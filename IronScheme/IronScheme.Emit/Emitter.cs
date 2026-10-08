using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Reflection.Emit;
using System.Reflection.Metadata;
using System.Reflection.Metadata.Ecma335;
using System.Reflection.PortableExecutable;
using System.Runtime.Loader;
using System.Security.Cryptography;
using System.Diagnostics.SymbolStore;

namespace IronScheme.Emit
{
  public enum EmitMode
  {
    /// <summary>PersistedAssemblyBuilder → dll 文件（确定性：MVID 与时间戳由内容哈希得出）。</summary>
    Persisted,
    /// <summary>AssemblyBuilder.RunAndCollect，用于 eval。</summary>
    InMemory,
  }

  /// <summary>
  /// Lcil → 程序集（designs/04-lcil-and-emitter.md §4、§5）。不引用 IronScheme.Core 项目：
  /// 运行时类型按名字从已加载或 references 中的程序集解析；互操作规则调用 Core 的 TypeResolver / Interop。
  /// </summary>
  public sealed partial class LcilEmitter
  {
    /// <summary>额外的程序集查找目录（命令行 -r）；默认含发射器所在目录。</summary>
    public static readonly List<string> ProbeDirectories = new List<string> { AppContext.BaseDirectory };

    static LcilEmitter()
    {
      AssemblyLoadContext.Default.Resolving += (ctx, name) =>
      {
        foreach (var dir in ProbeDirectories)
        {
          var p = Path.Combine(dir, name.Name + ".dll");
          if (File.Exists(p)) return ctx.LoadFromAssemblyPath(Path.GetFullPath(p));
        }
        return null;
      };
    }

    /// <summary>发射到内存并返回程序集。</summary>
    public static Assembly EmitInMemory(string lcil, string file = "lcil") => EmitInMemory(LcilParser.Parse(lcil, file));

    /// <summary>发射到内存；Lcil 用 (live-constants n) 时由 constants 直接提供常量对象。</summary>
    public static Assembly EmitInMemory(string lcil, string file, object[] constants) => EmitInMemory(LcilParser.Parse(lcil, file), constants);

    public static Assembly EmitInMemory(LcilAssembly a) => EmitInMemory(a, null);

    public static Assembly EmitInMemory(LcilAssembly a, object[] liveConstants)
    {
      if (a.LiveConstants >= 0 && (liveConstants == null || liveConstants.Length != a.LiveConstants))
        throw new LcilException($"{a.File}: expected {a.LiveConstants} live constants");
      var ab = AssemblyBuilder.DefineDynamicAssembly(new AssemblyName(a.Name), AssemblyBuilderAccess.RunAndCollect);
      var e = new LcilEmitter(a, ab.DefineDynamicModule(a.Name), false) { live = liveConstants };
      e.Build();
      return ab;
    }

    /// <summary>发射并保存为 dll；pdb 为真时同时生成 Portable PDB（同名 .pdb）。</summary>
    public static void Save(string lcil, string file, string outPath, bool pdb = false) => Save(LcilParser.Parse(lcil, file), outPath, pdb);

    public static void Save(LcilAssembly a, string outPath, bool pdb = false)
    {
      if (a.LiveConstants >= 0) throw new LcilException($"{a.File}: live constants can only be emitted in memory");
      var ab = new PersistedAssemblyBuilder(new AssemblyName(a.Name), typeof(object).Assembly);
      var mb = ab.DefineDynamicModule(a.Name);
      var e = new LcilEmitter(a, mb, pdb);
      e.Build();
      WritePE(ab, a, outPath, pdb);
    }

    readonly LcilAssembly asm;
    readonly ModuleBuilder module;
    readonly bool debug;
    readonly Dictionary<string, TypeBuilder> types = new Dictionary<string, TypeBuilder>();
    readonly Dictionary<LcilType, TypeBuilder> builders = new Dictionary<LcilType, TypeBuilder>();
    readonly Dictionary<string, List<(LcilMethod M, MethodBase B, Type[] P)>> methods = new Dictionary<string, List<(LcilMethod, MethodBase, Type[])>>();
    readonly Dictionary<(string, string), FieldBuilder> fields = new Dictionary<(string, string), FieldBuilder>();
    readonly List<Assembly> references = new List<Assembly>();
    readonly Dictionary<string, ISymbolDocumentWriter> documents = new Dictionary<string, ISymbolDocumentWriter>();
    FieldInfo constantsField;

    LcilEmitter(LcilAssembly asm, ModuleBuilder module, bool debug)
    {
      this.asm = asm;
      this.module = module;
      this.debug = debug;
      foreach (var r in asm.References) references.Add(LoadReference(r));
      // 互操作类型名在已加载程序集中查找：被引用程序集的依赖（如 Core 引用的 Oyster.IntX）也要加载
      foreach (var a in references.ToList())
        foreach (var dep in a.GetReferencedAssemblies())
          try { Assembly.Load(dep); } catch (FileNotFoundException) { }
    }

    Exception Err(SNode pos, string msg) => new LcilException(pos != null ? $"{pos.Where(asm.File)}: {msg}" : $"{asm.File}: {msg}");

    static Assembly LoadReference(string name)
    {
      if (name.EndsWith(".dll", StringComparison.OrdinalIgnoreCase) && File.Exists(name)) return Assembly.LoadFrom(Path.GetFullPath(name));
      var loaded = AppDomain.CurrentDomain.GetAssemblies().FirstOrDefault(x => x.GetName().Name == name);
      if (loaded != null) return loaded;
      try { return Assembly.Load(new AssemblyName(name)); }
      catch (FileNotFoundException) { throw new LcilException($"referenced assembly not found: {name}"); }
    }

    // ———————————————— 类型解析 ————————————————

    /// <summary>Lcil 类型引用（§2.4）：本程序集的类型 → 全名查找；后缀 [] 与 &amp;。</summary>
    Type T(string name, SNode pos)
    {
      if (name.EndsWith("[]", StringComparison.Ordinal)) return T(name.Substring(0, name.Length - 2), pos).MakeArrayType();
      if (name.EndsWith("&", StringComparison.Ordinal)) return T(name.Substring(0, name.Length - 1), pos).MakeByRefType();
      if (types.TryGetValue(name, out var tb)) return tb;
      var t = Type.GetType(name);
      if (t != null) return t;
      foreach (var a in references.Concat(AppDomain.CurrentDomain.GetAssemblies()))
      {
        if (a.IsDynamic) continue;
        t = a.GetType(name);
        if (t != null && (t.IsPublic || t.IsNestedPublic)) return t;
      }
      throw Err(pos, "type not found: " + name);
    }

    Type[] Ts(IEnumerable<string> names, SNode pos) => names.Select(n => T(n, pos)).ToArray();

    // ———————————————— 定义 ————————————————

    void Build()
    {
      // 1. 类型：基类在本程序集中的先定义
      var pending = new List<LcilType>(asm.Types);
      while (pending.Count > 0)
      {
        var ready = pending.FirstOrDefault(t => !pending.Any(o => o.Name == t.Base));
        if (ready == null) throw Err(pending[0].Pos, "cyclic base types");
        pending.Remove(ready);
        DefineType(ready);
      }
      if (asm.ConstantCount > 0) DefineConstants();
      if (asm.EntryType != null) DefineEntry();
      // 2. 字段与方法签名
      foreach (var t in asm.Types)
      {
        var tb = builders[t];
        foreach (var f in t.Fields)
        {
          var fa = f.Attrs.Contains("private") ? FieldAttributes.Private : FieldAttributes.Public;
          if (f.IsStatic) fa |= FieldAttributes.Static;
          if (f.Attrs.Contains("readonly")) fa |= FieldAttributes.InitOnly;
          if (fields.ContainsKey((t.Name, f.Name))) throw Err(t.Pos, $"duplicate field {t.Name}::{f.Name}");
          fields[(t.Name, f.Name)] = tb.DefineField(f.Name, T(f.Type, t.Pos), fa);
        }
        foreach (var m in t.Methods) DefineMethod(t, tb, m);
      }
      // 3. 方法体
      foreach (var t in asm.Types)
        foreach (var (m, b, _) in methods[t.Name])
          if (m.Body.Count > 0) EmitBody(t, m, b);
      // 4. 完成类型（基类先）
      var done = new HashSet<string>();
      void Create(LcilType t)
      {
        if (!done.Add(t.Name)) return;
        var bt = asm.Types.FirstOrDefault(o => o.Name == t.Base);
        if (bt != null) Create(bt);
        builders[t].CreateType();
      }
      constantsType?.CreateType();
      foreach (var t in asm.Types) Create(t);
    }

    /// <summary>入口（04 §6）：校验 public static object M()，写程序集级属性 SchemeModule("类型", "方法")。</summary>
    void DefineEntry()
    {
      var t = asm.Types.FirstOrDefault(x => x.Name == asm.EntryType) ?? throw new LcilException($"{asm.File}: entry type not found: {asm.EntryType}");
      var m = t.Methods.FirstOrDefault(x => x.Name == asm.EntryMethod);
      if (m == null || !m.IsStatic || m.IsCctor || m.Params.Count != 0 || m.Ret != "System.Object" || m.Attrs.Contains("private"))
        throw Err(m?.Pos ?? t.Pos, $"entry {asm.EntryType}::{asm.EntryMethod} must be a public static method with no parameters returning System.Object");
      var attr = LoadReference("IronScheme.Core").GetType("IronScheme.Core.SchemeModuleAttribute", true);
      var ctor = attr.GetConstructor(new[] { typeof(string), typeof(string) });
      ((AssemblyBuilder)module.Assembly).SetCustomAttribute(new CustomAttributeBuilder(ctor, new object[] { asm.EntryType, asm.EntryMethod }));
    }

    void DefineType(LcilType t)
    {
      var ta = TypeAttributes.Public | TypeAttributes.BeforeFieldInit;
      if (t.Attrs.Contains("sealed")) ta |= TypeAttributes.Sealed;
      if (t.Attrs.Contains("abstract")) ta |= TypeAttributes.Abstract;
      if (t.Attrs.Contains("interface")) ta = TypeAttributes.Public | TypeAttributes.Interface | TypeAttributes.Abstract;
      var parent = t.Attrs.Contains("interface") ? null : T(t.Base, t.Pos);
      var tb = module.DefineType(t.Name, ta, parent, Ts(t.Interfaces, t.Pos));
      types[t.Name] = tb;
      builders[t] = tb;
      methods[t.Name] = new List<(LcilMethod, MethodBase, Type[])>();
    }

    void DefineMethod(LcilType t, TypeBuilder tb, LcilMethod m)
    {
      var ps = Ts(m.Params, m.Pos);
      MethodBase b;
      if (m.IsCctor) b = tb.DefineTypeInitializer();
      else if (m.IsCtor)
      {
        var ca = (m.Attrs.Contains("private") ? MethodAttributes.Private : MethodAttributes.Public) | MethodAttributes.HideBySig;
        b = tb.DefineConstructor(ca, CallingConventions.Standard, ps);
      }
      else
      {
        var ma = (m.Attrs.Contains("private") ? MethodAttributes.Private : MethodAttributes.Public) | MethodAttributes.HideBySig;
        if (m.IsStatic) ma |= MethodAttributes.Static;
        if (m.Attrs.Contains("virtual")) ma |= MethodAttributes.Virtual | MethodAttributes.NewSlot;
        if (m.Attrs.Contains("override")) ma |= MethodAttributes.Virtual;
        if (m.Attrs.Contains("abstract")) ma |= MethodAttributes.Virtual | MethodAttributes.Abstract | MethodAttributes.NewSlot;
        b = tb.DefineMethod(m.Name, ma, T(m.Ret, m.Pos), ps);
      }
      if (methods[t.Name].Any(x => x.M.Name == m.Name && x.P.SequenceEqual(ps)))
        throw Err(m.Pos, $"duplicate method {t.Name}::{m.Name}");
      methods[t.Name].Add((m, b, ps));
    }

    // ———————————————— 成员引用 ————————————————

    MethodBase Method(MethodRef r, SNode pos)
    {
      var ps = Ts(r.Params, pos);
      MethodBase found = null;
      if (methods.TryGetValue(r.Type, out var own))
        found = own.FirstOrDefault(x => (x.B is ConstructorInfo ? x.M.IsCctor ? ".cctor" : ".ctor" : x.M.Name) == r.Name && x.P.SequenceEqual(ps)).B;
      if (found == null)
      {
        var t = T(r.Type, pos);
        if (t is TypeBuilder) t = t.BaseType;   // 继承来的成员：在基类中找
        const BindingFlags all = BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static | BindingFlags.Instance;
        if (r.Name == ".ctor") found = t.GetConstructor(all, null, ps, null);
        else
        {
          for (var s = t; s != null && found == null; s = s.BaseType)
            found = s is TypeBuilder ? null : s.GetMethod(r.Name, all | BindingFlags.DeclaredOnly, null, ps, null);
        }
      }
      if (found == null) throw Err(pos, "method not found: " + r);
      if (found is MethodInfo mi && r.Name != ".ctor")
      {
        var ret = T(r.Ret, pos);
        if (mi.ReturnType != ret) throw Err(pos, $"return type mismatch for {r}: {mi.ReturnType} vs {ret}");
      }
      return found;
    }

    FieldInfo Field(FieldRef r, SNode pos)
    {
      if (fields.TryGetValue((r.Type, r.Name), out var fb)) return fb;
      var t = T(r.Type, pos);
      if (t is TypeBuilder) t = t.BaseType;
      var f = t?.GetField(r.Name, BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static | BindingFlags.Instance | BindingFlags.FlattenHierarchy);
      return f ?? throw Err(pos, $"field not found: {r.Type}::{r.Name}");
    }

    // ———————————————— 方法体 ————————————————

    sealed class BodyContext
    {
      public ILGenerator IL;
      public LcilMethod M;
      public Dictionary<string, Label> Labels = new Dictionary<string, Label>();
      public ISymbolDocumentWriter Doc;
      public string[] Namespaces;
      // 互操作用的临时局部变量（object），按需分配、可复用
      public List<LocalBuilder> Temps = new List<LocalBuilder>();
    }

    void EmitBody(LcilType t, LcilMethod m, MethodBase b)
    {
      var il = b is ConstructorBuilder cb ? cb.GetILGenerator() : ((MethodBuilder)b).GetILGenerator();
      var cx = new BodyContext { IL = il, M = m, Namespaces = m.Namespaces.ToArray() };
      foreach (var l in m.Locals) il.DeclareLocal(T(l, m.Pos));
      if (debug && m.Source != null)
      {
        if (!documents.TryGetValue(m.Source, out var doc)) documents[m.Source] = doc = module.DefineDocument(m.Source);
        cx.Doc = doc;
      }
      void DefineLabels(List<Instr> list)
      {
        foreach (var ins in list)
        {
          if (ins.Kind == InstrKind.Label) cx.Labels[(string)ins.Operand] = il.DefineLabel();
          else if (ins.Kind == InstrKind.Try)
          {
            DefineLabels(ins.TryBody);
            foreach (var c in ins.Catches) DefineLabels(c.Body);
            if (ins.Finally != null) DefineLabels(ins.Finally);
          }
        }
      }
      DefineLabels(m.Body);
      Instrs(cx, m.Body);
    }

    void Instrs(BodyContext cx, List<Instr> list)
    {
      foreach (var ins in list) Instruction(cx, ins);
    }

    static readonly Dictionary<string, OpCode> longForms = new Dictionary<string, OpCode>();

    static OpCode LongForm(OpCode op)
    {
      if (op.OperandType != OperandType.ShortInlineBrTarget) return op;
      lock (longForms)
      {
        if (!longForms.TryGetValue(op.Name, out var l))
          longForms[op.Name] = l = LcilParser.TryGetOpCode(op.Name.Substring(0, op.Name.Length - 2), out var x) ? x : op;
        return l;
      }
    }

    void Instruction(BodyContext cx, Instr ins)
    {
      var il = cx.IL;
      switch (ins.Kind)
      {
        case InstrKind.Label: il.MarkLabel(cx.Labels[(string)ins.Operand]); return;
        case InstrKind.Tail: il.Emit(OpCodes.Tailcall); return;
        case InstrKind.Line:
          if (cx.Doc != null) il.MarkSequencePoint(cx.Doc, ins.L1, ins.C1, ins.L2, ins.C2);
          return;
        case InstrKind.LdConst:
          il.Emit(OpCodes.Ldsfld, constantsField);
          EmitInt(il, (int)ins.Operand);
          il.Emit(OpCodes.Ldelem_Ref);
          return;
        case InstrKind.Try:
          il.BeginExceptionBlock();
          Instrs(cx, ins.TryBody);
          foreach (var (type, body) in ins.Catches)
          {
            il.BeginCatchBlock(T(type, ins.Pos));
            Instrs(cx, body);
          }
          if (ins.Finally != null)
          {
            il.BeginFinallyBlock();
            Instrs(cx, ins.Finally);
          }
          il.EndExceptionBlock();
          return;
        case InstrKind.Clr: Clr(cx, ins); return;
      }

      var op = ins.OpCode;
      switch (op.OperandType)
      {
        case OperandType.InlineNone: il.Emit(op); break;
        case OperandType.ShortInlineI:
        case OperandType.InlineI:
          if (op == OpCodes.Ldc_I4 || op == OpCodes.Ldc_I4_S) EmitInt(il, checked((int)(long)ins.Operand));
          else if (op.OperandType == OperandType.ShortInlineI) il.Emit(op, checked((byte)(long)ins.Operand));
          else il.Emit(op, checked((int)(long)ins.Operand));
          break;
        case OperandType.InlineI8: il.Emit(op, (long)ins.Operand); break;
        case OperandType.ShortInlineR: il.Emit(op, (float)(double)ins.Operand); break;
        case OperandType.InlineR: il.Emit(op, (double)ins.Operand); break;
        case OperandType.InlineString: il.Emit(op, (string)ins.Operand); break;
        case OperandType.ShortInlineVar:
        case OperandType.InlineVar: EmitVar(il, op, (int)ins.Operand); break;
        case OperandType.ShortInlineBrTarget:
        case OperandType.InlineBrTarget: il.Emit(LongForm(op), cx.Labels[(string)ins.Operand]); break;
        case OperandType.InlineSwitch: il.Emit(op, ((string[])ins.Operand).Select(l => cx.Labels[l]).ToArray()); break;
        case OperandType.InlineType:
        case OperandType.InlineTok: il.Emit(op, T((string)ins.Operand, ins.Pos)); break;
        case OperandType.InlineField: il.Emit(op, Field((FieldRef)ins.Operand, ins.Pos)); break;
        case OperandType.InlineMethod:
          var mb = Method((MethodRef)ins.Operand, ins.Pos);
          if (mb is ConstructorInfo ci) il.Emit(op, ci); else il.Emit(op, (MethodInfo)mb);
          break;
        default: throw Err(ins.Pos, "unsupported instruction: " + op.Name);
      }
    }

    static void EmitInt(ILGenerator il, int n)
    {
      switch (n)
      {
        case -1: il.Emit(OpCodes.Ldc_I4_M1); return;
        case 0: il.Emit(OpCodes.Ldc_I4_0); return;
        case 1: il.Emit(OpCodes.Ldc_I4_1); return;
        case 2: il.Emit(OpCodes.Ldc_I4_2); return;
        case 3: il.Emit(OpCodes.Ldc_I4_3); return;
        case 4: il.Emit(OpCodes.Ldc_I4_4); return;
        case 5: il.Emit(OpCodes.Ldc_I4_5); return;
        case 6: il.Emit(OpCodes.Ldc_I4_6); return;
        case 7: il.Emit(OpCodes.Ldc_I4_7); return;
        case 8: il.Emit(OpCodes.Ldc_I4_8); return;
      }
      if (n >= sbyte.MinValue && n <= sbyte.MaxValue) il.Emit(OpCodes.Ldc_I4_S, (sbyte)n);
      else il.Emit(OpCodes.Ldc_I4, n);
    }

    /// <summary>参数 / 局部变量指令：按下标选最短格式。</summary>
    static void EmitVar(ILGenerator il, OpCode op, int i)
    {
      string name = op.Name.EndsWith(".s", StringComparison.Ordinal) ? op.Name.Substring(0, op.Name.Length - 2) : op.Name;
      if (i <= 3 && (name == "ldarg" || name == "ldloc" || name == "stloc"))
      {
        LcilParser.TryGetOpCode(name + "." + i, out var shortOp);
        il.Emit(shortOp);
        return;
      }
      LcilParser.TryGetOpCode(name, out var longOp);
      if (i <= 255 && LcilParser.TryGetOpCode(name + ".s", out var sOp)) il.Emit(sOp, (byte)i);
      else il.Emit(longOp, (short)i);
    }

    // ———————————————— 保存 ————————————————

    static void WritePE(PersistedAssemblyBuilder ab, LcilAssembly a, string outPath, bool pdb)
    {
      MetadataBuilder metadata = ab.GenerateMetadata(out BlobBuilder ilStream, out BlobBuilder fieldData, out MetadataBuilder pdbBuilder);
      // 确定性：程序集内容哈希 → MVID / 时间戳 / PDB ID（iron-003）
      Func<IEnumerable<Blob>, BlobContentId> idProvider = blobs =>
      {
        using var h = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        foreach (var blob in blobs) h.AppendData(blob.GetBytes());
        return BlobContentId.FromHash(h.GetHashAndReset());
      };
      DebugDirectoryBuilder debug = null;
      if (pdb)
      {
        var pdbBlob = new BlobBuilder();
        var portablePdb = new PortablePdbBuilder(pdbBuilder, metadata.GetRowCounts(), default, idProvider);
        BlobContentId pdbId = portablePdb.Serialize(pdbBlob);
        string pdbPath = Path.ChangeExtension(outPath, ".pdb");
        using (var fs = File.Create(pdbPath)) pdbBlob.WriteContentTo(fs);
        debug = new DebugDirectoryBuilder();
        debug.AddCodeViewEntry(Path.GetFileName(pdbPath), pdbId, portablePdb.FormatVersion);
      }
      var pe = new ManagedPEBuilder(
        new PEHeaderBuilder(imageCharacteristics: Characteristics.Dll | Characteristics.ExecutableImage),
        new MetadataRootBuilder(metadata), ilStream, fieldData,
        debugDirectoryBuilder: debug, deterministicIdProvider: idProvider);
      var peBlob = new BlobBuilder();
      pe.Serialize(peBlob);
      var image = peBlob.ToArray();
      MakeDeterministic(image);
      File.WriteAllBytes(outPath, image);
    }

    /// <summary>
    /// GenerateMetadata 生成随机 MVID：清零 MVID 与 COFF 时间戳 → SHA256 → 回填（iron-003 验证）。
    /// 相同 Lcil 因此得到逐字节相同的 dll。
    /// </summary>
    static void MakeDeterministic(byte[] image)
    {
      int mvid, ts;
      using (var pe = new PEReader(new MemoryStream(image)))
      {
        var md = pe.GetMetadataReader();
        int heap = md.GetHeapMetadataOffset(HeapIndex.Guid);
        int index = MetadataTokens.GetHeapOffset(md.GetModuleDefinition().Mvid);   // GUID 堆索引从 1 开始
        mvid = pe.PEHeaders.MetadataStartOffset + heap + (index - 1) * 16;
        ts = pe.PEHeaders.CoffHeaderStartOffset + 4;
      }
      Array.Clear(image, mvid, 16);
      Array.Clear(image, ts, 4);
      byte[] hash = SHA256.HashData(image);
      Array.Copy(hash, 0, image, mvid, 16);
      Array.Copy(hash, 16, image, ts, 4);
    }
  }
}

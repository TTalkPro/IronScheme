// iron-003：验证 .NET 10 上设计依赖的能力
//   tail     —— 生成代码中 tail. 前缀在虚调用、参数个数变化、栈传参时是否可靠
//   save     —— PersistedAssemblyBuilder 保存（含托管资源、try/finally、可选 PDB）
//   load     —— 另一进程加载已保存程序集并运行
//   dynamic  —— 内存程序集（RunAndCollect）引用已保存程序集中的类型
//   determinism —— 同一输入两次保存是否逐字节相同
using System.Diagnostics;
using System.Diagnostics.SymbolStore;
using System.Reflection;
using System.Reflection.Emit;
using System.Reflection.Metadata;
using System.Reflection.Metadata.Ecma335;
using System.Reflection.PortableExecutable;
using System.Security.Cryptography;

public abstract class Procedure
{
    public virtual object Invoke1(object a) => throw new InvalidOperationException("arity 1");
    public virtual object Invoke3(object a, object b, object c) => throw new InvalidOperationException("arity 3");
}

public static class RT
{
    public static readonly object True = true;
    public static readonly object False = false;
    public static int FinallyCount;
}

public static class Program
{
    const int Depth = 10_000_000;

    public static int Main(string[] args)
    {
        string cmd = args.Length > 0 ? args[0] : "all";
        string dir = Path.Combine(AppContext.BaseDirectory, "out");
        Directory.CreateDirectory(dir);
        switch (cmd)
        {
            case "tail": return RunTailTests(Gen.BuildInMemory(withTail: true));
            case "notail": return RunTailTests(Gen.BuildInMemory(withTail: false)); // 对照：预期栈溢出
            case "save": Gen.SaveWithMetadata(Path.Combine(dir, "gen.dll"), withTail: true, pdb: true); Console.WriteLine("saved"); return 0;
            case "load": return RunTailTests(Assembly.LoadFrom(args[1]));
            case "dynamic": return DynamicReferencingSaved(args[1]);
            case "determinism": return Determinism(dir);
            default: Console.WriteLine("usage: tail|notail|save|load <dll>|dynamic <dll>|determinism"); return 2;
        }
    }

    // 在 1MB 栈的线程上跑，确保没有尾调用时必然溢出
    static int RunTailTests(Assembly asm)
    {
        int rc = 0;
        void Check(string name, Func<object> f, object expected)
        {
            object r = null; Exception err = null;
            var t = new Thread(() => { try { r = f(); } catch (Exception e) { err = e; } }, 1024 * 1024);
            var sw = Stopwatch.StartNew(); t.Start(); t.Join(); sw.Stop();
            bool ok = err == null && Equals(r, expected);
            if (!ok) rc = 1;
            Console.WriteLine($"{(ok ? "PASS" : "FAIL")} {name} = {r ?? err?.GetType().Name} ({sw.ElapsedMilliseconds} ms)");
        }

        Procedure Make(string type) => (Procedure)Activator.CreateInstance(asm.GetType(type));
        void Link(Procedure a, Procedure b) { a.GetType().GetField("other").SetValue(a, b); }

        var even = Make("Even"); var odd = Make("Odd"); Link(even, odd); Link(odd, even);
        Check("虚调用相互尾递归 Invoke1↔Invoke1", () => even.Invoke1(Depth), true);

        var a = Make("A"); var b = Make("B"); Link(a, b); Link(b, a);
        Check("参数个数变化 Invoke1→Invoke3→Invoke1", () => a.Invoke1(Depth), true);

        var s = asm.GetType("S");
        Check("静态尾调用 1 参→2 参", () => s.GetMethod("Loop").Invoke(null, new object[] { Depth }), true);
        Check("静态尾调用 1 参→8 参（栈传参）", () => s.GetMethod("LoopWide").Invoke(null, new object[] { Depth }), true);

        RT.FinallyCount = 0;
        Check("try/finally 内调用", () => s.GetMethod("WithFinally").Invoke(null, new object[] { even, 10 }), true);
        Console.WriteLine($"     finally 执行次数 = {RT.FinallyCount}");
        return rc;
    }

    static int DynamicReferencingSaved(string path)
    {
        var saved = Assembly.LoadFrom(path);
        var evenType = saved.GetType("Even");
        var ab = AssemblyBuilder.DefineDynamicAssembly(new AssemblyName("dyn"), AssemblyBuilderAccess.RunAndCollect);
        var mb = ab.DefineDynamicModule("dyn");
        // 内存程序集中的类型调用已保存程序集中的 Even（经 Procedure 虚调用，带 tail.）
        var tb = mb.DefineType("DynCaller", TypeAttributes.Public | TypeAttributes.Class);
        var m = tb.DefineMethod("Run", MethodAttributes.Public | MethodAttributes.Static, typeof(object), new[] { typeof(Procedure), typeof(object) });
        var il = m.GetILGenerator();
        il.Emit(OpCodes.Ldarg_0); il.Emit(OpCodes.Ldarg_1);
        il.Emit(OpCodes.Tailcall);
        il.Emit(OpCodes.Callvirt, typeof(Procedure).GetMethod("Invoke1"));
        il.Emit(OpCodes.Ret);
        var t = tb.CreateType();
        var even = (Procedure)Activator.CreateInstance(evenType);
        var odd = (Procedure)Activator.CreateInstance(saved.GetType("Odd"));
        evenType.GetField("other").SetValue(even, odd);
        saved.GetType("Odd").GetField("other").SetValue(odd, even);
        var r = t.GetMethod("Run").Invoke(null, new object[] { even, 1001 });
        Console.WriteLine($"{(Equals(r, false) ? "PASS" : "FAIL")} 内存程序集调用已保存程序集中的类型 = {r}");
        return Equals(r, false) ? 0 : 1;
    }

    static int Determinism(string dir)
    {
        string p1 = Path.Combine(dir, "det1.dll"), p2 = Path.Combine(dir, "det2.dll");
        Gen.SaveSimple(p1); Gen.SaveSimple(p2);
        bool simpleSame = File.ReadAllBytes(p1).AsSpan().SequenceEqual(File.ReadAllBytes(p2));
        Console.WriteLine($"Save() 两次逐字节相同: {simpleSame}");

        string q1 = Path.Combine(dir, "detm1.dll"), q2 = Path.Combine(dir, "detm2.dll");
        Gen.SaveWithMetadata(q1, true, pdb: false); Gen.SaveWithMetadata(q2, true, pdb: false);
        bool metaSame = File.ReadAllBytes(q1).AsSpan().SequenceEqual(File.ReadAllBytes(q2));
        Console.WriteLine($"GenerateMetadata + 确定性 ID 两次逐字节相同: {metaSame}");
        if (!metaSame) DiffReport(q1, q2);
        Console.WriteLine($"  MVID 文件偏移: 0x{MvidOffset(File.ReadAllBytes(q1)):X}");

        foreach (var p in new[] { p1, p2, q1, q2 }) MakeDeterministic(p);
        bool fixedSimple = File.ReadAllBytes(p1).AsSpan().SequenceEqual(File.ReadAllBytes(p2));
        bool fixedMeta = File.ReadAllBytes(q1).AsSpan().SequenceEqual(File.ReadAllBytes(q2));
        Console.WriteLine($"后处理（MVID、时间戳由内容哈希生成）后逐字节相同: Save()={fixedSimple}, GenerateMetadata={fixedMeta}");
        var asm = Assembly.LoadFrom(q1);
        Console.WriteLine($"后处理后仍可加载: MVID={asm.ManifestModule.ModuleVersionId}");
        return 0;
    }

    // 定位模块表 MVID 在文件中的偏移
    static int MvidOffset(byte[] image)
    {
        using var pe = new PEReader(new MemoryStream(image));
        var md = pe.GetMetadataReader();
        var mvidHandle = md.GetModuleDefinition().Mvid;
        int heapOffset = md.GetHeapMetadataOffset(HeapIndex.Guid);
        int index = MetadataTokens.GetHeapOffset(mvidHandle); // GUID 堆索引从 1 开始
        int mdStart = pe.PEHeaders.MetadataStartOffset;
        return mdStart + heapOffset + (index - 1) * 16;
    }

    // 清零 MVID 与 COFF 时间戳 → SHA256 → 回填，保证相同输入得到相同文件
    static void MakeDeterministic(string path)
    {
        var image = File.ReadAllBytes(path);
        int mvid = MvidOffset(image);
        int ts;
        using (var pe = new PEReader(new MemoryStream(image))) ts = pe.PEHeaders.CoffHeaderStartOffset + 4;
        Array.Clear(image, mvid, 16); Array.Clear(image, ts, 4);
        byte[] hash = SHA256.HashData(image);
        Array.Copy(hash, 0, image, mvid, 16);
        Array.Copy(hash, 16, image, ts, 4);
        File.WriteAllBytes(path, image);
    }

    static void DiffReport(string a, string b)
    {
        var x = File.ReadAllBytes(a); var y = File.ReadAllBytes(b);
        int n = 0;
        for (int i = 0; i < Math.Min(x.Length, y.Length) && n < 5; i++)
            if (x[i] != y[i]) { Console.WriteLine($"  差异偏移 0x{i:X}"); n++; }
        Console.WriteLine($"  长度 {x.Length} / {y.Length}");
    }
}

static class Gen
{
    static readonly MethodInfo Invoke1 = typeof(Procedure).GetMethod("Invoke1");
    static readonly MethodInfo Invoke3 = typeof(Procedure).GetMethod("Invoke3");
    static readonly FieldInfo True = typeof(RT).GetField("True");
    static readonly FieldInfo False = typeof(RT).GetField("False");
    static readonly FieldInfo FinallyCount = typeof(RT).GetField("FinallyCount");

    public static Assembly BuildInMemory(bool withTail)
    {
        var ab = AssemblyBuilder.DefineDynamicAssembly(new AssemblyName("gen"), AssemblyBuilderAccess.RunAndCollect);
        var mb = ab.DefineDynamicModule("gen");
        DefineTypes(mb, withTail, null);
        return ab;
    }

    public static void SaveSimple(string path)
    {
        var ab = new PersistedAssemblyBuilder(new AssemblyName("gen"), typeof(object).Assembly);
        DefineTypes(ab.DefineDynamicModule("gen"), true, null);
        ab.Save(path);
    }

    // 走 GenerateMetadata：可加托管资源、确定性 ID、Portable PDB
    public static void SaveWithMetadata(string path, bool withTail, bool pdb)
    {
        var ab = new PersistedAssemblyBuilder(new AssemblyName("gen"), typeof(object).Assembly);
        var mb = ab.DefineDynamicModule("gen");
        var doc = pdb ? mb.DefineDocument("gen.scm") : null;
        DefineTypes(mb, withTail, doc);

        MetadataBuilder metadata = ab.GenerateMetadata(out BlobBuilder ilStream, out BlobBuilder fieldData, out MetadataBuilder pdbBuilder);

        // 托管资源（模拟 fasl 常量块）
        var resources = new BlobBuilder();
        byte[] payload = System.Text.Encoding.UTF8.GetBytes("fasl-constants");
        resources.WriteInt32(payload.Length); resources.WriteBytes(payload);
        metadata.AddManifestResource(ManifestResourceAttributes.Public, metadata.GetOrAddString("constants.fasl"), default, 0);

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
            string pdbPath = Path.ChangeExtension(path, ".pdb");
            using (var fs = File.Create(pdbPath)) pdbBlob.WriteContentTo(fs);
            debug = new DebugDirectoryBuilder();
            debug.AddCodeViewEntry(Path.GetFileName(pdbPath), pdbId, portablePdb.FormatVersion);
        }

        var pe = new ManagedPEBuilder(
            new PEHeaderBuilder(imageCharacteristics: Characteristics.Dll),
            new MetadataRootBuilder(metadata), ilStream, fieldData,
            managedResources: resources, debugDirectoryBuilder: debug,
            deterministicIdProvider: idProvider);
        var peBlob = new BlobBuilder();
        pe.Serialize(peBlob);
        using var f = File.Create(path);
        peBlob.WriteContentTo(f);
    }

    static void DefineTypes(ModuleBuilder mb, bool withTail, ISymbolDocumentWriter doc)
    {
        // Even / Odd：虚调用相互尾递归
        foreach (var (name, zeroResult) in new[] { ("Even", True), ("Odd", False) })
        {
            var tb = mb.DefineType(name, TypeAttributes.Public | TypeAttributes.Sealed, typeof(Procedure));
            var other = tb.DefineField("other", typeof(Procedure), FieldAttributes.Public);
            var m = tb.DefineMethod("Invoke1", MethodAttributes.Public | MethodAttributes.Virtual | MethodAttributes.HideBySig,
                typeof(object), new[] { typeof(object) });
            var il = m.GetILGenerator();
            if (doc != null) il.MarkSequencePoint(doc, 1, 1, 1, 20);
            var nonzero = il.DefineLabel();
            il.Emit(OpCodes.Ldarg_1); il.Emit(OpCodes.Unbox_Any, typeof(int)); il.Emit(OpCodes.Brtrue, nonzero);
            il.Emit(OpCodes.Ldsfld, zeroResult); il.Emit(OpCodes.Ret);
            il.MarkLabel(nonzero);
            il.Emit(OpCodes.Ldarg_0); il.Emit(OpCodes.Ldfld, other);
            il.Emit(OpCodes.Ldarg_1); il.Emit(OpCodes.Unbox_Any, typeof(int)); il.Emit(OpCodes.Ldc_I4_1); il.Emit(OpCodes.Sub);
            il.Emit(OpCodes.Box, typeof(int));
            if (withTail) il.Emit(OpCodes.Tailcall);
            il.Emit(OpCodes.Callvirt, Invoke1);
            il.Emit(OpCodes.Ret);
            tb.DefineMethodOverride(m, Invoke1);
            tb.CreateType();
        }

        // A.Invoke1(n) → B.Invoke3(n-1, null, null) → A.Invoke1(...)
        {
            var tb = mb.DefineType("A", TypeAttributes.Public | TypeAttributes.Sealed, typeof(Procedure));
            var other = tb.DefineField("other", typeof(Procedure), FieldAttributes.Public);
            var m = tb.DefineMethod("Invoke1", MethodAttributes.Public | MethodAttributes.Virtual | MethodAttributes.HideBySig,
                typeof(object), new[] { typeof(object) });
            var il = m.GetILGenerator();
            var nonzero = il.DefineLabel();
            il.Emit(OpCodes.Ldarg_1); il.Emit(OpCodes.Unbox_Any, typeof(int)); il.Emit(OpCodes.Brtrue, nonzero);
            il.Emit(OpCodes.Ldsfld, True); il.Emit(OpCodes.Ret);
            il.MarkLabel(nonzero);
            il.Emit(OpCodes.Ldarg_0); il.Emit(OpCodes.Ldfld, other);
            il.Emit(OpCodes.Ldarg_1); il.Emit(OpCodes.Unbox_Any, typeof(int)); il.Emit(OpCodes.Ldc_I4_1); il.Emit(OpCodes.Sub);
            il.Emit(OpCodes.Box, typeof(int));
            il.Emit(OpCodes.Ldnull); il.Emit(OpCodes.Ldnull);
            if (withTail) il.Emit(OpCodes.Tailcall);
            il.Emit(OpCodes.Callvirt, Invoke3);
            il.Emit(OpCodes.Ret);
            tb.DefineMethodOverride(m, Invoke1);
            tb.CreateType();
        }
        {
            var tb = mb.DefineType("B", TypeAttributes.Public | TypeAttributes.Sealed, typeof(Procedure));
            var other = tb.DefineField("other", typeof(Procedure), FieldAttributes.Public);
            var m = tb.DefineMethod("Invoke3", MethodAttributes.Public | MethodAttributes.Virtual | MethodAttributes.HideBySig,
                typeof(object), new[] { typeof(object), typeof(object), typeof(object) });
            var il = m.GetILGenerator();
            il.Emit(OpCodes.Ldarg_0); il.Emit(OpCodes.Ldfld, other); il.Emit(OpCodes.Ldarg_1);
            if (withTail) il.Emit(OpCodes.Tailcall);
            il.Emit(OpCodes.Callvirt, Invoke1);
            il.Emit(OpCodes.Ret);
            tb.DefineMethodOverride(m, Invoke3);
            tb.CreateType();
        }

        // 静态方法：Loop(1 参) → Loop2(2 参)；LoopWide(1 参) → Wide8(8 参，部分走栈)
        {
            var tb = mb.DefineType("S", TypeAttributes.Public | TypeAttributes.Abstract | TypeAttributes.Sealed);
            var loop = tb.DefineMethod("Loop", MethodAttributes.Public | MethodAttributes.Static, typeof(object), new[] { typeof(object) });
            var loop2 = tb.DefineMethod("Loop2", MethodAttributes.Public | MethodAttributes.Static, typeof(object), new[] { typeof(object), typeof(object) });
            var wide = tb.DefineMethod("LoopWide", MethodAttributes.Public | MethodAttributes.Static, typeof(object), new[] { typeof(object) });
            var objs8 = Enumerable.Repeat(typeof(object), 8).ToArray();
            var wide8 = tb.DefineMethod("Wide8", MethodAttributes.Public | MethodAttributes.Static, typeof(object), objs8);

            void Countdown(MethodBuilder m, Action<ILGenerator> callNext)
            {
                var il = m.GetILGenerator(); var nz = il.DefineLabel();
                il.Emit(OpCodes.Ldarg_0); il.Emit(OpCodes.Unbox_Any, typeof(int)); il.Emit(OpCodes.Brtrue, nz);
                il.Emit(OpCodes.Ldsfld, True); il.Emit(OpCodes.Ret);
                il.MarkLabel(nz);
                il.Emit(OpCodes.Ldarg_0); il.Emit(OpCodes.Unbox_Any, typeof(int)); il.Emit(OpCodes.Ldc_I4_1); il.Emit(OpCodes.Sub);
                il.Emit(OpCodes.Box, typeof(int));
                callNext(il);
                il.Emit(OpCodes.Ret);
            }
            Countdown(loop, il => { il.Emit(OpCodes.Ldnull); if (withTail) il.Emit(OpCodes.Tailcall); il.Emit(OpCodes.Call, loop2); });
            { var il = loop2.GetILGenerator(); il.Emit(OpCodes.Ldarg_0); if (withTail) il.Emit(OpCodes.Tailcall); il.Emit(OpCodes.Call, loop); il.Emit(OpCodes.Ret); }
            Countdown(wide, il => { for (int i = 0; i < 7; i++) il.Emit(OpCodes.Ldnull); if (withTail) il.Emit(OpCodes.Tailcall); il.Emit(OpCodes.Call, wide8); });
            { var il = wide8.GetILGenerator(); il.Emit(OpCodes.Ldarg_0); if (withTail) il.Emit(OpCodes.Tailcall); il.Emit(OpCodes.Call, wide); il.Emit(OpCodes.Ret); }

            // try/finally：结果存局部变量，leave 出区域后返回（区域内不能用 tail.）
            var wf = tb.DefineMethod("WithFinally", MethodAttributes.Public | MethodAttributes.Static, typeof(object), new[] { typeof(Procedure), typeof(object) });
            {
                var il = wf.GetILGenerator(); var res = il.DeclareLocal(typeof(object)); var end = il.DefineLabel();
                il.BeginExceptionBlock();
                il.Emit(OpCodes.Ldarg_0); il.Emit(OpCodes.Ldarg_1); il.Emit(OpCodes.Callvirt, Invoke1); il.Emit(OpCodes.Stloc, res);
                il.BeginFinallyBlock();
                il.Emit(OpCodes.Ldsfld, FinallyCount); il.Emit(OpCodes.Ldc_I4_1); il.Emit(OpCodes.Add); il.Emit(OpCodes.Stsfld, FinallyCount);
                il.EndExceptionBlock();
                il.Emit(OpCodes.Ldloc, res); il.Emit(OpCodes.Ret);
            }
            tb.CreateType();
        }
    }
}

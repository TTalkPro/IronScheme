using System;
using System.Collections.Generic;
using System.Linq;

namespace IronScheme.Core
{
  /// <summary>
  /// 记录实例：RTD + 字段数组（父类型的字段在前）。所有记录都用这一种表示，不再运行时生成 CLR 类型。
  /// 设计：designs/02-runtime.md §7。
  /// </summary>
  public class Record
  {
    public readonly RecordTypeDescriptor Rtd;
    public readonly object[] Fields;

    public Record(RecordTypeDescriptor rtd, object[] fields)
    {
      Rtd = rtd;
      Fields = fields;
    }

    public override string ToString() => Rtd == null ? "#<record>" : $"#<record {Rtd.Name}>";
  }

  /// <summary>R6RS 记录类型描述符。成员名与旧运行时一致（build/records/inspection.sls 直接访问）。</summary>
  public sealed class RecordTypeDescriptor
  {
    public string Name { get; }
    /// <summary>uid：符号（非生成性）、字符串（旧系统中的生成性 uid）或 #f。</summary>
    public object uid;
    public RecordTypeDescriptor Parent { get; }
    public FieldDescriptor[] Fields { get; }

    internal readonly bool @sealed, opaque, generative;
    public object Sealed => RT.Bool(@sealed);
    public object Opaque => RT.Bool(opaque);
    public object Generative => RT.Bool(generative);

    /// <summary>是否条件类型：名字为 &amp;condition 或父类型是条件类型（与旧系统相同的判定）。</summary>
    public bool IsCondition { get; }

    /// <summary>父类型字段总数（本类型字段在字段数组中的起始下标）。</summary>
    public int FieldOffset { get; }
    public int TotalFieldCount => FieldOffset + Fields.Length;

    // ancestors[d] 为深度 d 的祖先（含自身），使子类型判断为 O(1)
    readonly RecordTypeDescriptor[] ancestors;

    public Procedure Predicate { get; }

    internal RecordTypeDescriptor(string name, RecordTypeDescriptor parent, object uid, bool @sealed, bool opaque, bool generative,
      IList<(string Name, bool Mutable)> fields)
    {
      Name = name;
      Parent = parent;
      this.uid = uid;
      this.@sealed = @sealed;
      this.opaque = opaque || (parent?.opaque ?? false);   // R6RS：父类型不透明则子类型也不透明
      this.generative = generative;
      IsCondition = name == "&condition" || (parent?.IsCondition ?? false);
      FieldOffset = parent?.TotalFieldCount ?? 0;
      ancestors = parent == null ? new[] { this } : parent.ancestors.Append(this).ToArray();
      Fields = fields.Select((f, i) => new FieldDescriptor(this, f.Name, f.Mutable, FieldOffset + i)).ToArray();
      Predicate = new RecordPredicate(this);
    }

    /// <summary>obj 是否本类型或其子类型的实例。</summary>
    public bool IsInstance(object obj) =>
      obj is Record r && r.Rtd != null && r.Rtd.ancestors.Length > ancestors.Length - 1 && ReferenceEquals(r.Rtd.ancestors[ancestors.Length - 1], this);

    public IEnumerable<FieldDescriptor> GetAllFields() =>
      Parent == null ? Fields : Parent.GetAllFields().Concat(Fields);

    internal Record Instantiate(object[] fields) => IsCondition ? new Condition(this, fields) : new Record(this, fields);

    public override string ToString() => "rtd: " + Name;

    sealed class RecordPredicate : Procedure
    {
      readonly RecordTypeDescriptor rtd;
      public RecordPredicate(RecordTypeDescriptor rtd) { this.rtd = rtd; }
      public override string Name => rtd.Name + "?";
      public override object Invoke1(object obj) => RT.Bool(rtd.IsInstance(obj));
    }
  }

  /// <summary>字段描述符。成员名与旧运行时一致。</summary>
  public sealed class FieldDescriptor
  {
    public string Name { get; }
    internal readonly bool mutable;
    public object Mutable => RT.Bool(mutable);
    /// <summary>在记录字段数组中的绝对下标。</summary>
    public int Index { get; }
    public Procedure Accessor { get; }
    /// <summary>可变字段为修改器过程；不可变字段为 #f（与旧系统一致）。</summary>
    public object Mutator { get; }
    /// <summary>字段类型：统一表示下都是 object（旧系统可声明 CLR 类型）。</summary>
    public Type Type => typeof(object);

    internal FieldDescriptor(RecordTypeDescriptor rtd, string name, bool mutable, int index)
    {
      Name = name;
      this.mutable = mutable;
      Index = index;
      Accessor = new FieldAccessor(rtd, this);
      Mutator = mutable ? new FieldMutator(rtd, this) : RT.False;
    }

    public override string ToString() => "fd: " + Name;

    sealed class FieldAccessor : Procedure
    {
      readonly RecordTypeDescriptor rtd; readonly FieldDescriptor fd;
      public FieldAccessor(RecordTypeDescriptor rtd, FieldDescriptor fd) { this.rtd = rtd; this.fd = fd; }
      public override string Name => rtd.Name + "-" + fd.Name;
      public override object Invoke1(object obj) =>
        rtd.IsInstance(obj) ? ((Record)obj).Fields[fd.Index] : Errors.AssertionViolation(Name, "not a record of type " + rtd.Name, obj);
    }

    sealed class FieldMutator : Procedure
    {
      readonly RecordTypeDescriptor rtd; readonly FieldDescriptor fd;
      public FieldMutator(RecordTypeDescriptor rtd, FieldDescriptor fd) { this.rtd = rtd; this.fd = fd; }
      public override string Name => rtd.Name + "-" + fd.Name + "-set!";
      public override object Invoke2(object obj, object value)
      {
        if (!rtd.IsInstance(obj)) return Errors.AssertionViolation(Name, "not a record of type " + rtd.Name, obj);
        ((Record)obj).Fields[fd.Index] = value;
        return Unspecified.Instance;
      }
    }
  }

  /// <summary>R6RS 记录构造描述符。字段名与旧运行时一致。</summary>
  public sealed class RecordConstructorDescriptor
  {
    public RecordTypeDescriptor type;
    public Procedure protocol;
    public RecordConstructorDescriptor parent;

    public override string ToString() => "rcd: " + type.Name;
  }

  /// <summary>记录的过程层与检视层原语。</summary>
  public class Records : Builtins
  {
    static readonly Dictionary<string, RecordTypeDescriptor> nongenerative = new Dictionary<string, RecordTypeDescriptor>();
    static readonly object gate = new object();

    static readonly Symbol mutableSym = Symbol.Intern("mutable"), immutableSym = Symbol.Intern("immutable");

    /// <summary>(make-record-type-descriptor name parent uid sealed? opaque? fields)</summary>
    [Primitive("make-record-type-descriptor")]
    public static object MakeRecordTypeDescriptor(object name, object parent, object uid, object issealed, object isopaque, object fields)
    {
      string n = RequiresNotNull<Symbol>(name).Name;
      var prtd = parent as RecordTypeDescriptor;
      if (prtd == null && IsTrue(parent))
        return AssertionViolation("make-record-type-descriptor", "parent is not a record type descriptor", parent);
      if (prtd != null && prtd.@sealed)
        return AssertionViolation("make-record-type-descriptor", "parent record type is sealed", parent);

      string id = uid is Symbol s ? s.Name : uid as string;
      bool @sealed = RequiresNotNull<bool>(issealed);
      bool opaque = RequiresNotNull<bool>(isopaque);

      var specs = new List<(string, bool)>();
      foreach (var f in RequiresNotNull<object[]>(fields))
      {
        var c = f as Cons;
        var kind = c?.car as Symbol;
        var fname = (c?.cdr as Cons)?.car as Symbol;
        if (fname == null || (kind != mutableSym && kind != immutableSym))
          return AssertionViolation("make-record-type-descriptor", "invalid field specifier", f);
        specs.Add((fname.Name, kind == mutableSym));
      }

      lock (gate)
      {
        // 非生成性：同名同 uid 返回已登记的同一 RTD（fasl 重建常量时依赖这一点）
        if (id != null && nongenerative.TryGetValue(n + id, out var existing))
          return existing;

        var rtd = new RecordTypeDescriptor(n, prtd, IsTrue(uid) ? uid : RT.False, @sealed, opaque,
          generative: id == null || uid is string, specs);
        if (id != null) nongenerative[n + id] = rtd;
        if (rtd.IsCondition) Symbol.Intern(n + "-rtd").Value = rtd;   // 条件类型：与旧系统一样登记 <名字>-rtd
        return rtd;
      }
    }

    /// <summary>带字段类型的版本（旧系统用于生成强类型字段）。统一表示下忽略类型。</summary>
    [Primitive("make-record-type-descriptor")]
    public static object MakeRecordTypeDescriptorTyped(object name, object parent, object uid, object issealed, object isopaque, object fields, object fieldtypes) =>
      MakeRecordTypeDescriptor(name, parent, uid, issealed, isopaque, fields);

    /// <summary>按 uid 取已登记的非生成性 RTD（fasl 常量重建使用，iron-020）。</summary>
    public static RecordTypeDescriptor LookupNongenerative(string name, string uid)
    {
      lock (gate) return nongenerative.TryGetValue(name + uid, out var r) ? r : null;
    }

    [Primitive("make-record-constructor-descriptor")]
    public static object MakeRecordConstructorDescriptor(object rtd, object parent_constructor_descriptor, object protocol)
    {
      var t = RequiresNotNull<RecordTypeDescriptor>(rtd);
      var rcd = new RecordConstructorDescriptor
      {
        type = t,
        protocol = protocol as Procedure,
        parent = parent_constructor_descriptor as RecordConstructorDescriptor,
      };
      if (t.IsCondition) Symbol.Intern(t.Name + "-rcd").Value = rcd;     // 与旧系统一样登记 <名字>-rcd
      return rcd;
    }

    [Primitive("record-predicate")]
    public static object RecordPredicate(object rtd) => RequiresNotNull<RecordTypeDescriptor>(rtd).Predicate;

    [Primitive("record-accessor")]
    public static object RecordAccessor(object rtd, object k)
    {
      var t = RequiresNotNull<RecordTypeDescriptor>(rtd);
      int i = RequiresNotNull<int>(k);
      if (i < 0 || i >= t.Fields.Length) return AssertionViolation("record-accessor", "invalid field index", rtd, k);
      return t.Fields[i].Accessor;
    }

    /// <summary>不可变字段返回 #f（与旧系统一致）。</summary>
    [Primitive("record-mutator")]
    public static object RecordMutator(object rtd, object k)
    {
      var t = RequiresNotNull<RecordTypeDescriptor>(rtd);
      int i = RequiresNotNull<int>(k);
      if (i < 0 || i >= t.Fields.Length) return AssertionViolation("record-mutator", "invalid field index", rtd, k);
      return t.Fields[i].Mutator;
    }

    [Primitive("record?")]
    public static object IsRecord(object obj) => GetBool(obj is Record r && r.Rtd != null && !r.Rtd.opaque);

    [Primitive("record-rtd")]
    public static object RecordRtd(object obj) =>
      obj is Record r && r.Rtd != null && !r.Rtd.opaque ? r.Rtd : AssertionViolation("record-rtd", "not a record", obj);

    /// <summary>(record-constructor rcd)</summary>
    [Primitive("record-constructor")]
    public static object RecordConstructor(object cd)
    {
      var rcd = RequiresNotNull<RecordConstructorDescriptor>(cd);
      for (var r = rcd; r != null; r = r.parent)
        if (r.protocol != null) return new ProtocolConstructor(rcd);
      return new DefaultConstructor(rcd.type);
    }

    /// <summary>没有 protocol：参数依次为全部字段（父类型字段在前）。</summary>
    sealed class DefaultConstructor : VariadicProcedure
    {
      readonly RecordTypeDescriptor rtd;
      public DefaultConstructor(RecordTypeDescriptor rtd) { this.rtd = rtd; }
      public override string Name => "make-" + rtd.Name;
      public override object InvokeN(object[] args)
      {
        if (args.Length != rtd.TotalFieldCount)
          return Errors.AssertionViolation(rtd.Name,
            $"Incorrect number of arguments, expected {rtd.TotalFieldCount} got {args.Length}", args);
        return rtd.Instantiate((object[])args.Clone());
      }
    }

    /// <summary>
    /// 有 protocol：先创建空实例，再沿构造描述符链调用各层 protocol。
    /// 每层的 "new" 过程：无父层时直接填写本层字段；有父层时接受父层参数、调用父层链，返回填写本层字段的过程。
    /// protocol 为 #f 的层用 R6RS 默认 protocol（参数中父层字段在前）。
    /// </summary>
    sealed class ProtocolConstructor : VariadicProcedure
    {
      readonly RecordConstructorDescriptor rcd;
      public ProtocolConstructor(RecordConstructorDescriptor rcd) { this.rcd = rcd; }
      public override string Name => "make-" + rcd.type.Name;

      public override object InvokeN(object[] args)
      {
        var instance = rcd.type.Instantiate(new object[rcd.type.TotalFieldCount]);
        Chain(rcd, instance).InvokeN(args);
        return instance;
      }

      static Procedure Chain(RecordConstructorDescriptor level, Record instance)
      {
        var fill = new FieldFiller(level.type, instance);
        Procedure newProc = level.parent == null
          ? fill
          : new ParentThenFill(Chain(level.parent, instance), fill, level.parent.type.TotalFieldCount);
        if (level.protocol != null)
          return (Procedure)level.protocol.Invoke1(newProc);
        // 默认 protocol
        return level.parent == null ? fill : new DefaultProtocol(newProc, level.parent.type.TotalFieldCount);
      }
    }

    /// <summary>填写某一层自己的字段。</summary>
    sealed class FieldFiller : VariadicProcedure
    {
      readonly RecordTypeDescriptor rtd; readonly Record instance;
      public FieldFiller(RecordTypeDescriptor rtd, Record instance) { this.rtd = rtd; this.instance = instance; }
      public override string Name => rtd.Name;
      public override object InvokeN(object[] args)
      {
        if (args.Length != rtd.Fields.Length)
          return Errors.AssertionViolation(rtd.Name,
            $"Incorrect number of arguments, expected {rtd.Fields.Length} got {args.Length}", args);
        Array.Copy(args, 0, instance.Fields, rtd.FieldOffset, args.Length);
        return instance;
      }
    }

    /// <summary>有父层时的 "new"：(n parent-arg ...) 调用父层链，返回填写本层字段的过程。</summary>
    sealed class ParentThenFill : VariadicProcedure
    {
      readonly Procedure parentChain, fill; readonly int parentCount;
      public ParentThenFill(Procedure parentChain, Procedure fill, int parentCount) { this.parentChain = parentChain; this.fill = fill; this.parentCount = parentCount; }
      public override object InvokeN(object[] args)
      {
        parentChain.InvokeN(args);
        return fill;
      }
    }

    /// <summary>R6RS 默认 protocol（有父层时）：参数前 parentCount 个给父层，其余给本层。</summary>
    sealed class DefaultProtocol : VariadicProcedure
    {
      readonly Procedure n; readonly int parentCount;
      public DefaultProtocol(Procedure n, int parentCount) { this.n = n; this.parentCount = parentCount; }
      public override object InvokeN(object[] args)
      {
        if (args.Length < parentCount)
          return Errors.AssertionViolation("record-constructor", "too few arguments", args);
        var p = (Procedure)n.InvokeN(args[..parentCount]);
        return p.InvokeN(args[parentCount..]);
      }
    }
  }
}

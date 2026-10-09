using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.CompilerServices;
using System.Text;
using BigInteger = Oyster.Math.IntX;

namespace IronScheme.Core
{
  /// <summary>
  /// 二进制 fasl（designs/04-lcil-and-emitter.md §3）：编译产物的常量表与 serialize-port 的格式。
  /// 发射器（IronScheme.Emit.FaslEncoder）把中立编码写成同一格式；这里负责读回对象，并能把对象直接写出。
  /// 符号按名字驻留；记录类型按 uid 取回已登记的同一 RTD；def / ref 表示共享与环。
  /// </summary>
  public static class Fasl
  {
    public const byte Version = 1;
    static readonly byte[] Magic = Encoding.ASCII.GetBytes("ISFASL");

    // 标签（与 IronScheme.Emit.FaslEncoder 一致）
    public const byte Nil = 0x00, True = 0x01, False = 0x02, Unspec = 0x03, EofTag = 0x04,
      Fix = 0x10, Big = 0x11, Rat = 0x12, Flo = 0x13, Cpx = 0x14,
      Chr = 0x20, Str = 0x21, MStr = 0x22, Sym = 0x23,
      Pair = 0x30, List = 0x31, Vec = 0x32, Bv = 0x33,
      Rtd = 0x40, Rec = 0x41, Ann = 0x42, EqHt = 0x43, Cnd = 0x44, Rcd = 0x45,
      Def = 0x50, Ref = 0x51;

    #region 读

    /// <summary>常量表：发射器把 base64 编码的 fasl 写进模块类型初始化器。</summary>
    public static object[] ReadTable(string base64) => (object[])Read(Convert.FromBase64String(base64));

    public static object Read(byte[] data)
    {
      using var r = new BinaryReader(new MemoryStream(data));
      return Read(r);
    }

    public static object Read(BinaryReader r)
    {
      var magic = r.ReadBytes(Magic.Length);
      if (!magic.AsSpan().SequenceEqual(Magic)) throw new InvalidDataException("not a fasl stream");
      byte v = r.ReadByte();
      if (v != Version) throw new InvalidDataException("unsupported fasl version " + v);
      return new Reader(r).Object();
    }

    sealed class Reader
    {
      readonly BinaryReader r;
      readonly Dictionary<int, object> defs = new Dictionary<int, object>();
      int pendingDef = -1;

      public Reader(BinaryReader r) { this.r = r; }

      int Count() => r.Read7BitEncodedInt();

      string String()
      {
        int n = Count();
        var cs = new char[n];
        for (int i = 0; i < n; i++) cs[i] = (char)r.ReadUInt16();
        return new string(cs);
      }

      // 复合对象在读子项之前登记，环才能指回自己
      T Register<T>(int def, T obj)
      {
        if (def >= 0) defs[def] = obj;
        return obj;
      }

      public object Object()
      {
        int def = pendingDef;
        pendingDef = -1;
        byte tag = r.ReadByte();
        switch (tag)
        {
          case Nil: return Register<object>(def, null);
          case True: return Register(def, RT.True);
          case False: return Register(def, RT.False);
          case Unspec: return Register<object>(def, Unspecified.Instance);
          case EofTag: return Register(def, Builtins.EofObject());
          case Fix: return Register(def, RT.Box(r.ReadInt32()));
          case Big:
          case Rat: return Register(def, Builtins.ParseNumber(String()) ?? throw new InvalidDataException("bad number in fasl"));
          case Flo: return Register<object>(def, BitConverter.Int64BitsToDouble(r.ReadInt64()));
          case Cpx:
          {
            var re = Object();
            var im = Object();
            return Register(def, Builtins.MakeRectangular(re, im));
          }
          case Chr:
          {
            int cp = r.ReadInt32();
            return Register<object>(def, cp < 0x10000 ? (object)(char)cp : new SchemeChar(cp));
          }
          case Str: return Register<object>(def, String());
          case MStr: return Register<object>(def, new StringBuilder(String()));
          case Sym: return Register<object>(def, Symbol.Intern(String()));
          case Pair:
          {
            var c = Register(def, new Cons(null, null));
            c.car = Object();
            c.cdr = Object();
            return c;
          }
          case List:
          {
            int n = Count();
            if (n == 0) return Register(def, Object());
            var head = Register(def, new Cons(null, null));
            var c = head;
            for (int i = 0; i < n; i++)
            {
              if (i > 0) { var next = new Cons(null, null); c.cdr = next; c = next; }
              c.car = Object();
            }
            c.cdr = Object();
            return head;
          }
          case Vec:
          {
            var v = Register(def, new object[Count()]);
            for (int i = 0; i < v.Length; i++) v[i] = Object();
            return v;
          }
          case Bv:
          {
            int n = Count();
            return Register<object>(def, r.ReadBytes(n));
          }
          case Rtd:
          {
            string name = String();
            object uid = Object();
            object parent = Object();
            bool @sealed = r.ReadByte() != 0, opaque = r.ReadByte() != 0;
            var fields = new object[Count()];
            for (int i = 0; i < fields.Length; i++)
            {
              bool mutable = r.ReadByte() != 0;
              fields[i] = Cons.FromArray(Symbol.Intern(mutable ? "mutable" : "immutable"), Symbol.Intern(String()));
            }
            // 非生成性：按名字与 uid 取回已登记的同一 RTD；生成性：新建（同一 fasl 内经 def/ref 共享）
            return Register(def, Records.MakeRecordTypeDescriptor(Symbol.Intern(name), parent, uid, RT.Bool(@sealed), RT.Bool(opaque), fields));
          }
          case Rec:
          {
            var rtd = Object() as RecordTypeDescriptor ?? throw new InvalidDataException("record without type descriptor in fasl");
            var fields = new object[Count()];
            var rec = Register(def, rtd.Instantiate(fields));
            for (int i = 0; i < fields.Length; i++) fields[i] = Object();
            return rec;
          }
          case Ann:
          {
            var expr = Object();
            var source = Object();
            var stripped = Object();
            return Register(def, Builtins.MakeAnnotation(expr, source, stripped));
          }
          case EqHt:
          {
            // eq 哈希表（make-eq-hashtable 即 System.Collections.Hashtable）；'() 键按 Hashtables 的约定包装
            int n = Count();
            var ht = Register(def, new System.Collections.Hashtable(Math.Max(n, 1)));
            for (int i = 0; i < n; i++)
            {
              var k = Object();
              ht[Hashtables.ToNull(k)] = Object();
            }
            return ht;
          }
          case Rcd:
          {
            // 记录构造描述符（没有 protocol 的）：nanopass 把展开时创建的 RCD 作为常量写进生成的代码
            var rtd = Object();
            var parent = Object();
            return Register(def, Records.MakeRecordConstructorDescriptor(rtd, parent, RT.False));
          }
          case Cnd:
          {
            // 复合条件：由简单条件组成，构造时就要有组成部分，所以读完再登记（组成部分不会指回它）
            var parts = new object[Count()];
            for (int i = 0; i < parts.Length; i++) parts[i] = Object();
            return Register(def, new CompoundCondition(parts));
          }
          case Def:
            pendingDef = Count();
            return Object();
          case Ref:
          {
            int n = Count();
            return defs.TryGetValue(n, out var o) ? o : throw new InvalidDataException("fasl reference to undefined object " + n);
          }
          default: throw new InvalidDataException($"bad fasl tag 0x{tag:X2}");
        }
      }
    }

    #endregion

    #region serialize-port / deserialize-port（取代旧版 BinaryFormatter，iron-008 转来）

    [Primitive("serialize-port")]
    public static object SerializePort(object obj, object port)
    {
      var stream = Errors.RequiresType<Stream>(port, "serialize-port");
      using (var w = new BinaryWriter(stream, Encoding.UTF8, true)) Write(w, obj);
      return Unspecified.Instance;
    }

    [Primitive("deserialize-port")]
    public static object DeserializePort(object port)
    {
      var stream = Errors.RequiresType<Stream>(port, "deserialize-port");
      using var r = new BinaryReader(stream, Encoding.UTF8, true);
      return Read(r);
    }

    #endregion

    #region 写

    public static byte[] Write(object obj)
    {
      var ms = new MemoryStream();
      using (var w = new BinaryWriter(ms, Encoding.UTF8, true)) Write(w, obj);
      return ms.ToArray();
    }

    public static void Write(BinaryWriter w, object obj)
    {
      w.Write(Magic);
      w.Write(Version);
      new Writer(w).Run(obj);
    }

    /// <summary>可共享的对象：eq? 身份有意义，出现多次时用 def/ref。</summary>
    static bool Shareable(object o) =>
      o is Cons || o is object[] || o is byte[] || o is Record || o is RecordTypeDescriptor || o is RecordConstructorDescriptor
      || o is StringBuilder || o is Annotation || IsEqHashtable(o);

    /// <summary>只支持 eq 哈希表（类型恰为 Hashtable）；带自定义哈希函数的表无法序列化。</summary>
    static bool IsEqHashtable(object o) => o != null && o.GetType() == typeof(System.Collections.Hashtable);

    sealed class Writer
    {
      readonly BinaryWriter w;
      readonly Dictionary<object, int> counts = new Dictionary<object, int>(ReferenceEqualityComparer.Instance);
      readonly Dictionary<object, int> ids = new Dictionary<object, int>(ReferenceEqualityComparer.Instance);

      public Writer(BinaryWriter w) { this.w = w; }

      public void Run(object root)
      {
        Count(root);
        Object(root);
      }

      // 第一遍：统计可共享对象出现的次数（已见过的不再深入，所以环也能结束）
      void Count(object o)
      {
        while (true)
        {
          if (!Shareable(o)) return;
          counts.TryGetValue(o, out int n);
          counts[o] = n + 1;
          if (n > 0) return;
          switch (o)
          {
            case Cons c: Count(c.car); o = c.cdr; continue;   // 沿表尾循环，长表不递归
            case object[] v: foreach (var e in v) Count(e); return;
            case CompoundCondition cc: foreach (var e in cc.conds) Count(e); return;
            case RecordConstructorDescriptor rcd: Count(rcd.type); Count(rcd.parent); return;
            case Record r: Count(r.Rtd); foreach (var e in r.Fields) Count(e); return;
            case RecordTypeDescriptor t: Count(t.uid); Count(t.Parent); return;
            case Annotation a: Count(a.expression); Count(a.source); Count(a.stripped); return;
            case System.Collections.Hashtable h:
              foreach (System.Collections.DictionaryEntry e in h) { Count(Hashtables.FromNull(e.Key)); Count(e.Value); }
              return;
            default: return;
          }
        }
      }

      bool Shared(object o) => counts.TryGetValue(o, out int n) && n > 1;

      void String(string s)
      {
        w.Write7BitEncodedInt(s.Length);
        foreach (char c in s) w.Write((ushort)c);
      }

      void Object(object o)
      {
        if (Shareable(o))
        {
          if (ids.TryGetValue(o, out int id)) { w.Write(Ref); w.Write7BitEncodedInt(id); return; }
          if (Shared(o))
          {
            id = ids.Count;
            ids[o] = id;
            w.Write(Def);
            w.Write7BitEncodedInt(id);
          }
        }
        switch (o)
        {
          case null: w.Write(Nil); return;
          case bool b: w.Write(b ? True : False); return;
          case Unspecified _: w.Write(Unspec); return;
          case int i: w.Write(Fix); w.Write(i); return;
          case BigInteger _:
          case Fraction _: w.Write(o is Fraction ? Rat : Big); String(o.ToString()); return;   // 十进制，"n/d"；Fraction 的 IConvertible.ToString 未实现
          case double d: w.Write(Flo); w.Write(BitConverter.DoubleToInt64Bits(d)); return;
          case ComplexFraction cf: w.Write(Cpx); Object(Builtins.ToExact(cf.Real)); Object(Builtins.ToExact(cf.Imag)); return;
          case Complex64 cd: w.Write(Cpx); Object(cd.Real); Object(cd.Imag); return;
          case char c: w.Write(Chr); w.Write((int)c); return;
          case SchemeChar sc: w.Write(Chr); w.Write(sc.Value); return;
          case string s: w.Write(Str); String(s); return;
          case StringBuilder sb: w.Write(MStr); String(sb.ToString()); return;
          case Symbol sym: w.Write(Sym); String(sym.Name); return;
          case Cons c:
          {
            // 表尾中未被共享的序对连成一段，用 List 写出
            var items = new List<object> { c.car };
            object tail = c.cdr;
            while (tail is Cons next && !Shared(next)) { items.Add(next.car); tail = next.cdr; }
            if (items.Count == 1) { w.Write(Pair); Object(c.car); Object(c.cdr); return; }
            w.Write(List);
            w.Write7BitEncodedInt(items.Count);
            foreach (var e in items) Object(e);
            Object(tail);
            return;
          }
          case object[] v: w.Write(Vec); w.Write7BitEncodedInt(v.Length); foreach (var e in v) Object(e); return;
          case byte[] bv: w.Write(Bv); w.Write7BitEncodedInt(bv.Length); w.Write(bv); return;
          case RecordTypeDescriptor t:
            w.Write(Rtd);
            String(t.Name);
            Object(t.generative && !(t.uid is string) ? RT.False : t.uid);
            Object((object)t.Parent ?? RT.False);
            w.Write((byte)(t.@sealed ? 1 : 0));
            w.Write((byte)(t.opaque ? 1 : 0));
            w.Write7BitEncodedInt(t.Fields.Length);
            foreach (var f in t.Fields) { w.Write((byte)(f.mutable ? 1 : 0)); String(f.Name); }
            return;
          case RecordConstructorDescriptor rcd when rcd.protocol == null:
            w.Write(Rcd);
            Object(rcd.type);
            Object((object)rcd.parent ?? RT.False);
            return;
          case CompoundCondition cc:
            w.Write(Cnd);
            w.Write7BitEncodedInt(cc.conds.Length);
            foreach (var e in cc.conds) Object(e);
            return;
          case Record r when r.Rtd != null:
            w.Write(Rec);
            Object(r.Rtd);
            w.Write7BitEncodedInt(r.Fields.Length);
            foreach (var e in r.Fields) Object(e);
            return;
          case Annotation a: w.Write(Ann); Object(a.expression); Object(a.source); Object(a.stripped); return;
          case System.Collections.Hashtable h when IsEqHashtable(h):
          {
            w.Write(EqHt);
            w.Write7BitEncodedInt(h.Count);
            foreach (var (k, v) in SortedEntries(h)) { Object(k); Object(v); }
            return;
          }
        }
        if (ReferenceEquals(o, Builtins.EofObject())) { w.Write(EofTag); return; }
        Errors.AssertionViolation("fasl-write", "cannot serialize object", o);
      }
    }

    /// <summary>条目按键排序（符号、字符串、数按其文本），使相同内容的表写出相同字节；其余键保持枚举顺序。</summary>
    static List<(object, object)> SortedEntries(System.Collections.Hashtable h)
    {
      var list = new List<(object Key, object Value)>();
      foreach (System.Collections.DictionaryEntry e in h) list.Add((Hashtables.FromNull(e.Key), e.Value));
      static string SortKey(object k) => k switch { Symbol s => "s" + s.Name, string s => "t" + s, int i => "i" + i.ToString("D11"), _ => null };
      if (list.TrueForAll(e => SortKey(e.Key) != null)) list.Sort((a, b) => string.CompareOrdinal(SortKey(a.Key), SortKey(b.Key)));
      return list.ConvertAll(e => (e.Key, e.Value));
    }

    #endregion
  }
}

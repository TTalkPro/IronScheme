using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;

namespace IronScheme.Emit
{
  /// <summary>
  /// 常量的中立编码（designs/04-lcil-and-emitter.md §3）→ 二进制 fasl。格式与 IronScheme.Core.Fasl 一致，
  /// 这里不引用 Core，标签值重复定义。
  /// </summary>
  public static class FaslEncoder
  {
    const byte Nil = 0x00, True = 0x01, False = 0x02, Unspec = 0x03, EofTag = 0x04,
      Fix = 0x10, Big = 0x11, Rat = 0x12, Flo = 0x13, Cpx = 0x14,
      Chr = 0x20, Str = 0x21, MStr = 0x22, Sym = 0x23,
      Pair = 0x30, List = 0x31, Vec = 0x32, Bv = 0x33,
      Rtd = 0x40, Rec = 0x41, Ann = 0x42, EqHt = 0x43, Cnd = 0x44,
      Def = 0x50, Ref = 0x51;

    /// <summary>常量表（各项编码）→ fasl：整个表写成一个向量，def / ref 编号在全表内共享。</summary>
    public static byte[] EncodeTable(IList<SNode> constants, string file)
    {
      var ms = new MemoryStream();
      using (var w = new BinaryWriter(ms, Encoding.UTF8, true))
      {
        w.Write(Encoding.ASCII.GetBytes("ISFASL"));
        w.Write((byte)1);
        w.Write(Vec);
        w.Write7BitEncodedInt(constants.Count);
        var e = new Encoder(w, file);
        foreach (var c in constants) e.Encode(c);
        e.CheckRefs();
      }
      return ms.ToArray();
    }

    sealed class Encoder
    {
      readonly BinaryWriter w;
      readonly string file;
      readonly HashSet<long> defined = new HashSet<long>();
      readonly List<(long, SNode)> refs = new List<(long, SNode)>();

      public Encoder(BinaryWriter w, string file) { this.w = w; this.file = file; }

      LcilException Err(SNode n, string msg) => new LcilException($"{n.Where(file)}: constant: {msg}");

      void String(string s)
      {
        w.Write7BitEncodedInt(s.Length);
        foreach (char c in s) w.Write((ushort)c);
      }

      static string StrOf(SNode n) => (n as SStr)?.Value;

      void Arity(SList l, int n)
      {
        if (l.Count - 1 != n) throw Err(l, $"{l.Head} takes {n} operand(s)");
      }

      string StrArg(SList l, int i) => StrOf(l[i]) ?? throw Err(l[i], "expected a string");
      long IntArg(SList l, int i) => l[i] is SInt n ? n.Value : throw Err(l[i], "expected an integer");

      public void CheckRefs()
      {
        // ref 必须指向已定义（或正在定义、即环）的编号
        foreach (var (id, pos) in refs)
          if (!defined.Contains(id)) throw Err(pos, $"reference to undefined object {id}");
      }

      public void Encode(SNode n)
      {
        if (!(n is SList l) || l.Head == null) throw Err(n, "expected an encoding like (fix 1)");
        switch (l.Head)
        {
          case "nil": Arity(l, 0); w.Write(Nil); return;
          case "true": Arity(l, 0); w.Write(True); return;
          case "false": Arity(l, 0); w.Write(False); return;
          case "unspecified": Arity(l, 0); w.Write(Unspec); return;
          case "eof": Arity(l, 0); w.Write(EofTag); return;
          case "fix":
          {
            Arity(l, 1);
            long v = IntArg(l, 1);
            if (v < int.MinValue || v > int.MaxValue) throw Err(l, "fixnum out of range");
            w.Write(Fix); w.Write((int)v);
            return;
          }
          case "big": Arity(l, 1); w.Write(Big); String(StrArg(l, 1)); return;
          case "rat": Arity(l, 1); w.Write(Rat); String(StrArg(l, 1)); return;
          case "flo":
          {
            Arity(l, 1);
            if (!ulong.TryParse(StrArg(l, 1), NumberStyles.AllowHexSpecifier, CultureInfo.InvariantCulture, out ulong bits))
              throw Err(l[1], "flonum must be 16 hexadecimal digits (IEEE bits)");
            w.Write(Flo); w.Write(unchecked((long)bits));
            return;
          }
          case "cpx": Arity(l, 2); w.Write(Cpx); Encode(l[1]); Encode(l[2]); return;
          case "chr": Arity(l, 1); w.Write(Chr); w.Write((int)IntArg(l, 1)); return;
          case "str": Arity(l, 1); w.Write(Str); String(StrArg(l, 1)); return;
          case "mstr": Arity(l, 1); w.Write(MStr); String(StrArg(l, 1)); return;
          case "sym": case "gensym": Arity(l, 1); w.Write(Sym); String(StrArg(l, 1)); return;
          case "pair": Arity(l, 2); w.Write(Pair); Encode(l[1]); Encode(l[2]); return;
          case "list":
            w.Write(List); w.Write7BitEncodedInt(l.Count - 1);
            for (int i = 1; i < l.Count; i++) Encode(l[i]);
            w.Write(Nil);
            return;
          case "dlist":
            if (l.Count < 3) throw Err(l, "dlist needs at least one element and a tail");
            w.Write(List); w.Write7BitEncodedInt(l.Count - 2);
            for (int i = 1; i < l.Count; i++) Encode(l[i]);
            return;
          case "vec":
            w.Write(Vec); w.Write7BitEncodedInt(l.Count - 1);
            for (int i = 1; i < l.Count; i++) Encode(l[i]);
            return;
          case "bv":
          {
            Arity(l, 1);
            string hex = StrArg(l, 1);
            byte[] bytes;
            try { bytes = Convert.FromHexString(hex); } catch (FormatException) { throw Err(l[1], "bad hexadecimal bytevector"); }
            w.Write(Bv); w.Write7BitEncodedInt(bytes.Length); w.Write(bytes);
            return;
          }
          case "rtd":
          {
            // (rtd "名字" uid 父 sealed? opaque? ((mutable|immutable "字段") …))
            Arity(l, 6);
            w.Write(Rtd);
            String(StrArg(l, 1));
            Encode(l[2]);
            Encode(l[3]);
            w.Write((byte)(Bool(l[4]) ? 1 : 0));
            w.Write((byte)(Bool(l[5]) ? 1 : 0));
            var fields = l[6] as SList ?? throw Err(l[6], "expected a field list");
            w.Write7BitEncodedInt(fields.Count);
            foreach (var f in fields.Items)
            {
              if (!(f is SList fl) || fl.Count != 2 || (fl.Head != "mutable" && fl.Head != "immutable")) throw Err(f, "field must be (mutable \"name\") or (immutable \"name\")");
              w.Write((byte)(fl.Head == "mutable" ? 1 : 0));
              String(StrOf(fl[1]) ?? throw Err(fl[1], "expected a string"));
            }
            return;
          }
          case "rec":
            if (l.Count < 2) throw Err(l, "rec needs a type descriptor");
            w.Write(Rec); Encode(l[1]);
            w.Write7BitEncodedInt(l.Count - 2);
            for (int i = 2; i < l.Count; i++) Encode(l[i]);
            return;
          case "ann": Arity(l, 3); w.Write(Ann); Encode(l[1]); Encode(l[2]); Encode(l[3]); return;
          case "cnd":
            w.Write(Cnd); w.Write7BitEncodedInt(l.Count - 1);
            for (int i = 1; i < l.Count; i++) Encode(l[i]);
            return;
          case "eqht":
            if ((l.Count - 1) % 2 != 0) throw Err(l, "eqht needs key / value pairs");
            w.Write(EqHt); w.Write7BitEncodedInt((l.Count - 1) / 2);
            for (int i = 1; i < l.Count; i++) Encode(l[i]);
            return;
          case "def":
          {
            Arity(l, 2);
            long id = IntArg(l, 1);
            if (id < 0 || !defined.Add(id)) throw Err(l, $"duplicate or negative definition {id}");
            w.Write(Def); w.Write7BitEncodedInt((int)id); Encode(l[2]);
            return;
          }
          case "ref":
            Arity(l, 1);
            refs.Add((IntArg(l, 1), l));
            w.Write(Ref); w.Write7BitEncodedInt((int)IntArg(l, 1));
            return;
          default: throw Err(l, "unknown encoding: " + l.Head);
        }
      }

      bool Bool(SNode n) => n is SBool b ? b.Value : throw Err(n, "expected #t or #f");
    }
  }
}

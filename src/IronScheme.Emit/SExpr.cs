using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

namespace IronScheme.Emit
{
  // Lcil 的极简 S 表达式读取器（designs/04-lcil-and-emitter.md §2.1），不依赖 Scheme reader。
  // 每个节点带源位置，供校验报错。

  public abstract class SNode
  {
    public int Line, Col;
    public string Where(string file) => $"{file}:{Line}:{Col}";
  }

  public sealed class SList : SNode
  {
    public readonly List<SNode> Items = new List<SNode>();
    public int Count => Items.Count;
    public SNode this[int i] => Items[i];
    /// <summary>首项为符号时返回其名字，否则 null。</summary>
    public string Head => Items.Count > 0 && Items[0] is SSym s ? s.Name : null;
    public override string ToString() => "(" + string.Join(" ", Items) + ")";
  }

  public sealed class SSym : SNode
  {
    public readonly string Name;
    public SSym(string name) { Name = name; }
    public override string ToString() => Name;
  }

  public sealed class SStr : SNode
  {
    public readonly string Value;
    public SStr(string value) { Value = value; }
    public override string ToString() => "\"" + Value.Replace("\\", "\\\\").Replace("\"", "\\\"") + "\"";
  }

  public sealed class SInt : SNode
  {
    public readonly long Value;
    public SInt(long value) { Value = value; }
    public override string ToString() => Value.ToString(CultureInfo.InvariantCulture);
  }

  public sealed class SReal : SNode
  {
    public readonly double Value;
    public SReal(double value) { Value = value; }
    public override string ToString() => Value.ToString("R", CultureInfo.InvariantCulture);
  }

  public sealed class SBool : SNode
  {
    public readonly bool Value;
    public SBool(bool value) { Value = value; }
    public override string ToString() => Value ? "#t" : "#f";
  }

  public sealed class LcilException : Exception
  {
    public LcilException(string message) : base(message) { }
  }

  public sealed class SExprReader
  {
    readonly string text, file;
    int pos, line = 1, col = 1;

    public SExprReader(string text, string file) { this.text = text; this.file = file ?? "lcil"; }

    LcilException Error(string msg, int l, int c) => new LcilException($"{file}:{l}:{c}: {msg}");

    /// <summary>读全部数据。</summary>
    public List<SNode> ReadAll()
    {
      var r = new List<SNode>();
      while (true)
      {
        SkipAtmosphere();
        if (pos >= text.Length) return r;
        r.Add(ReadItem());
      }
    }

    int Peek() => pos < text.Length ? text[pos] : -1;

    char Next()
    {
      char c = text[pos++];
      if (c == '\n') { line++; col = 1; } else col++;
      return c;
    }

    void SkipAtmosphere()
    {
      while (pos < text.Length)
      {
        char c = text[pos];
        if (char.IsWhiteSpace(c)) Next();
        else if (c == ';') { while (pos < text.Length && text[pos] != '\n') Next(); }
        else if (c == '#' && pos + 1 < text.Length && text[pos + 1] == '|')
        {
          int l = line, cc = col;
          Next(); Next();
          while (true)
          {
            if (pos >= text.Length) throw Error("unterminated block comment", l, cc);
            if (text[pos] == '|' && pos + 1 < text.Length && text[pos + 1] == '#') { Next(); Next(); break; }
            Next();
          }
        }
        else return;
      }
    }

    SNode ReadItem()
    {
      SkipAtmosphere();
      int l = line, c = col;
      if (pos >= text.Length) throw Error("unexpected end of input", l, c);
      char ch = text[pos];
      SNode n;
      if (ch == '(' || ch == '[')
      {
        char close = ch == '(' ? ')' : ']';
        Next();
        var list = new SList();
        while (true)
        {
          SkipAtmosphere();
          if (pos >= text.Length) throw Error("unterminated list", l, c);
          if (text[pos] == ')' || text[pos] == ']')
          {
            if (text[pos] != close) throw Error("mismatched bracket", line, col);
            Next();
            break;
          }
          list.Items.Add(ReadItem());
        }
        n = list;
      }
      else if (ch == ')' || ch == ']') throw Error("unexpected '" + ch + "'", l, c);
      else if (ch == '"') n = ReadString(l, c);
      else n = ReadAtom(l, c);
      n.Line = l; n.Col = c;
      return n;
    }

    SNode ReadString(int l, int c)
    {
      Next();
      var sb = new StringBuilder();
      while (true)
      {
        if (pos >= text.Length) throw Error("unterminated string", l, c);
        char ch = Next();
        if (ch == '"') return new SStr(sb.ToString());
        if (ch != '\\') { sb.Append(ch); continue; }
        if (pos >= text.Length) throw Error("unterminated string", l, c);
        char e = Next();
        switch (e)
        {
          case '"': sb.Append('"'); break;
          case '\\': sb.Append('\\'); break;
          case 'n': sb.Append('\n'); break;
          case 'r': sb.Append('\r'); break;
          case 't': sb.Append('\t'); break;
          case 'x':
          {
            int semi = text.IndexOf(';', pos);
            if (semi < 0 || !int.TryParse(text.AsSpan(pos, semi - pos), NumberStyles.AllowHexSpecifier, CultureInfo.InvariantCulture, out int cp)
                || cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF))
              throw Error("bad \\x escape in string", line, col);
            sb.Append(char.ConvertFromUtf32(cp));
            while (pos <= semi) Next();
            break;
          }
          default: throw Error("unknown string escape \\" + e, line, col);
        }
      }
    }

    SNode ReadAtom(int l, int c)
    {
      int start = pos;
      while (pos < text.Length)
      {
        char ch = text[pos];
        if (char.IsWhiteSpace(ch) || ch == '(' || ch == ')' || ch == '[' || ch == ']' || ch == '"' || ch == ';') break;
        Next();
      }
      string s = text.Substring(start, pos - start);
      if (s == "#t") return new SBool(true);
      if (s == "#f") return new SBool(false);
      if (s.StartsWith("#x", StringComparison.Ordinal) || s.StartsWith("#X", StringComparison.Ordinal))
      {
        if (long.TryParse(s.AsSpan(2), NumberStyles.AllowHexSpecifier, CultureInfo.InvariantCulture, out long h)) return new SInt(h);
        throw Error("bad hexadecimal number: " + s, l, c);
      }
      if (s.Length > 0 && (char.IsDigit(s[0]) || ((s[0] == '-' || s[0] == '+' || s[0] == '.') && s.Length > 1 && (char.IsDigit(s[1]) || s[1] == '.'))))
      {
        if (long.TryParse(s, NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture, out long i)) return new SInt(i);
        if (double.TryParse(s, NumberStyles.Float, CultureInfo.InvariantCulture, out double d)) return new SReal(d);
        throw Error("bad number: " + s, l, c);
      }
      if (s.StartsWith("#", StringComparison.Ordinal)) throw Error("unsupported syntax: " + s, l, c);
      return new SSym(s);
    }
  }
}

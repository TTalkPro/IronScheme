using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Runtime.CompilerServices;
using System.Text;

namespace IronScheme.Core
{
  /// <summary>reader 的语法错误（带行列）。由原语层转换为 Scheme 的 lexical-error。</summary>
  public sealed class ReaderException : Exception
  {
    public int Line { get; }
    public int Column { get; }
    public ReaderException(string message, int line, int column) : base(message) { Line = line; Column = column; }
  }

  /// <summary>
  /// 手写递归下降 reader，取代 gplex/gppg 生成的分析器（设计 02 §8）。语法逐条对照旧的
  /// IronScheme/Compiler/IronScheme.lex 与 IronScheme.y：
  /// <list type="bullet">
  /// <item>R6RS 数据语法：( ) [ ]、缩写 ' ` , ,@ #' #` #, #,@、#( 向量、字符串、字符、布尔、数字、标识符；</item>
  /// <item>注释 ; #| |#（可嵌套）#;；指令 #!r6rs 等（忽略）、#!fold-case、#!no-fold-case、#!eof（之后的输入全部忽略）、#!/… 与 #! /…（整行忽略）；</item>
  /// <item>IronScheme 扩展：中缀点号 (a . op . b …) 读作 (op a b …)；值向量 #vu8( #u8( #fl( #fx(；标识符中的 [] 对（CLR 数组类型名）；</item>
  /// <item>字符：BMP 内读为 System.Char，之外读为 SchemeChar（与旧系统一致）；字符串中的裸 \r 被删除。</item>
  /// </list>
  /// 与旧实现的差别：逐个数据读取（旧实现首次读取时读完整个端口并缓存剩余数据），read 与 read-char 可以交替使用。
  /// </summary>
  public sealed class SchemeReader
  {
    sealed class PortState
    {
      public int Line = 1, Column;           // Column 从 0 开始
      public bool FoldCase, EofDirective, PrevCR;
      public readonly Stack<int> Pushback = new Stack<int>();
    }

    static readonly ConditionalWeakTable<TextReader, PortState> states = new ConditionalWeakTable<TextReader, PortState>();

    readonly TextReader input;
    readonly PortState st;
    readonly string filename;
    readonly bool annotate;

    static readonly object EofToken = new object(), CloseToken = new object(), DotToken = new object();
    char lastClose;

    public SchemeReader(TextReader input, string filename, bool annotate)
    {
      this.input = input;
      this.filename = filename ?? "";
      this.annotate = annotate;
      st = states.GetValue(input, _ => new PortState());
    }

    /// <summary>读一个数据；输入结束返回 eof 对象。annotate 为真时返回 <see cref="Annotation"/>（原子也包装）。</summary>
    public object Read()
    {
      var x = ReadItem();
      if (x == EofToken) return Builtins.EOF;
      if (x == CloseToken) throw Error("unexpected close bracket");
      if (x == DotToken) throw Error("unexpected dot");
      return x;
    }

    /// <summary>读到输入结束，返回全部数据（stage0 读种子文件使用）。</summary>
    public List<object> ReadAll()
    {
      var all = new List<object>();
      for (object x; (x = Read()) != Builtins.EOF;) all.Add(x);
      return all;
    }

    #region 字符输入与位置

    int Peek()
    {
      if (st.Pushback.Count > 0) return st.Pushback.Peek();
      int c = input.Peek();
      if (c >= 0) return c;
      c = input.Read();                 // 不支持 Peek 的端口：读出来暂存
      st.Pushback.Push(c);
      return c;
    }

    int Next()
    {
      int c = st.Pushback.Count > 0 ? st.Pushback.Pop() : input.Read();
      if (c == '\n') { if (!st.PrevCR) st.Line++; st.Column = 0; st.PrevCR = false; }
      else if (c == '\r') { st.Line++; st.Column = 0; st.PrevCR = true; }
      else if (c >= 0) { st.Column++; st.PrevCR = false; }
      return c;
    }

    /// <summary>退回一个已经读出的字符（只用于标识符后的 [ 判断）。位置不回退，误差最多一列。</summary>
    void Unread(int c) => st.Pushback.Push(c);

    (int Line, int Col) Pos() => (st.Line, st.Column + 1);

    ReaderException Error(string message) => new ReaderException(message, st.Line, st.Column + 1);

    static bool IsDelimiter(int c) => c < 0 || char.IsWhiteSpace((char)c) || c == '(' || c == ')' || c == '[' || c == ']' || c == '"' || c == ';';

    #endregion

    #region 注解

    object Wrap(object value, (int Line, int Col) start)
    {
      if (!annotate) return value;
      var src = new Cons(filename, new SourceSpan(start.Line, start.Col, st.Line, st.Column + 1).ToString());
      return value switch
      {
        Cons c => new ConsAnnotation(c, src, (Cons)Strip(c)),
        object[] v => new Annotation(v, src, Array.ConvertAll(v, Strip)),
        _ => new Annotation(value, src, value),
      };
    }

    static object Strip(object o)
    {
      switch (o)
      {
        case Annotation a: return a.stripped;
        case Cons c:
          Cons head = null, cur = null;
          object x = c;
          for (; x is Cons p; x = p.cdr)
          {
            var n = new Cons(Strip(p.car));
            if (head == null) head = n; else cur.cdr = n;
            cur = n;
          }
          cur.cdr = Strip(x);
          return head;
        default: return o;
      }
    }

    #endregion

    #region 空白、注释与指令

    /// <summary>跳过空白、注释与指令。遇到 # 而后面不是 | ; ! 时，# 已被读掉：返回 true 并给出它的位置。</summary>
    bool SkipAtmosphere(out (int Line, int Col) hashStart)
    {
      hashStart = default;
      while (true)
      {
        if (st.EofDirective) return false;
        int c = Peek();
        if (c < 0) return false;
        if (char.IsWhiteSpace((char)c)) { Next(); continue; }
        if (c == ';') { while ((c = Peek()) >= 0 && c != '\n' && c != '\r') Next(); continue; }
        if (c != '#') return false;

        hashStart = Pos();
        Next();
        int d = Peek();
        if (d == '|') { Next(); SkipBlockComment(); continue; }
        if (d == ';')
        {
          Next();
          var ignored = ReadItem();
          if (ignored == EofToken || ignored == CloseToken || ignored == DotToken) throw Error("#; must be followed by a datum");
          continue;
        }
        if (d == '!') { Next(); ReadDirective(); continue; }
        return true;
      }
    }

    void SkipBlockComment()
    {
      int depth = 1;
      while (depth > 0)
      {
        int c = Next();
        if (c < 0) throw Error("unterminated block comment");
        if (c == '|' && Peek() == '#') { Next(); depth--; }
        else if (c == '#' && Peek() == '|') { Next(); depth++; }
      }
    }

    void ReadDirective()
    {
      int c = Peek();
      if (c == ' ' || c == '\t' || c == '/')
      {
        // #!/usr/bin/env … 或 #! /…：整行忽略
        while ((c = Peek()) >= 0 && c != '\n' && c != '\r') Next();
        return;
      }
      var sb = new StringBuilder();
      while (!IsDelimiter(Peek())) sb.Append((char)Next());
      switch (sb.ToString())
      {
        case "fold-case": st.FoldCase = true; break;
        case "no-fold-case": st.FoldCase = false; break;
        case "eof": st.EofDirective = true; break;
        case "": throw Error("bad directive");
        default: break;                      // #!r6rs 等：忽略
      }
    }

    #endregion

    #region 数据

    object ReadItem()
    {
      bool hash = SkipAtmosphere(out var hashStart);
      if (st.EofDirective) return EofToken;
      if (hash) return ReadHash(hashStart);
      var start = Pos();
      int c = Peek();
      if (c < 0) return EofToken;
      switch (c)
      {
        case '(': Next(); return ReadList(start, ')');
        case '[': Next(); return ReadList(start, ']');
        case ')': case ']': Next(); lastClose = (char)c; return CloseToken;
        case '\'': Next(); return ReadAbbreviation("quote", start);
        case '`': Next(); return ReadAbbreviation("quasiquote", start);
        case ',':
          Next();
          if (Peek() == '@') { Next(); return ReadAbbreviation("unquote-splicing", start); }
          return ReadAbbreviation("unquote", start);
        case '"': Next(); return Wrap(ReadString(), start);
        default: return ReadAtom(start);
      }
    }

    object RequireDatum(object x)
    {
      if (x == EofToken) throw Error("unexpected end of input");
      if (x == CloseToken) throw Error("unexpected close bracket");
      if (x == DotToken) throw Error("unexpected dot");
      return x;
    }

    object ReadAbbreviation(string name, (int Line, int Col) start)
    {
      var sym = Wrap(Symbol.Intern(name), start);
      var datum = RequireDatum(ReadItem());
      return Wrap(new Cons(sym, new Cons(datum, null)), start);
    }

    object ReadList((int Line, int Col) start, char closer)
    {
      var items = new List<object>();
      object tail = null;
      while (true)
      {
        var x = ReadItem();
        if (x == EofToken) throw Error("unexpected end of input in list");
        if (x == CloseToken)
        {
          if (lastClose != closer) throw Error($"mismatched brackets: expected '{closer}'");
          break;
        }
        if (x == DotToken)
        {
          if (items.Count == 0) throw Error("bad dot");
          var t = RequireDatum(ReadItem());
          var y = ReadItem();
          if (y == CloseToken)
          {
            if (lastClose != closer) throw Error($"mismatched brackets: expected '{closer}'");
            tail = t;
            break;
          }
          if (y == DotToken && items.Count == 1)
          {
            // 中缀点号 (a . op . b rest …) => (op a b rest …)
            var rest = new List<object> { t, items[0], RequireDatum(ReadItem()) };
            while (true)
            {
              var z = ReadItem();
              if (z == CloseToken) { if (lastClose != closer) throw Error($"mismatched brackets: expected '{closer}'"); break; }
              rest.Add(RequireDatum(z));
            }
            items = rest;
            break;
          }
          throw Error("bad dotted list");
        }
        items.Add(x);
      }
      object list = tail;
      for (int i = items.Count - 1; i >= 0; i--) list = new Cons(items[i], list);
      return Wrap(list, start);
    }

    object ReadHash((int Line, int Col) start)
    {
      int c = Peek();
      switch (c)
      {
        case '(':
          Next();
          return Wrap(ReadVectorItems().ToArray(), start);
        case '\\': Next(); return Wrap(ReadCharacter(), start);
        case '\'': Next(); return ReadAbbreviation("syntax", start);
        case '`': Next(); return ReadAbbreviation("quasisyntax", start);
        case ',':
          Next();
          if (Peek() == '@') { Next(); return ReadAbbreviation("unsyntax-splicing", start); }
          return ReadAbbreviation("unsyntax", start);
      }
      if (c < 0 || IsDelimiter(c)) throw Error("bad input: #");

      var sb = new StringBuilder();
      while (!IsDelimiter(Peek()) && Peek() != '(') sb.Append((char)Next());
      string name = sb.ToString();

      if (Peek() == '(')
      {
        Next();
        var items = ReadVectorItems();
        return Wrap(MakeValueVector(name, items), start);
      }
      switch (name)
      {
        case "t": case "T": case "true": return Wrap(RT.True, start);
        case "f": case "F": case "false": return Wrap(RT.False, start);
      }
      if ("xXbBoOdDeEiI".IndexOf(name[0]) >= 0)
      {
        var n = Builtins.ParseNumber("#" + name);
        if (n == null) throw Error("bad number: #" + name);
        return Wrap(n, start);
      }
      throw Error("bad input: #" + name);
    }

    List<object> ReadVectorItems()
    {
      var items = new List<object>();
      while (true)
      {
        var x = ReadItem();
        if (x == EofToken) throw Error("unexpected end of input in vector");
        if (x == DotToken) throw Error("unexpected dot in vector");
        if (x == CloseToken)
        {
          if (lastClose != ')') throw Error("mismatched brackets: expected ')'");
          return items;
        }
        items.Add(x);
      }
    }

    object MakeValueVector(string type, List<object> items)
    {
      var list = Cons.FromList(items.ConvertAll(Strip));
      try
      {
        switch (type)
        {
          case "u8": case "vu8": return BytesFromList(list);
          case "fl": return Builtins.ListToFlonumVector(list);
          case "fx": return Builtins.ListToFixnumVector(list);
        }
      }
      catch (InvalidCastException) { throw Error($"invalid element in #{type}( vector"); }
      throw Error("not a known vector type: " + type);
    }

    byte[] BytesFromList(Cons list)
    {
      var result = new List<byte>();
      if (list != null)
        foreach (var o in list)
        {
          if (!(o is int i) || i < 0 || i > 255) throw Error("bytevector element out of range: " + o);
          result.Add((byte)i);
        }
      return result.ToArray();
    }

    static readonly Dictionary<string, int> charNames = new Dictionary<string, int>(StringComparer.Ordinal)
    {
      ["nul"] = 0, ["alarm"] = 7, ["backspace"] = 8, ["tab"] = 9, ["linefeed"] = 10, ["newline"] = 10,
      ["vtab"] = 11, ["page"] = 12, ["return"] = 13, ["esc"] = 0x1b, ["space"] = 32, ["delete"] = 0x7f,
    };

    /// <summary>BMP 内为 System.Char，之外为 SchemeChar（与旧系统一致）。</summary>
    static object MakeChar(int cp) => cp < 0x10000 ? (object)(char)cp : new SchemeChar(cp);

    object ReadCharacter()
    {
      int c = Next();
      if (c < 0) throw Error("unexpected end of input after #\\");
      var sb = new StringBuilder().Append((char)c);
      if (char.IsHighSurrogate((char)c) && Peek() >= 0) sb.Append((char)Next());
      while (!IsDelimiter(Peek())) sb.Append((char)Next());
      string t = sb.ToString();

      if (t.Length == 1 || (t.Length == 2 && char.IsSurrogatePair(t, 0))) return MakeChar(char.ConvertToUtf32(t, 0));
      if (charNames.TryGetValue(t, out int named)) return MakeChar(named);
      if (t[0] == 'x' && int.TryParse(t.AsSpan(1), NumberStyles.AllowHexSpecifier, CultureInfo.InvariantCulture, out int cp))
      {
        if (cp < 0 || cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF)) throw Error("not a valid Unicode value: " + cp);
        return MakeChar(cp);
      }
      throw Error("bad character: #\\" + t);
    }

    string ReadString()
    {
      var sb = new StringBuilder();
      while (true)
      {
        int c = Next();
        if (c < 0) throw Error("unterminated string");
        if (c == '"') return sb.ToString();
        if (c == '\r') continue;                       // 与旧实现一致：删除字符串中的裸 \r
        if (c != '\\') { sb.Append((char)c); continue; }

        int e = Next();
        switch (e)
        {
          case '"': sb.Append('"'); break;
          case '\\': sb.Append('\\'); break;
          case 'a': sb.Append('\a'); break;
          case 'b': sb.Append('\b'); break;
          case 't': sb.Append('\t'); break;
          case 'n': sb.Append('\n'); break;
          case 'v': sb.Append('\v'); break;
          case 'f': sb.Append('\f'); break;
          case 'r': sb.Append('\r'); break;
          case 'x': case 'X':
          {
            var hex = new StringBuilder();
            while (Uri.IsHexDigit((char)Peek())) hex.Append((char)Next());
            if (Peek() != ';' || hex.Length == 0) throw Error("invalid hex escape in string");
            Next();
            int cp = int.Parse(hex.ToString(), NumberStyles.AllowHexSpecifier, CultureInfo.InvariantCulture);
            if (cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF)) throw Error("not a valid Unicode value: " + cp);
            sb.Append(char.ConvertFromUtf32(cp));
            break;
          }
          case ' ': case '\t': case '\n': case '\r':
          {
            // 行接续：\ 后可有行内空白，然后换行，再跳过下一行开头的行内空白
            var skipped = new StringBuilder().Append((char)e);
            int d = e;
            while (d == ' ' || d == '\t') { d = Peek(); if (d == ' ' || d == '\t') skipped.Append((char)Next()); else break; }
            if (e == '\n' || e == '\r' || Peek() == '\n' || Peek() == '\r')
            {
              if (e != '\n' && e != '\r') e = Next();
              if (e == '\r' && Peek() == '\n') Next();
              while (Peek() == ' ' || Peek() == '\t') Next();
            }
            else sb.Append('\\').Append(skipped);   // 不是行接续：与旧实现一样保留原文
            break;
          }
          case -1: throw Error("unterminated string");
          default: sb.Append('\\').Append((char)e); break;   // 未知转义：与旧实现一样保留原文
        }
      }
    }

    object ReadAtom((int Line, int Col) start)
    {
      var sb = new StringBuilder();
      bool inEscape = false;   // 标识符中的 \x…; 转义：其中的 ; 是转义结束符而不是注释
      while (true)
      {
        int c = Peek();
        if (inEscape && c == ';') { sb.Append((char)Next()); inEscape = false; continue; }
        if (c == '\\') { sb.Append((char)Next()); inEscape = Peek() == 'x'; continue; }
        if (c == '[' && sb.Length > 0)
        {
          // 标识符中的 [] 对（如 CLR 数组类型名 Int32[]）
          Next();
          if (Peek() == ']') { Next(); sb.Append("[]"); continue; }
          Unread('[');
          break;
        }
        if (IsDelimiter(c)) break;
        sb.Append((char)Next());
      }
      string text = sb.ToString();
      if (text == ".") return DotToken;

      var n = Builtins.ParseNumber(text);
      if (n != null) return Wrap(n, start);

      string name = ParseIdentifier(text);
      if (name == null)
        throw Error((char.IsDigit(text[0]) || text[0] == '.' ? "bad number: " : "bad identifier: ") + text);
      if (st.FoldCase) name = name.ToLowerInvariant();
      return Wrap(Symbol.Intern(name), start);
    }

    #endregion

    #region 标识符

    /// <summary>校验标识符并解码 \x…; 转义；不合法返回 null。</summary>
    static string ParseIdentifier(string text)
    {
      switch (text)
      {
        case "+": case "-": case "...": case "+o": case "-o": case "@": return text;   // 后三者为旧系统的扩展
      }
      var sb = new StringBuilder();
      int i = 0;
      bool first = true;
      while (i < text.Length)
      {
        if (text[i] == '\\')
        {
          if (i + 1 >= text.Length || text[i + 1] != 'x') return null;
          int semi = text.IndexOf(';', i);
          if (semi < 0 || !int.TryParse(text.AsSpan(i + 2, semi - i - 2), NumberStyles.AllowHexSpecifier, CultureInfo.InvariantCulture, out int cp)) return null;
          if (cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF)) return null;
          sb.Append(char.ConvertFromUtf32(cp));
          i = semi + 1;
          first = false;
          continue;
        }
        if (first && text[i] == '-' && i + 1 < text.Length && text[i + 1] == '>') { sb.Append("->"); i += 2; first = false; continue; }
        if (!Rune.TryGetRuneAt(text, i, out Rune r)) return null;
        if (first ? !IsInitial(r) : !IsSubsequent(r, text, i)) return null;
        if (r.Value == '[') { sb.Append("[]"); i += 2; first = false; continue; }
        sb.Append(r.ToString());
        i += r.Utf16SequenceLength;
        first = false;
      }
      return sb.ToString();
    }

    static bool IsInitial(Rune r)
    {
      int v = r.Value;
      if (v < 128) return (v >= 'a' && v <= 'z') || (v >= 'A' && v <= 'Z') || "!$%*/:<=>?~_^&".IndexOf((char)v) >= 0;
      switch (Rune.GetUnicodeCategory(r))
      {
        case UnicodeCategory.UppercaseLetter: case UnicodeCategory.LowercaseLetter: case UnicodeCategory.TitlecaseLetter:
        case UnicodeCategory.ModifierLetter: case UnicodeCategory.OtherLetter: case UnicodeCategory.NonSpacingMark:
        case UnicodeCategory.LetterNumber: case UnicodeCategory.OtherNumber: case UnicodeCategory.DashPunctuation:
        case UnicodeCategory.ConnectorPunctuation: case UnicodeCategory.OtherPunctuation: case UnicodeCategory.CurrencySymbol:
        case UnicodeCategory.MathSymbol: case UnicodeCategory.ModifierSymbol: case UnicodeCategory.OtherSymbol:
        case UnicodeCategory.PrivateUse:
          return true;
        default: return false;
      }
    }

    static bool IsSubsequent(Rune r, string text, int i)
    {
      if (IsInitial(r)) return true;
      int v = r.Value;
      if (v < 128)
      {
        if (char.IsDigit((char)v) || v == '.' || v == '+' || v == '@' || v == '-') return true;
        return v == '[' && i + 1 < text.Length && text[i + 1] == ']';
      }
      var cat = Rune.GetUnicodeCategory(r);
      return cat == UnicodeCategory.DecimalDigitNumber || cat == UnicodeCategory.SpacingCombiningMark || cat == UnicodeCategory.EnclosingMark;
    }

    #endregion
  }
}

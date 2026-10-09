using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;

namespace IronScheme.Host
{
  /// <summary>补全与提示的数据来源（由 Scheme 侧提供，见 Repl.SchemeServices）。</summary>
  interface IReplServices
  {
    /// <summary>以 prefix 开头的候选：名字，或 library 为真时写成 "(a b c)" 的库名。</summary>
    IReadOnlyList<string> Complete(string prefix, bool library);

    /// <summary>名字的提示（如过程的形参 "(list-tail lst k)"、"syntax"）；没有时为 null。</summary>
    string Hint(string name);
  }

  /// <summary>
  /// REPL 的行编辑器（iron-038，designs/07-tooling-and-embedding.md §4），只用 System.Console，Windows / Linux / macOS 通用：
  /// 行内编辑、多行输入（括号未闭合时换行继续）、历史、Tab 补全、行尾的参数提示、右括号匹配高亮。
  /// 只编辑当前行；之前输入的续行已提交。标准输入被重定向时不使用（Repl 退回逐行读取）。
  /// </summary>
  sealed class LineEditor
  {
    readonly IReplServices services;
    readonly string historyFile;
    readonly List<string> history = new List<string>();
    readonly Dictionary<string, string> hintCache = new Dictionary<string, string>();
    const int MaxHistory = 1000;

    // 当前输入的状态
    readonly List<string> committed = new List<string>();   // 已提交的行（多行输入的前几行）
    readonly StringBuilder line = new StringBuilder();      // 正在编辑的行
    int pos;            // 光标在 line 中的位置
    string prompt;

    public LineEditor(IReplServices services, string historyFile)
    {
      this.services = services;
      this.historyFile = historyFile;
      try
      {
        if (historyFile != null && File.Exists(historyFile))
          history.AddRange(File.ReadAllLines(historyFile).Where(l => l.Length > 0).TakeLast(MaxHistory));
      }
      catch (IOException) { }
      catch (UnauthorizedAccessException) { }
    }

    /// <summary>读入一个完整的输入（括号平衡，可跨多行）；输入结束（空行上 Ctrl+D / Ctrl+Z）时返回 null，Ctrl+C 取消时返回空串。</summary>
    public string Read(string firstPrompt, string continuationPrompt)
    {
      committed.Clear();
      line.Clear();
      pos = 0;
      prompt = firstPrompt;
      int historyIndex = history.Count;
      string pending = null;      // 浏览历史前正在输入的内容
      bool lastWasTab = false;
      bool treatCtrlC = Console.TreatControlCAsInput;
      Console.TreatControlCAsInput = true;
      try
      {
        StartLine();
        while (true)
        {
          var key = Console.ReadKey(true);
          bool tab = false;
          bool ctrl = (key.Modifiers & ConsoleModifiers.Control) != 0;
          switch (key.Key)
          {
            case ConsoleKey.Enter:
            {
              string text = Text();
              if (IsComplete(text))
              {
                pos = line.Length;
                Render(false);
                Console.WriteLine();
                AddHistory(text);
                return text;
              }
              // 括号未闭合：提交当前行，换行继续
              pos = line.Length;
              Render(false);
              Console.WriteLine();
              committed.Add(line.ToString());
              line.Clear();
              pos = 0;
              prompt = continuationPrompt;
              StartLine();
              break;
            }
            case ConsoleKey.Tab:
              tab = true;
              Complete(lastWasTab);
              break;
            case ConsoleKey.Backspace:
              if (ctrl) DeleteWordBackward();
              else if (pos > 0) { line.Remove(pos - 1, 1); pos--; Render(); }
              break;
            case ConsoleKey.Delete:
              if (pos < line.Length) { line.Remove(pos, 1); Render(); }
              break;
            case ConsoleKey.LeftArrow:
              pos = ctrl ? WordStart(pos) : Math.Max(0, pos - 1);
              Render();
              break;
            case ConsoleKey.RightArrow:
              pos = ctrl ? WordEnd(pos) : Math.Min(line.Length, pos + 1);
              Render();
              break;
            case ConsoleKey.Home: pos = 0; Render(); break;
            case ConsoleKey.End: pos = line.Length; Render(); break;
            case ConsoleKey.UpArrow:
            case ConsoleKey.DownArrow:
            {
              if (committed.Count > 0 || history.Count == 0) break;
              if (historyIndex == history.Count) pending = line.ToString();
              historyIndex = key.Key == ConsoleKey.UpArrow ? Math.Max(0, historyIndex - 1) : Math.Min(history.Count, historyIndex + 1);
              SetLine(historyIndex == history.Count ? pending ?? "" : history[historyIndex]);
              break;
            }
            case ConsoleKey.Escape:
              SetLine("");
              break;
            default:
              if (ctrl && HandleControl(key.Key, out bool finish, out var result))
              {
                if (finish) return result;
                break;
              }
              if (key.KeyChar >= ' ' && !ctrl)
              {
                line.Insert(pos, key.KeyChar);
                pos++;
                Render();
                if (key.KeyChar == ')' || key.KeyChar == ']') FlashMatch();
              }
              break;
          }
          lastWasTab = tab;
        }
      }
      finally
      {
        Console.TreatControlCAsInput = treatCtrlC;
      }
    }

    /// <summary>Ctrl 组合键；返回真表示已处理。finish 为真时 Read 返回 result（Ctrl+C 取消返回空串；空输入上 Ctrl+D / Ctrl+Z 返回 null 表示输入结束）。</summary>
    bool HandleControl(ConsoleKey k, out bool finish, out string result)
    {
      finish = false;
      result = null;
      switch (k)
      {
        case ConsoleKey.A: pos = 0; Render(); return true;
        case ConsoleKey.E: pos = line.Length; Render(); return true;
        case ConsoleKey.B: pos = Math.Max(0, pos - 1); Render(); return true;
        case ConsoleKey.F: pos = Math.Min(line.Length, pos + 1); Render(); return true;
        case ConsoleKey.K: line.Remove(pos, line.Length - pos); Render(); return true;
        case ConsoleKey.U: line.Remove(0, pos); pos = 0; Render(); return true;
        case ConsoleKey.W: DeleteWordBackward(); return true;
        case ConsoleKey.L:
          Console.Clear();
          foreach (var l in committed) Console.WriteLine(l);
          StartLine();
          return true;
        case ConsoleKey.C:
          pos = line.Length;
          Render(false);
          Console.WriteLine("^C");
          finish = true;
          result = "";
          return true;
        case ConsoleKey.D:
        case ConsoleKey.Z:   // Windows 的输入结束
          if (line.Length == 0 && committed.Count == 0)
          {
            Console.WriteLine();
            finish = true;   // result 为 null：输入结束
            return true;
          }
          if (k == ConsoleKey.D && pos < line.Length) { line.Remove(pos, 1); Render(); }
          return true;
      }
      return false;
    }

    string Text() => committed.Count == 0 ? line.ToString() : string.Join("\n", committed) + "\n" + line;

    void SetLine(string s)
    {
      line.Clear();
      line.Append(s);
      pos = line.Length;
      Render();
    }

    void AddHistory(string text)
    {
      string entry = string.Join(" ", text.Split('\n').Select(l => l.Trim()).Where(l => l.Length > 0));
      if (entry.Length == 0 || (history.Count > 0 && history[^1] == entry)) return;
      history.Add(entry);
      if (history.Count > MaxHistory) history.RemoveAt(0);
      try
      {
        if (historyFile != null) File.AppendAllLines(historyFile, new[] { entry });
      }
      catch (IOException) { }
      catch (UnauthorizedAccessException) { }
    }

    // ———————————————— 绘制 ————————————————

    static int Width => Math.Max(20, Console.BufferWidth > 0 ? Console.BufferWidth : 80);

    static int Height
    {
      get
      {
        try { return Console.BufferHeight > 0 ? Console.BufferHeight : int.MaxValue; }
        catch (IOException) { return int.MaxValue; }
      }
    }

    // 光标位置：Unix 终端上不查询（查询要与终端往返，有的伪终端不回应，等待回应时会吞掉按键），
    // 由编辑器记录光标相对当前行起点（提示符所在行第 0 列）的行列，用 ANSI 相对移动定位、"清除到屏幕末尾"清残留；
    // 终端滚动不影响相对移动。Windows 控制台的光标查询是本地 API 调用，用绝对定位。
    static readonly bool ansi = !OperatingSystem.IsWindows();
    int row, col;       // ANSI：光标相对行起点的行列
    int top;            // Windows：行起点所在的缓冲区行
    int lastLength;     // Windows：上次绘制的字符数（用空格清除残留）

    /// <summary>开始绘制新的一行：调用时光标在一行的开头。</summary>
    void StartLine()
    {
      row = col = 0;
      lastLength = 0;
      if (!ansi) top = Math.Max(0, CursorTop());
      Render();
    }

    /// <summary>重绘当前行（提示符 + 文本 + 暗色的提示），清除残留，把光标放回 pos。</summary>
    void Render(bool withHint = true)
    {
      int width = Width;
      string hint = withHint && pos == line.Length ? CurrentHint() : null;
      MoveTo(0);
      Console.Write(prompt);
      Console.Write(line.ToString());
      int length = prompt.Length + line.Length;
      if (hint != null)
      {
        var color = Console.ForegroundColor;
        Console.ForegroundColor = ConsoleColor.DarkGray;
        Console.Write("  " + hint);
        Console.ForegroundColor = color;
        length += 2 + hint.Length;
      }
      if (ansi)
      {
        Console.Write("\x1b[J");   // 清除到屏幕末尾
        // 写满整行时终端停在行末（延迟换行），按此记录位置
        row = length == 0 ? 0 : (length - 1) / width;
        col = length == 0 ? 0 : (length % width == 0 ? width - 1 : length % width);
      }
      else
      {
        if (lastLength > length) Console.Write(new string(' ', lastLength - length));
        int written = Math.Max(length, lastLength);
        int rows = written == 0 ? 0 : (written - 1) / width;
        if (top + rows > Height - 1) top = Math.Max(0, Height - 1 - rows);
        lastLength = length;
      }
      MoveTo(prompt.Length + pos);
    }

    /// <summary>把光标移到当前行（含提示符）的第 offset 个字符处。</summary>
    void MoveTo(int offset)
    {
      int width = Width, r = offset / width, c = offset % width;
      if (ansi)
      {
        var sb = new StringBuilder("\r");
        if (r < row) sb.Append("\x1b[").Append(row - r).Append('A');
        else if (r > row) sb.Append("\x1b[").Append(r - row).Append('B');
        if (c > 0) sb.Append("\x1b[").Append(c).Append('C');
        Console.Write(sb.ToString());
        row = r;
        col = c;
      }
      else
      {
        try { Console.SetCursorPosition(c, Math.Min(Math.Max(0, top + r), Height - 1)); }
        catch (ArgumentOutOfRangeException) { }
        catch (IOException) { }
      }
    }

    static int CursorTop()
    {
      try { return Console.CursorTop; }
      catch (IOException) { return 0; }
    }

    /// <summary>右括号匹配：短暂把光标移到与之匹配的左括号（只在当前行内）。</summary>
    void FlashMatch()
    {
      int match = MatchingOpen(line.ToString(), pos - 1);
      if (match < 0) return;
      MoveTo(prompt.Length + match);
      for (int i = 0; i < 15 && !Console.KeyAvailable; i++) System.Threading.Thread.Sleep(20);
      MoveTo(prompt.Length + pos);
    }

    // ———————————————— 补全与提示 ————————————————

    void Complete(bool listCandidates)
    {
      string before = Text().Substring(0, Text().Length - (line.Length - pos));
      var (start, library) = CompletionStart(before);
      // start 是在整个输入中的位置；补全只作用于当前行
      int lineStart = before.Length - pos;
      if (start < lineStart) return;
      string prefix = before.Substring(start);
      var candidates = services.Complete(prefix, library);
      if (candidates.Count == 0) return;
      string common = CommonPrefix(candidates);
      if (candidates.Count == 1)
      {
        Replace(start - lineStart, candidates[0] + (library ? "" : " "));
        return;
      }
      if (common.Length > prefix.Length)
      {
        Replace(start - lineStart, common);
        return;
      }
      if (!listCandidates) return;
      // 第二次 Tab：在下方列出候选，再重绘输入
      pos = line.Length;
      Render(false);
      Console.WriteLine();
      int width = Width, col = Math.Min(width - 1, candidates.Max(s => s.Length) + 2), perRow = Math.Max(1, width / col);
      const int MaxShown = 200;
      var shown = candidates.Take(MaxShown).ToList();
      for (int i = 0; i < shown.Count; i++)
      {
        Console.Write(shown[i].PadRight(col));
        if ((i + 1) % perRow == 0 || i == shown.Count - 1) Console.WriteLine();
      }
      if (candidates.Count > MaxShown) Console.WriteLine($"… {candidates.Count - MaxShown} more");
      foreach (var l in committed) Console.WriteLine(l);
      StartLine();
    }

    void Replace(int from, string text)
    {
      line.Remove(from, pos - from);
      line.Insert(from, text);
      pos = from + text.Length;
      Render();
    }

    string CurrentHint()
    {
      string name = EnclosingHead(Text());
      if (name == null) return null;
      if (!hintCache.TryGetValue(name, out var hint))
      {
        try { hint = services.Hint(name); } catch (Exception) { hint = null; }
        hintCache[name] = hint;
      }
      return hint;
    }

    static string CommonPrefix(IReadOnlyList<string> xs)
    {
      string p = xs[0];
      foreach (var s in xs)
      {
        int i = 0;
        while (i < p.Length && i < s.Length && p[i] == s[i]) i++;
        p = p.Substring(0, i);
      }
      return p;
    }

    // ———————————————— 简单的词法扫描（跳过字符串、字符、注释） ————————————————

    static bool IsDelimiter(char c) => char.IsWhiteSpace(c) || c is '(' or ')' or '[' or ']' or '"' or ';' or '\'' or '`' or ',';

    int WordStart(int i)
    {
      while (i > 0 && IsDelimiter(line[i - 1])) i--;
      while (i > 0 && !IsDelimiter(line[i - 1])) i--;
      return i;
    }

    int WordEnd(int i)
    {
      while (i < line.Length && IsDelimiter(line[i])) i++;
      while (i < line.Length && !IsDelimiter(line[i])) i++;
      return i;
    }

    void DeleteWordBackward()
    {
      int s = WordStart(pos);
      line.Remove(s, pos - s);
      pos = s;
      Render();
    }

    /// <summary>扫描文本，返回仍未闭合的左括号位置（栈底在前）；inString 等表示扫描结束时的状态。</summary>
    static List<int> OpenParens(string s, out bool inString, out bool inBlockComment)
    {
      var stack = new List<int>();
      inString = false;
      inBlockComment = false;
      int depthBlock = 0;
      for (int i = 0; i < s.Length; i++)
      {
        char c = s[i];
        if (depthBlock > 0)
        {
          if (c == '|' && i + 1 < s.Length && s[i + 1] == '#') { depthBlock--; i++; }
          else if (c == '#' && i + 1 < s.Length && s[i + 1] == '|') { depthBlock++; i++; }
          continue;
        }
        if (inString)
        {
          if (c == '\\') i++;
          else if (c == '"') inString = false;
          continue;
        }
        switch (c)
        {
          case '"': inString = true; break;
          case ';': while (i < s.Length && s[i] != '\n') i++; break;
          case '#':
            if (i + 1 < s.Length && s[i + 1] == '|') { depthBlock++; i++; }
            else if (i + 1 < s.Length && s[i + 1] == '\\') i += 2;   // 字符字面量 #\( 等
            break;
          case '(': case '[': stack.Add(i); break;
          case ')': case ']': if (stack.Count > 0) stack.RemoveAt(stack.Count - 1); break;
        }
      }
      inBlockComment = depthBlock > 0;
      return stack;
    }

    /// <summary>输入是否完整：括号平衡、不在字符串或块注释中，且有非空白内容。</summary>
    internal static bool IsComplete(string s)
    {
      if (s.Trim().Length == 0) return true;
      var open = OpenParens(s, out bool inString, out bool inBlock);
      return open.Count == 0 && !inString && !inBlock;
    }

    /// <summary>与 close 处的右括号匹配的左括号位置；没有时为 -1。</summary>
    static int MatchingOpen(string s, int close)
    {
      var open = OpenParens(s.Substring(0, close), out bool inString, out _);
      return inString || open.Count == 0 ? -1 : open[^1];
    }

    /// <summary>
    /// 补全的起点：光标前的符号；若光标位于 (import …) 中的库名列表内（含 only/except/prefix/rename/for 等嵌套），
    /// 起点是该库名的左括号，补全整个库名。
    /// </summary>
    internal static (int Start, bool Library) CompletionStart(string before)
    {
      var open = OpenParens(before, out bool inString, out _);
      if (inString) return (before.Length, false);
      int start = before.Length;
      while (start > 0 && !IsDelimiter(before[start - 1])) start--;
      // 库名：当前所在列表的某个外层列表以 import 开头
      if (open.Count >= 2)
      {
        int current = open[^1];
        string head = HeadAt(before, current);
        bool modifier = head is "only" or "except" or "prefix" or "rename" or "for" or "library";
        for (int i = open.Count - 2; i >= 0; i--)
        {
          string h = HeadAt(before, open[i]);
          if (h == "import") return modifier && i == open.Count - 2 ? (start, false) : (current, true);
          if (!(h is "only" or "except" or "prefix" or "rename" or "for")) break;
        }
      }
      return (start, false);
    }

    /// <summary>光标所在（最内层未闭合）列表的首个符号；光标仍在首符号上时为 null。</summary>
    internal static string EnclosingHead(string before)
    {
      var open = OpenParens(before, out bool inString, out _);
      if (inString || open.Count == 0) return null;
      int p = open[^1] + 1, e = p;
      while (e < before.Length && !IsDelimiter(before[e])) e++;
      if (e == p || e >= before.Length) return null;   // 还在输入首符号
      return before.Substring(p, e - p);
    }

    static string HeadAt(string s, int paren)
    {
      int p = paren + 1;
      while (p < s.Length && char.IsWhiteSpace(s[p])) p++;
      int e = p;
      while (e < s.Length && !IsDelimiter(s[e])) e++;
      return s.Substring(p, e - p);
    }
  }
}

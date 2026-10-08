using System;
using System.Collections.Concurrent;
using System.Text;
using System.Threading;

namespace IronScheme.Core
{
  /// <summary>
  /// 符号：按名字驻留，带值槽。全局变量与库绑定的值存放在（位置）符号的 Value 中。
  /// 设计：designs/02-runtime.md §3。
  /// </summary>
  public sealed class Symbol
  {
    public readonly string Name;

    /// <summary>值槽。未绑定时为 <see cref="Unbound.Instance"/>。</summary>
    public object Value = Unbound.Instance;

    Symbol(string name) { Name = name; }

    public override string ToString() => Name;

    public bool IsBound => !(Value is Unbound);

    static readonly ConcurrentDictionary<string, Symbol> table = new ConcurrentDictionary<string, Symbol>(StringComparer.Ordinal);

    /// <summary>按名字驻留：同名总是返回同一对象。gensym 也按名字驻留，因此从 dll 重新加载时得到同一个对象。</summary>
    public static Symbol Intern(string name)
    {
      if (name == null) throw new ArgumentNullException(nameof(name));
      return table.TryGetValue(name, out var s) ? s : table.GetOrAdd(name, n => new Symbol(n));
    }

    #region gensym

    // 名字格式沿用旧运行时：g$<名字>$<计数>$<TICKS>，匿名为 g$gen<计数>$<TICKS>。
    // TICKS 由进程启动时间派生，保证不同进程生成的 gensym 不冲突。
    //
    // 构建模式（RuntimeOptions.DeterministicGensym，iron-014）：TICKS 换成当前 gensym 作用域名，
    // 计数在作用域内从 1 开始，同一输入两次展开得到相同名字。psyntax 展开库时进入以库名为名的作用域
    // （如 rnrs.base），作用域外为 %top；文本种子中的 gensym 后缀为 %seed（iron-015）。

    static int anonCount, namedCount;

    /// <summary>构建模式下的 gensym 作用域：名字与计数。</summary>
    public sealed class GensymScope
    {
      public readonly string Name;
      internal int Count;
      internal GensymScope(string name) { Name = name; }
      public override string ToString() => "#<gensym-scope " + Name + " " + Count + ">";
    }

    static GensymScope topScope = new GensymScope("%top");
    static GensymScope scope;

    /// <summary>当前作用域；未进入任何作用域时为 null。</summary>
    public static GensymScope CurrentGensymScope => scope;

    /// <summary>进入新作用域（计数从 0 开始）。名字中的 '$' 换成 '_'，以免干扰 ungensym。</summary>
    public static void EnterGensymScope(string name) => scope = new GensymScope(name.Replace('$', '_'));

    /// <summary>恢复先前保存的作用域（可为 null）。</summary>
    public static void RestoreGensymScope(GensymScope saved) => scope = saved;

    static string NextDeterministic(out int n)
    {
      var s = scope ?? topScope;
      n = ++s.Count;
      return s.Name;
    }

    static readonly char[] packChars = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ@=".ToCharArray();

    static string PackInt(int i)
    {
      var sb = new StringBuilder();
      do { sb.Insert(0, packChars[i % 64]); i /= 64; } while (i > 0);
      return sb.ToString();
    }

    /// <summary>gensym 名字的进程唯一后缀。</summary>
    public static readonly string TickString = PackInt((int)((DateTime.Now.Ticks >> 16) & 0x7FFFFFFF));

    public static Symbol Gensym()
    {
      if (RuntimeOptions.DeterministicGensym)
      {
        string sc = NextDeterministic(out int n);
        return Intern("g$gen" + n + "$" + sc);
      }
      return Intern("g$gen" + Interlocked.Increment(ref anonCount) + "$" + TickString);
    }

    public static Symbol Gensym(string name)
    {
      if (RuntimeOptions.DeterministicGensym)
      {
        string sc = NextDeterministic(out int n);
        return Intern("g$" + name + "$" + n + "$" + sc);
      }
      return Intern("g$" + name + "$" + Interlocked.Increment(ref namedCount) + "$" + TickString);
    }

    /// <summary>gensym 去掉装饰后的名字：第一个与第二个 '$' 之间的部分；不是 gensym 时返回原名。</summary>
    public static string UngensymName(string name)
    {
      int start = name.IndexOf('$') + 1;
      if (start > 0)
      {
        int end = name.IndexOf('$', start);
        if (end > start) return name.Substring(start, end - start);
      }
      return name;
    }

    public Symbol Ungensym()
    {
      string n = UngensymName(Name);
      return ReferenceEquals(n, Name) ? this : Intern(n);
    }

    #endregion
  }
}

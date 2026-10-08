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
    // 构建模式下的确定性命名见 iron-014。

    static int anonCount, namedCount;

    static readonly char[] packChars = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ@=".ToCharArray();

    static string PackInt(int i)
    {
      var sb = new StringBuilder();
      do { sb.Insert(0, packChars[i % 64]); i /= 64; } while (i > 0);
      return sb.ToString();
    }

    /// <summary>gensym 名字的进程唯一后缀。</summary>
    public static readonly string TickString = PackInt((int)((DateTime.Now.Ticks >> 16) & 0x7FFFFFFF));

    public static Symbol Gensym() =>
      Intern("g$gen" + Interlocked.Increment(ref anonCount) + "$" + TickString);

    public static Symbol Gensym(string name) =>
      Intern("g$" + name + "$" + Interlocked.Increment(ref namedCount) + "$" + TickString);

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

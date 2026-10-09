using System.Collections.Concurrent;
using System.Threading;

namespace IronScheme.Core
{
  /// <summary>
  /// 内存模式（eval）的常量直接以对象传给生成的程序集，不经编码（designs/04-lcil-and-emitter.md §3）：
  /// 语法对象的 mark、rib 等靠 eq? 身份工作，编码再解码得到的副本会破坏它们。
  /// 发射器登记常量数组得到编号，生成的 $Constants 类型初始化器按编号取回（取一次后移除）。
  /// </summary>
  public static class ConstantPool
  {
    static readonly ConcurrentDictionary<int, object[]> pool = new ConcurrentDictionary<int, object[]>();
    static int next;

    public static int Register(object[] constants)
    {
      int id = Interlocked.Increment(ref next);
      pool[id] = constants;
      return id;
    }

    public static object[] Take(int id) => pool.TryRemove(id, out var c) ? c : new object[0];
  }
}

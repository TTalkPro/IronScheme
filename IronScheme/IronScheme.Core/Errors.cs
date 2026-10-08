using System;

namespace IronScheme.Core
{
  /// <summary>
  /// 运行时报错的统一入口。
  /// 临时实现：直接抛 <see cref="SchemeRuntimeError"/>；iron-007 改为经运行时钩子调用 Scheme 定义的条件过程。
  /// </summary>
  public static class Errors
  {
    public static object AssertionViolation(string who, string message, params object[] irritants) =>
      throw new SchemeRuntimeError("assertion-violation", who, message, irritants);

    public static object UndefinedError(Symbol symbol) =>
      throw new SchemeRuntimeError("undefined-error", symbol.Ungensym().Name, "attempt to reference unbound identifier", new object[] { symbol });

    public static T RequiresType<T>(object o, string who)
    {
      if (o is T t) return t;
      AssertionViolation(who, "not a " + typeof(T).Name, o);
      return default;
    }
  }

  /// <summary>钩子登记之前（或单元测试中）使用的 .NET 异常。</summary>
  public sealed class SchemeRuntimeError : Exception
  {
    public string Kind { get; }
    public string Who { get; }
    public object[] Irritants { get; }

    public SchemeRuntimeError(string kind, string who, string message, object[] irritants)
      : base($"{kind}: {who}: {message}")
    {
      Kind = kind; Who = who; Irritants = irritants;
    }
  }
}

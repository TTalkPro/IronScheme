using System;
using System.Threading;

namespace IronScheme.Core;

/// <summary>
/// 参数对象的存储（designs/10-async.md §2 D7）：每个参数一个 <see cref="AsyncLocal{T}"/>，
/// 值随 ExecutionContext 流动——parameterize 的值在 Task.Run 的子任务里可见、在 await 之后的恢复线程上可见；
/// 子任务里的赋值不流回。没有设置过的上下文读到回退值：创建时的初始值，以及之后在**创建线程**上的赋值
/// （与旧的 Thread.AllocateDataSlot 实现相同：启动时主线程上 <c>(p v)</c> 设置的库路径、库集合等，
/// 宿主的工作线程也要看到；其他线程上的赋值只影响自己的上下文）。
/// </summary>
public sealed class ParamSlot
{
    /// <summary>空表是 null，而 AsyncLocal 的 null 表示"未设置"，所以空表另用哨兵存放。</summary>
    private static readonly object s_nil = new object();

    private readonly AsyncLocal<object> _local = new AsyncLocal<object>();
    private readonly int _ownerThread = Environment.CurrentManagedThreadId;
    private volatile object _fallback;

    public ParamSlot(object initial) { _fallback = initial; }

    public object Value
    {
        get
        {
            var v = _local.Value;
            return v == null ? _fallback : ReferenceEquals(v, s_nil) ? null : v;
        }
        set
        {
            if (Environment.CurrentManagedThreadId == _ownerThread) _fallback = value;
            _local.Value = value ?? s_nil;
        }
    }
}

/// <summary>make-parameter 用的原语（boot/expander/compat.sls）。</summary>
public static class Parameters
{
    [Primitive("$make-param-slot", Flags = PrimitiveFlags.Unsafe)]
    public static object MakeSlot(object initial) => new ParamSlot(initial);

    [Primitive("$param-ref", Flags = PrimitiveFlags.Unsafe)]
    public static object Ref(object slot) => ((ParamSlot)slot).Value;

    [Primitive("$param-set!", Flags = PrimitiveFlags.Unsafe)]
    public static object Set(object slot, object value)
    {
        ((ParamSlot)slot).Value = value;
        return Unspecified.Instance;
    }
}

/// <summary>
/// 当前异常处理器栈（boot/exceptions.sls 的 with-exception-handler / raise 使用）：Scheme 过程的列表，栈顶在前。
/// 同样是 AsyncLocal，所以恢复到另一个线程后 raise 仍能找到 guard 装的处理器。
/// 缺省（以及设为空表时）是只含默认处理器的表，默认处理器把条件包成 <see cref="SchemeException"/> 抛出。
/// </summary>
public static class ExceptionHandlers
{
    private static readonly AsyncLocal<object> s_handlers = new AsyncLocal<object>();
    private static readonly object s_default = new Cons(new DefaultHandler(), null);

    [Primitive("$current-handlers", Flags = PrimitiveFlags.Unsafe)]
    public static object Current() => s_handlers.Value ?? s_default;

    [Primitive("$set-current-handlers!", Flags = PrimitiveFlags.Unsafe)]
    public static object Set(object handlers)
    {
        s_handlers.Value = handlers;
        return Unspecified.Instance;
    }

    private sealed class DefaultHandler : Procedure
    {
        public override object Invoke1(object condition) => throw new SchemeException(condition);
        public override string Name => "default-exception-handler";
    }
}

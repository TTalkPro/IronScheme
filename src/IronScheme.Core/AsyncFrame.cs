using System;
using System.Runtime.CompilerServices;
using System.Threading;
using System.Threading.Tasks;

namespace IronScheme.Core;

/// <summary>
/// async-lambda 的状态机基类（designs/10-async.md §2 D6；形状由 spikes/iron-049 验证）。
/// 编译器为每个 async-lambda 生成一个子类：自由变量、形参与体内的局部变量是字段，<see cref="MoveNext"/> 是函数体。
/// 所有 ref、结构体与泛型操作都收在这里，生成的代码只做普通调用：
/// <list type="bullet">
/// <item>await = <c>Suspend(task, n)</c>：已完成返回 true 直接继续；否则记下恢复点 n、登记续接并返回 false，生成代码 leave 出去；</item>
/// <item>恢复时 <see cref="MoveNext"/> 按 <see cref="state"/> 跳回恢复点，再 <c>Resume()</c> 取结果（或重新抛出）；</item>
/// <item>体的结果 <c>Complete(v)</c>，体抛出的异常 <c>Fail(e)</c>。</item>
/// </list>
/// 与 C# 一样，<c>Suspend</c> 捕获 SynchronizationContext（D4），ExecutionContext 由 builder 随续接流动（参数对象见 D7）。
/// </summary>
public abstract class AsyncFrame : IAsyncStateMachine
{
    private AsyncTaskMethodBuilder<object> _builder = AsyncTaskMethodBuilder<object>.Create();
    private TaskAwaiter<object> _awaiter;

    /// <summary>-1 运行中；&gt;= 0 挂起在恢复点 n；-2 已完成。生成代码按名字读它做恢复点分派与 finally 守卫。</summary>
    public int state = -1;

    public abstract void MoveNext();

    void IAsyncStateMachine.SetStateMachine(IAsyncStateMachine stateMachine) { }

    /// <summary>
    /// 本线程正在运行 MoveNext 的帧（生成的 MoveNext 开头 Enter、finally 里 Exit）。线程静态而不是 AsyncLocal：
    /// 每次 Start 改 AsyncLocal 要复制整个 ExecutionContext（宿主设置过的参数越多越慢，实测 1 µs），线程静态只是一次读写。
    /// </summary>
    [ThreadStatic] private static AsyncFrame t_current;

    /// <summary>帧自己的异常处理器栈（ExceptionHandlers：帧内的 $current-handlers 读写这里而不是 AsyncLocal）。
    /// 新帧为 null = 缺省表：调用方的 guard 是逃逸续延，在帧恢复到的线程上没有意义；体内没接住的条件让 Task 失败，
    /// 由 await / task-result 在等待方重新 raise（与 C# 的 async 异常一致，10 §2 D7）。放在帧里，挂起后自然保留。</summary>
    internal object handlers;

    /// <summary>当前线程正在运行的帧，不在帧里时为 null。</summary>
    public static AsyncFrame Current => t_current;

    /// <summary>当前代码是否在某个 async-lambda 的帧里：参数对象的赋值只影响本上下文（Parameters.cs）。</summary>
    public static bool InFrame => t_current != null;

    /// <summary>MoveNext 开头：登记本帧为当前帧，返回之前的（嵌套同步调用 async 过程时是外层帧）。</summary>
    public static AsyncFrame Enter(AsyncFrame frame)
    {
        var previous = t_current;
        t_current = frame;
        return previous;
    }

    /// <summary>MoveNext 的 finally：恢复之前的帧（挂起的 leave 也经过这里）。</summary>
    public static void Exit(AsyncFrame previous) => t_current = previous;

    /// <summary>同步运行到第一个未完成的 await（或结束），返回代表整个体的 Task。</summary>
    public Task<object> Start()
    {
        var self = this;
        _builder.Start(ref self);
        return _builder.Task;
    }

    /// <summary>await 的前半段：task 已完成返回 true（快路径，不分配）；否则 state = next、登记恢复并返回 false。</summary>
    public bool Suspend(object task, int next)
    {
        if (task is not Task<object> t)
        {
            // 非泛型 Task 与其他 Task<T> 本应由互操作转换（D8）；这里兜底转换，非 Task 报 &assertion（D3）
            if (task is Task any) t = Tasks.Box(any);
            else { Errors.AssertionViolation("await", "expected a task", task); return true; }
        }
        _awaiter = t.GetAwaiter();
        if (_awaiter.IsCompleted) return true;
        state = next;
        var self = this;
        _builder.AwaitUnsafeOnCompleted(ref _awaiter, ref self);
        return false;
    }

    /// <summary>
    /// await 的后半段：取被等待 Task 的结果。失败时：Scheme 条件重新 raise（体内的 guard 能接住），
    /// 其他 .NET 异常原样重新抛出（取消为 TaskCanceledException）。
    /// </summary>
    public object Resume()
    {
        state = -1;
        try { return _awaiter.GetResult(); }
        catch (SchemeException e) { return Errors.Raise(e.Condition); }
    }

    public void Complete(object value)
    {
        state = -2;
        _builder.SetResult(value);
    }

    public void Fail(Exception exception)
    {
        state = -2;
        _builder.SetException(exception);
    }
}

using System;
using System.Runtime.CompilerServices;
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

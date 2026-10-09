using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Reflection;
using System.Threading;
using System.Threading.Tasks;

namespace IronScheme.Core;

/// <summary>
/// Task 原语与 Task 的互操作转换（designs/10-async.md §1 D5、§2 D8）。
/// Scheme 侧的 task 统一是 <c>Task&lt;object&gt;</c>，结果是 Scheme 值；其他 <c>Task&lt;T&gt;</c> 与非泛型 <c>Task</c>
/// 进入 Scheme 时经 <see cref="Box(Task)"/> 转换，Scheme 的 task 交给 .NET 时经 <see cref="Unbox{T}"/> 转换。
/// 这里的 async 方法是普通的 C# 状态机，不依赖 Runtime Async。
/// </summary>
public static class Tasks
{
    private static Task RequireTask(object o, string who) => Errors.RequiresType<Task>(o, who);

    #region 查询与构造

    [Primitive("task?", Flags = PrimitiveFlags.Pure)]
    public static object IsTask(object o) => RT.Bool(o is Task);

    [Primitive("task-completed?")]
    public static object IsCompleted(object task) => RT.Bool(RequireTask(task, "task-completed?").IsCompleted);

    /// <summary>失败或被取消（两者 await 时都抛出）。</summary>
    [Primitive("task-faulted?")]
    public static object IsFaulted(object task)
    {
        var t = RequireTask(task, "task-faulted?");
        return RT.Bool(t.IsFaulted || t.IsCanceled);
    }

    /// <summary>阻塞等待并取结果；失败时 Scheme 条件重新 raise（guard 能接住），其他 .NET 异常原样抛出（不是 AggregateException）。</summary>
    [Primitive("task-result")]
    public static object Result(object task) => Unwrap(Box(RequireTask(task, "task-result")));

    /// <summary>取已完成（或阻塞等到完成）的 task 的结果；task 以 Scheme 条件失败时重新 raise。AsyncFrame.Resume 同此。</summary>
    public static object Unwrap(Task<object> task)
    {
        try { return task.GetAwaiter().GetResult(); }
        catch (SchemeException e) { return Errors.Raise(e.Condition); }
    }

    [Primitive("task-from-result")]
    public static object FromResult(object value) => Task.FromResult(value);

    /// <summary>参数是 .NET 异常或 Scheme 条件（后者包成 <see cref="SchemeException"/>）。</summary>
    [Primitive("task-from-exception")]
    public static object FromException(object exception) => Task.FromException<object>(ToException(exception));

    /// <summary>(task-delay 毫秒)：结果为未指定值。</summary>
    [Primitive("task-delay")]
    public static object Delay(object milliseconds)
    {
        int ms = Errors.RequiresType<int>(milliseconds, "task-delay");
        return DelayAsync(ms);
    }

    private static async Task<object> DelayAsync(int ms)
    {
        await Task.Delay(ms).ConfigureAwait(false);
        return Unspecified.Instance;
    }

    /// <summary>(task-yield)：在线程池上完成的 task，await 它把后续工作让给线程池（结果为未指定值）。</summary>
    [Primitive("task-yield")]
    public static object Yield()
    {
        var tcs = new TaskCompletionSource<object>(TaskCreationOptions.RunContinuationsAsynchronously);
        ThreadPool.UnsafeQueueUserWorkItem(static s => s.SetResult(Unspecified.Instance), tcs, preferLocal: false);
        return tcs.Task;
    }

    /// <summary>
    /// (task-run thunk)：在线程池上调用 thunk；thunk 返回 task 时展开（async-lambda 可以直接传入）。
    /// thunk 从缺省异常处理器表开始（调用方的 guard 不进入新 task）：没接住的条件让 task 失败。
    /// </summary>
    [Primitive("task-run")]
    public static object Run(object thunk)
    {
        var p = Errors.RequiresType<Procedure>(thunk, "task-run");
        return Task.Run(() =>
        {
            ExceptionHandlers.Set(null);
            var r = p.Invoke0();
            return r is Task t ? Box(t) : Task.FromResult(r);
        });
    }

    #endregion

    #region 续接与组合

    /// <summary>(task-then task proc)：task 成功完成后以结果调用 proc，proc 返回 task 时展开；task 失败时不调用 proc，失败原样传递。</summary>
    [Primitive("task-then")]
    public static object Then(object task, object proc)
    {
        var t = Box(RequireTask(task, "task-then"));
        var p = Errors.RequiresType<Procedure>(proc, "task-then");
        return ThenAsync(t, p);
    }

    private static async Task<object> ThenAsync(Task<object> task, Procedure proc)
    {
        var r = await task;          // 与 await 相同：回到捕获的 SynchronizationContext（D4）
        ExceptionHandlers.Set(null); // 回调从缺省处理器表开始（同 task-run）
        var v = proc.Invoke1(r);
        return v is Task t ? await Box(t) : v;
    }

    /// <summary>(task-when-all 列表)：全部完成后结果为各结果组成的列表（顺序同输入）；任一失败则失败。</summary>
    [Primitive("task-when-all")]
    public static object WhenAll(object tasks) => WhenAllAsync(ToTaskArray(tasks, "task-when-all"));

    private static async Task<object> WhenAllAsync(Task<object>[] tasks)
    {
        var results = await Task.WhenAll(tasks);
        return Cons.FromArray(results);
    }

    /// <summary>(task-when-any 列表)：结果为最先完成的那个 task（用 task-result 取它的值）。</summary>
    [Primitive("task-when-any")]
    public static object WhenAny(object tasks)
    {
        var ts = ToTaskArray(tasks, "task-when-any");
        if (ts.Length == 0) return Errors.AssertionViolation("task-when-any", "expected a non-empty list", tasks);
        return WhenAnyAsync(ts);
    }

    private static async Task<object> WhenAnyAsync(Task<object>[] tasks) => await Task.WhenAny(tasks);

    private static Task<object>[] ToTaskArray(object list, string who)
    {
        var result = new List<Task<object>>();
        object l = list;
        for (; l is Cons c; l = c.cdr)
            result.Add(Box(RequireTask(c.car, who)));
        if (l != null) Errors.AssertionViolation(who, "expected a list of tasks", list);
        return result.ToArray();
    }

    #endregion

    #region TaskCompletionSource

    private static TaskCompletionSource<object> RequireSource(object o, string who) =>
      Errors.RequiresType<TaskCompletionSource<object>>(o, who);

    /// <summary>续接在线程池上运行，不在设置结果的线程上同步执行。</summary>
    [Primitive("make-task-source")]
    public static object MakeSource() => new TaskCompletionSource<object>(TaskCreationOptions.RunContinuationsAsynchronously);

    [Primitive("task-source-task")]
    public static object SourceTask(object source) => RequireSource(source, "task-source-task").Task;

    [Primitive("task-source-set-result!")]
    public static object SourceSetResult(object source, object value)
    {
        if (!RequireSource(source, "task-source-set-result!").TrySetResult(value))
            return Errors.AssertionViolation("task-source-set-result!", "task already completed", source);
        return Unspecified.Instance;
    }

    [Primitive("task-source-set-exception!")]
    public static object SourceSetException(object source, object exception)
    {
        if (!RequireSource(source, "task-source-set-exception!").TrySetException(ToException(exception)))
            return Errors.AssertionViolation("task-source-set-exception!", "task already completed", source);
        return Unspecified.Instance;
    }

    private static Exception ToException(object o) => o as Exception ?? new SchemeException(o);

    #endregion

    #region Task<T> ↔ Task<object>（D8）

    /// <summary>Task&lt;T&gt; → Task&lt;object&gt;：结果经 <see cref="Interop.ConvertFrom"/> 转为 Scheme 值，异常与取消保留。</summary>
    public static Task<object> Box<T>(Task<T> task)
    {
        if (task is Task<object> o) return o;
        if (task.Status == TaskStatus.RanToCompletion) return Task.FromResult(Interop.ConvertFrom(task.Result, typeof(T)));
        return BoxAsync(task);
    }

    private static async Task<object> BoxAsync<T>(Task<T> task) => Interop.ConvertFrom(await task.ConfigureAwait(false), typeof(T));

    /// <summary>任意 Task → Task&lt;object&gt;：按运行时类型分派到 <see cref="Box{T}"/>；非泛型 Task 的结果是未指定值。</summary>
    public static Task<object> Box(Task task)
    {
        if (task is Task<object> o) return o;
        var resultType = ResultType(task.GetType());
        if (resultType != null) return s_boxers.GetOrAdd(resultType, MakeBoxer)(task);
        if (task.Status == TaskStatus.RanToCompletion) return Task.FromResult<object>(Unspecified.Instance);
        return BoxPlainAsync(task);
    }

    private static async Task<object> BoxPlainAsync(Task task)
    {
        await task.ConfigureAwait(false);
        return Unspecified.Instance;
    }

    /// <summary>Task&lt;object&gt; → Task&lt;T&gt;：结果经 <see cref="Interop.ConvertTo"/> 转为 T。</summary>
    public static Task<T> Unbox<T>(Task<object> task)
    {
        if (task is Task<T> same) return same;
        if (task.Status == TaskStatus.RanToCompletion)
        {
            try { return Task.FromResult((T)Interop.ConvertTo(task.Result, typeof(T), "task")); }
            catch (Exception e) { return Task.FromException<T>(e); }      // 转换失败也表现为失败的 Task
        }
        return UnboxAsync<T>(task);
    }

    private static async Task<T> UnboxAsync<T>(Task<object> task) => (T)Interop.ConvertTo(await task.ConfigureAwait(false), typeof(T), "task");

    /// <summary>Scheme 值 → 目标 Task 类型（ConvertTo 用）：Task 按结果类型转换，非 Task 的值包成已完成的 Task。</summary>
    public static object ToTaskType(object value, Type target, string who)
    {
        var task = value as Task;
        var resultType = ResultType(target);
        if (resultType == null)                                  // 目标是非泛型 Task
            return task ?? Task.CompletedTask;
        if (task == null)
            return s_fromResult.GetOrAdd(resultType, MakeFromResult)(Interop.ConvertTo(value, resultType, who));
        return s_unboxers.GetOrAdd(resultType, MakeUnboxer)(Box(task));
    }

    /// <summary>t 是 Task&lt;X&gt;（或其子类）时返回 X；非泛型 Task（含 async Task 方法实际返回的 Task&lt;VoidTaskResult&gt;）返回 null。</summary>
    public static Type ResultType(Type t)
    {
        for (; t != null && t != typeof(object); t = t.BaseType)
            if (t.IsGenericType && t.GetGenericTypeDefinition() == typeof(Task<>))
            {
                var r = t.GetGenericArguments()[0];
                return r.FullName == "System.Threading.Tasks.VoidTaskResult" ? null : r;
            }
        return null;
    }

    private static readonly ConcurrentDictionary<Type, Func<Task, Task<object>>> s_boxers = new();
    private static readonly ConcurrentDictionary<Type, Func<Task<object>, object>> s_unboxers = new();
    private static readonly ConcurrentDictionary<Type, Func<object, object>> s_fromResult = new();

    private static Func<Task, Task<object>> MakeBoxer(Type resultType)
    {
        var m = typeof(Tasks).GetMethod(nameof(BoxGeneric), BindingFlags.NonPublic | BindingFlags.Static).MakeGenericMethod(resultType);
        return m.CreateDelegate<Func<Task, Task<object>>>();
    }

    private static Task<object> BoxGeneric<T>(Task task) => Box((Task<T>)task);

    private static Func<Task<object>, object> MakeUnboxer(Type resultType)
    {
        var m = typeof(Tasks).GetMethod(nameof(UnboxGeneric), BindingFlags.NonPublic | BindingFlags.Static).MakeGenericMethod(resultType);
        return m.CreateDelegate<Func<Task<object>, object>>();
    }

    private static object UnboxGeneric<T>(Task<object> task) => Unbox<T>(task);

    private static Func<object, object> MakeFromResult(Type resultType)
    {
        var m = typeof(Tasks).GetMethod(nameof(FromResultGeneric), BindingFlags.NonPublic | BindingFlags.Static).MakeGenericMethod(resultType);
        return m.CreateDelegate<Func<object, object>>();
    }

    private static object FromResultGeneric<T>(object value) => Task.FromResult((T)value);

    #endregion
}

using System;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using IronScheme.Core;
using NUnit.Framework;

namespace IronScheme.Core.Tests;

/// <summary>iron-050：AsyncFrame、Task 原语与转换、参数对象的 AsyncLocal 存储、异常处理器栈。</summary>
public class AsyncFrameTests
{
    /// <summary>手写的帧子类，形状与 codegen 将生成的相同：(await a) + (await b)。</summary>
    private sealed class SumFrame : AsyncFrame
    {
        public object a, b, t;
        public int suspendedThread, resumedThread;

        public override void MoveNext()
        {
            try
            {
                if (state == 0) goto L0;
                if (state == 1) goto L1;
                if (!Suspend(a, 0)) { suspendedThread = Environment.CurrentManagedThreadId; return; }
            L0:
                t = Resume();
                if (!Suspend(b, 1)) return;
            L1:
                resumedThread = Environment.CurrentManagedThreadId;
                Complete((int)t + (int)Resume());
            }
            catch (Exception e) { Fail(e); }
        }
    }

    private static async Task<object> After(int ms, object v) { await Task.Delay(ms); return v; }

    [Test]
    public void SyncFastPathCompletesInline()
    {
        var f = new SumFrame { a = Task.FromResult<object>(1), b = Task.FromResult<object>(2) };
        var task = f.Start();
        Assert.That(task.IsCompletedSuccessfully, Is.True);
        Assert.That(task.Result, Is.EqualTo(3));
        Assert.That(f.state, Is.EqualTo(-2));
    }

    [Test]
    public void SuspendsAndResumes()
    {
        var f = new SumFrame { a = After(30, 10), b = After(30, 20) };
        var task = f.Start();
        Assert.That(task.IsCompleted, Is.False);
        Assert.That(f.state, Is.EqualTo(0));
        Assert.That(task.Result, Is.EqualTo(30));
        Assert.That(f.state, Is.EqualTo(-2));
    }

    [Test]
    public void AwaitedFailurePropagatesUnwrapped()
    {
        var f = new SumFrame { a = Task.FromResult<object>(1), b = Task.FromException<object>(new InvalidOperationException("boom")) };
        var task = f.Start();
        Assert.That(task.IsFaulted, Is.True);
        Assert.That(task.Exception.InnerException, Is.InstanceOf<InvalidOperationException>().With.Message.EqualTo("boom"));
    }

    [Test]
    public void SchemeConditionIsReraised()
    {
        // 没有登记钩子时 Errors.Raise 直接抛 SchemeException；登记后走 Scheme 的 raise，体内的 guard 能接住
        var f = new SumFrame { a = Task.FromResult<object>(1), b = Task.FromException<object>(new SchemeException("cond")) };
        var task = f.Start();
        Assert.That(task.IsFaulted, Is.True);
        Assert.That(task.Exception.InnerException, Is.InstanceOf<SchemeException>().With.Property("Condition").EqualTo("cond"));
    }

    [Test]
    public void NonTaskIsAssertionViolation()
    {
        var f = new SumFrame { a = 42, b = Task.FromResult<object>(2) };
        var task = f.Start();
        Assert.That(task.IsFaulted, Is.True);
        var e = task.Exception.InnerException as SchemeRuntimeError;
        Assert.That(e, Is.Not.Null);
        Assert.That(e.Who, Is.EqualTo("await"));
    }

    [Test]
    public void OtherTaskTypesAreBoxed()
    {
        var f = new SumFrame { a = Task.FromResult(5), b = Task.FromResult(6L) };   // Task<int>、Task<long>
        Assert.That(f.Start().Result, Is.EqualTo(11));
    }

    private sealed class ParamFrame : AsyncFrame
    {
        public ParamSlot slot;
        public object seenAfterResume;

        public override void MoveNext()
        {
            try
            {
                if (state == 0) goto L0;
                slot.Value = "inside";
                if (!Suspend(After(20, null), 0)) return;
            L0:
                Resume();
                seenAfterResume = slot.Value;
                Complete(Environment.CurrentManagedThreadId);
            }
            catch (Exception e) { Fail(e); }
        }
    }

    [Test]
    public void AsyncLocalFlowsAcrossSuspensionButNotOut()
    {
        var slot = Task.Run(() => new ParamSlot("initial")).Result;   // 创建线程不是本线程：本线程的赋值不更新回退值
        var f = new ParamFrame { slot = slot };
        var task = f.Start();
        Assert.That(slot.Value, Is.EqualTo("initial"), "赋值不流出帧");
        task.Wait();
        Assert.That(f.seenAfterResume, Is.EqualTo("inside"), "恢复后仍看到挂起前的赋值");
        Assert.That(slot.Value, Is.EqualTo("initial"));
    }
}

public class TaskConversionTests
{
    private static async Task PlainAsync() { await Task.Yield(); }

    [Test]
    public void BoxConvertsResultToSchemeValue()
    {
        Assert.That(Tasks.Box(Task.FromResult(3)).Result, Is.EqualTo(3));
        Assert.That(Tasks.Box(Task.FromResult(7L)).Result, Is.EqualTo(7).And.InstanceOf<int>());
        Assert.That(Tasks.Box(Task.FromResult(true)).Result, Is.SameAs(RT.True));
        Assert.That(Tasks.Box(Task.FromResult("s")).Result, Is.EqualTo("s"));
        var same = Task.FromResult<object>(1);
        Assert.That(Tasks.Box(same), Is.SameAs(same));
    }

    [Test]
    public void BoxOfPlainTaskIsUnspecified()
    {
        Assert.That(Tasks.Box(Task.CompletedTask).Result, Is.SameAs(Unspecified.Instance));
        Assert.That(Tasks.Box(PlainAsync()).Result, Is.SameAs(Unspecified.Instance));     // Task<VoidTaskResult>
        Assert.That(Tasks.Box(Task.Delay(10)).Result, Is.SameAs(Unspecified.Instance));
    }

    [Test]
    public void BoxKeepsExceptionAndCancellation()
    {
        var faulted = Tasks.Box(Task.FromException<int>(new InvalidOperationException("x")));
        Assert.That(faulted.IsFaulted, Is.True);
        Assert.That(faulted.Exception.InnerException, Is.InstanceOf<InvalidOperationException>());

        var canceled = Tasks.Box(Task.FromCanceled<int>(new CancellationToken(true)));
        Assert.That(canceled.IsCanceled, Is.True);

        var late = Tasks.Box(Task.Run(async () => { await Task.Delay(20); throw new ArgumentException("late"); return 1; }));
        Assert.That(() => late.GetAwaiter().GetResult(), Throws.ArgumentException);
    }

    [Test]
    public void UnboxConvertsAndFails()
    {
        Assert.That(Tasks.Unbox<int>(Task.FromResult<object>(3)).Result, Is.EqualTo(3));
        Assert.That(Tasks.Unbox<string>(Task.FromResult<object>(SchemeString.MutableFrom("abc"))).Result, Is.EqualTo("abc"));
        var bad = Tasks.Unbox<int>(Task.FromResult<object>("nope"));
        Assert.That(bad.IsFaulted, Is.True);
        Assert.That(bad.Exception.InnerException, Is.InstanceOf<SchemeRuntimeError>());
        var late = Tasks.Unbox<int>(Task.Run(async () => { await Task.Delay(20); return (object)9; }));
        Assert.That(late.Result, Is.EqualTo(9));
    }

    [Test]
    public void InteropConvertFromBoxesTasks()
    {
        var t = Interop.ConvertFrom(Task.FromResult(5), typeof(Task<int>));
        Assert.That(t, Is.InstanceOf<Task<object>>());
        Assert.That(((Task<object>)t).Result, Is.EqualTo(5));
        Assert.That(Interop.ConvertFrom(Task.FromResult(5), typeof(object)), Is.InstanceOf<Task<object>>());   // 按运行时类型
        Assert.That(Interop.ConvertFrom(Task.CompletedTask, typeof(Task)), Is.InstanceOf<Task<object>>());
    }

    [Test]
    public void InteropConvertToTaskTypes()
    {
        var boxed = Task.FromResult<object>(4);
        Assert.That(Interop.ConvertTo(boxed, typeof(Task<int>)), Is.InstanceOf<Task<int>>().With.Property("Result").EqualTo(4));
        Assert.That(Interop.ConvertTo(boxed, typeof(Task)), Is.SameAs(boxed));
        Assert.That(Interop.ConvertTo(boxed, typeof(Task<object>)), Is.SameAs(boxed));
        Assert.That(Interop.ConvertTo(7, typeof(Task<int>)), Is.InstanceOf<Task<int>>().With.Property("Result").EqualTo(7));   // 同步值包成 Task
        Assert.That(Interop.ConvertTo(Unspecified.Instance, typeof(Task)), Is.SameAs(Task.CompletedTask));
        Assert.That(Interop.ConvertTo(Task.FromResult(1), typeof(Task<long>)), Is.InstanceOf<Task<long>>().With.Property("Result").EqualTo(1L));
    }

    [Test]
    public async Task ProcedureAsTaskReturningDelegate()
    {
        var asyncProc = new Fn(_ => Task.FromResult<object>(5));
        var d = (Func<Task<int>>)Interop.ToDelegate(typeof(Func<Task<int>>), asyncProc);
        Assert.That(await d(), Is.EqualTo(5));

        var syncProc = new Fn(a => (int)a[0] + 1);
        var d2 = (Func<int, Task<int>>)Interop.ToDelegate(typeof(Func<int, Task<int>>), syncProc);
        Assert.That(await d2(9), Is.EqualTo(10));

        var plain = (Func<Task>)Interop.ToDelegate(typeof(Func<Task>), new Fn(_ => Unspecified.Instance));
        await plain();

        var failing = (Func<Task<int>>)Interop.ToDelegate(typeof(Func<Task<int>>), new Fn(_ => Task.FromException<object>(new InvalidOperationException())));
        Assert.That(async () => await failing(), Throws.InvalidOperationException);
    }
}

public class TaskPrimitiveTests
{
    [Test]
    public void PredicatesAndResult()
    {
        var ok = Task.FromResult<object>(1);
        Assert.That(Tasks.IsTask(ok), Is.SameAs(RT.True));
        Assert.That(Tasks.IsTask(1), Is.SameAs(RT.False));
        Assert.That(Tasks.IsCompleted(ok), Is.SameAs(RT.True));
        Assert.That(Tasks.IsFaulted(ok), Is.SameAs(RT.False));
        Assert.That(Tasks.Result(ok), Is.EqualTo(1));
        Assert.That(Tasks.Result(Task.FromResult(2)), Is.EqualTo(2));

        var bad = Tasks.FromException(new InvalidOperationException("e"));
        Assert.That(Tasks.IsFaulted(bad), Is.SameAs(RT.True));
        Assert.That(() => Tasks.Result(bad), Throws.InvalidOperationException);      // 不是 AggregateException

        var cond = Tasks.FromException(Symbol.Intern("some-condition"));
        Assert.That(() => Tasks.Result(cond), Throws.InstanceOf<SchemeException>().With.Property("Condition").EqualTo(Symbol.Intern("some-condition")));
        Assert.That(() => Tasks.Result("x"), Throws.InstanceOf<SchemeRuntimeError>());
    }

    [Test]
    public void DelayYieldRun()
    {
        var d = (Task<object>)Tasks.Delay(20);
        Assert.That(d.IsCompleted, Is.False);
        Assert.That(d.Result, Is.SameAs(Unspecified.Instance));
        Assert.That(((Task<object>)Tasks.Yield()).Result, Is.SameAs(Unspecified.Instance));

        int tid = Environment.CurrentManagedThreadId;
        var r = (Task<object>)Tasks.Run(new Fn(_ => Environment.CurrentManagedThreadId));
        Assert.That(r.Result, Is.Not.EqualTo(tid));
        var unwrapped = (Task<object>)Tasks.Run(new Fn(_ => Task.FromResult<object>("inner")));
        Assert.That(unwrapped.Result, Is.EqualTo("inner"));
        var unwrappedInt = (Task<object>)Tasks.Run(new Fn(_ => Task.FromResult(3)));
        Assert.That(unwrappedInt.Result, Is.EqualTo(3));
        Assert.That(() => Tasks.Run(1), Throws.InstanceOf<SchemeRuntimeError>());
    }

    [Test]
    public void ThenChainsAndUnwraps()
    {
        var t = (Task<object>)Tasks.Then(Task.FromResult<object>(1), new Fn(a => (int)a[0] + 1));
        Assert.That(t.Result, Is.EqualTo(2));
        var t2 = (Task<object>)Tasks.Then(Tasks.Delay(10), new Fn(_ => Task.FromResult<object>("async")));
        Assert.That(t2.Result, Is.EqualTo("async"));
        bool called = false;
        var t3 = (Task<object>)Tasks.Then(Tasks.FromException(new InvalidOperationException()), new Fn(_ => called = true));
        Assert.That(() => t3.GetAwaiter().GetResult(), Throws.InvalidOperationException);
        Assert.That(called, Is.False);
        var t4 = (Task<object>)Tasks.Then(Task.FromResult<object>(1), new Fn(_ => throw new ArgumentException("in callback")));
        Assert.That(() => t4.GetAwaiter().GetResult(), Throws.ArgumentException);
    }

    [Test]
    public void WhenAllAndWhenAny()
    {
        var list = Cons.FromArray(Task.FromResult<object>(1), Tasks.Delay(10), Task.FromResult(3));
        var all = (Task<object>)Tasks.WhenAll(list);
        Assert.That(((Cons)all.Result).Cast<object>().ToArray(), Is.EqualTo(new object[] { 1, Unspecified.Instance, 3 }));
        Assert.That(((Task<object>)Tasks.WhenAll(null)).Result, Is.Null);

        var slow = Tasks.Delay(200);
        var fast = Task.FromResult<object>("fast");
        var any = (Task<object>)Tasks.WhenAny(Cons.FromArray(slow, fast));
        Assert.That(any.Result, Is.SameAs(fast));
        Assert.That(() => Tasks.WhenAny(null), Throws.InstanceOf<SchemeRuntimeError>());
        Assert.That(() => Tasks.WhenAll(Cons.FromArray(1)), Throws.InstanceOf<SchemeRuntimeError>());
    }

    [Test]
    public void TaskCompletionSource()
    {
        var src = Tasks.MakeSource();
        var task = (Task<object>)Tasks.SourceTask(src);
        Assert.That(task.IsCompleted, Is.False);
        Tasks.SourceSetResult(src, "done");
        Assert.That(task.Result, Is.EqualTo("done"));
        Assert.That(() => Tasks.SourceSetResult(src, "again"), Throws.InstanceOf<SchemeRuntimeError>());

        var src2 = Tasks.MakeSource();
        Tasks.SourceSetException(src2, Symbol.Intern("cond"));
        Assert.That(() => Tasks.Result(Tasks.SourceTask(src2)), Throws.InstanceOf<SchemeException>());
        Assert.That(() => Tasks.SourceTask(1), Throws.InstanceOf<SchemeRuntimeError>());
    }
}

public class ParameterSlotTests
{
    [Test]
    public void InitialSetAndEmptyList()
    {
        var slot = (ParamSlot)Parameters.MakeSlot("init");
        Assert.That(Parameters.Ref(slot), Is.EqualTo("init"));
        Parameters.Set(slot, "v");
        Assert.That(Parameters.Ref(slot), Is.EqualTo("v"));
        Parameters.Set(slot, null);                           // 空表不是"未设置"
        Assert.That(Parameters.Ref(slot), Is.Null);
        var nilInit = new ParamSlot(null);
        Assert.That(nilInit.Value, Is.Null);
        nilInit.Value = 1;
        Assert.That(nilInit.Value, Is.EqualTo(1));
    }

    [Test]
    public void ValueFlowsIntoChildTaskButNotBack()
    {
        var slot = new ParamSlot("init");
        slot.Value = "parent";
        var seenInChild = Task.Run(() =>
        {
            var before = slot.Value;
            slot.Value = "child";
            return (before, slot.Value);
        }).Result;
        Assert.That(seenInChild, Is.EqualTo(("parent", "child")));
        Assert.That(slot.Value, Is.EqualTo("parent"));

        string seenInThread = null;
        var th = new Thread(() => seenInThread = (string)slot.Value);
        th.Start(); th.Join();
        Assert.That(seenInThread, Is.EqualTo("parent"));
        slot.Value = "init";
    }

    [Test]
    public void OwnerThreadAssignmentIsTheFallbackForOtherContexts()
    {
        // 与旧实现相同：创建线程上的赋值对没有自己值的上下文可见（宿主启动时在主线程设置的参数要让工作线程看到）
        var slot = new ParamSlot("init");
        slot.Value = "set-by-owner";
        object seen = null;
        using (ExecutionContext.SuppressFlow())                                   // 不带本线程的 ExecutionContext
        {
            var done = new ManualResetEventSlim();
            ThreadPool.UnsafeQueueUserWorkItem(_ => { seen = slot.Value; done.Set(); }, null);
            done.Wait();
        }
        Assert.That(seen, Is.EqualTo("set-by-owner"));

        // 其他线程上的赋值不改回退值
        Task.Run(() => slot.Value = "set-by-child").Wait();
        using (ExecutionContext.SuppressFlow())
        {
            var done = new ManualResetEventSlim();
            ThreadPool.UnsafeQueueUserWorkItem(_ => { seen = slot.Value; done.Set(); }, null);
            done.Wait();
        }
        Assert.That(seen, Is.EqualTo("set-by-owner"));
        Assert.That(slot.Value, Is.EqualTo("set-by-owner"));
    }
}

public class ExceptionHandlerStackTests
{
    [Test]
    public void DefaultHandlerThrowsSchemeException()
    {
        var hs = ExceptionHandlers.Current() as Cons;
        Assert.That(hs, Is.Not.Null);
        Assert.That(hs.cdr, Is.Null);
        var h = (Procedure)hs.car;
        var e = Assert.Throws<SchemeException>(() => h.Invoke1("cond"));
        Assert.That(e.Condition, Is.EqualTo("cond"));
    }

    [Test]
    public void SetAndRestore()
    {
        var saved = ExceptionHandlers.Current();
        var mine = new Cons(new Fn(_ => "mine"), saved);
        ExceptionHandlers.Set(mine);
        Assert.That(ExceptionHandlers.Current(), Is.SameAs(mine));
        Assert.That(Task.Run(() => ExceptionHandlers.Current()).Result, Is.SameAs(mine));   // 流入子任务
        ExceptionHandlers.Set(null);
        Assert.That(ExceptionHandlers.Current(), Is.SameAs(saved));                       // 空表 → 缺省
    }
}

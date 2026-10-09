// iron-049：验证"AsyncFrame + AsyncTaskMethodBuilder"（Roslyn 方式的状态机）能否当 async-lambda 的后端
//   每个 async-lambda 编译成 AsyncFrame 的子类：参数与局部变量是字段，MoveNext 是函数体；
//   await = call Suspend(task, N) → 已完成则继续，否则 leave 出去；恢复时按 state 分派回 L_N 再 call Resume。
//   finally 块用 state < 0 守卫，挂起时跳过；try 块内的恢复点在进入 try 之后再分派一次（IL 不许从外面跳进 try）。
// 测试项与 iron-048 相同（去掉 tail），另加 stack —— 同步完成路径上深递归时的栈深度。
// 用法：dotnet run -c Release -- all | save | load all
using System.Diagnostics;
using System.Reflection;
using System.Reflection.Emit;
using System.Runtime.CompilerServices;

public abstract class Procedure
{
    public virtual object Invoke1(object a) => throw new InvalidOperationException("arity 1");
}

/// <summary>运行时基类：把 builder 与 awaiter 的 ref 操作收在 C# 里，发射的代码只做普通调用。</summary>
public abstract class AsyncFrame : IAsyncStateMachine
{
    AsyncTaskMethodBuilder<object> builder = AsyncTaskMethodBuilder<object>.Create();
    TaskAwaiter<object> awaiter;
    public int state = -1;                       // -1 运行中；>= 0 挂起在恢复点 N

    public abstract void MoveNext();
    void IAsyncStateMachine.SetStateMachine(IAsyncStateMachine m) { }

    public Task<object> Start() { var self = this; builder.Start(ref self); return builder.Task; }

    /// <summary>await 前半段：已完成返回 true（快路径）；否则登记恢复并返回 false。</summary>
    public bool Suspend(object task, int next)
    {
        awaiter = ((Task<object>)task).GetAwaiter();
        if (awaiter.IsCompleted) return true;
        state = next;
        var self = this;
        builder.AwaitUnsafeOnCompleted(ref awaiter, ref self);
        return false;
    }
    public object Resume() { state = -1; return awaiter.GetResult(); }
    public void Complete(object v) { state = -2; builder.SetResult(v); }
    public void Fail(Exception e) { state = -2; builder.SetException(e); }
}

public static class RT
{
    public static readonly AsyncLocal<object> Param = new();
    [ThreadStatic] public static object ThreadParam;
    public static int FinallyCount;
    public static int MaxStackDepth;

    public static object Tid() => Environment.CurrentManagedThreadId;
    public static object Done(object v) => Task.FromResult(v);
    public static object Fail(object msg) => Task.FromException<object>(new InvalidOperationException((string)msg));
    public static object Delay(object ms) => DelayAsync((int)ms);
    static async Task<object> DelayAsync(int ms) { await Task.Delay(ms).ConfigureAwait(false); return ms; }
    public static async Task<object> DelayAsync0(object t) => await (Task<object>)t;
    public static object Yield()
    {
        var tcs = new TaskCompletionSource<object>(TaskCreationOptions.RunContinuationsAsynchronously);
        ThreadPool.UnsafeQueueUserWorkItem(_ => tcs.SetResult(null), null);
        return tcs.Task;
    }
    public static object Identity(object o) => o;
    public static object Message(Exception e) => e.GetType().Name + ": " + e.Message;
    public static object Pair(object a, object b) => (a, b).ToString();
    public static object NoteStack()
    {
        var d = new StackTrace(false).FrameCount;
        if (d > MaxStackDepth) MaxStackDepth = d;
        return null;
    }
}

/// <summary>发射一个 AsyncFrame 子类：字段、构造函数、MoveNext，以及 Gen 上同名的静态入口 Name(args) = new Frame(args).Start()。</summary>
sealed class FrameBuilder
{
    public readonly TypeBuilder Frame;
    public readonly MethodBuilder Entry;
    public readonly ILGenerator IL;
    readonly Dictionary<string, FieldBuilder> fields = new();
    readonly Dictionary<int, Label> resume = new();
    readonly Label end;
    readonly FieldInfo stateF = typeof(AsyncFrame).GetField("state");
    readonly LocalBuilder tmp;

    public FrameBuilder(ModuleBuilder mod, TypeBuilder gen, string name, string[] parameters, string[] locals)
    {
        Frame = mod.DefineType(name + "Frame", TypeAttributes.Public | TypeAttributes.Sealed, typeof(AsyncFrame));
        foreach (var f in parameters.Concat(locals)) fields[f] = Frame.DefineField(f, typeof(object), FieldAttributes.Public);
        var ctor = Frame.DefineConstructor(MethodAttributes.Public, CallingConventions.Standard, Enumerable.Repeat(typeof(object), parameters.Length).ToArray());
        {
            var il = ctor.GetILGenerator();
            il.Emit(OpCodes.Ldarg_0); il.Emit(OpCodes.Call, typeof(AsyncFrame).GetConstructor(BindingFlags.NonPublic | BindingFlags.Instance, Type.EmptyTypes));
            for (int i = 0; i < parameters.Length; i++) { il.Emit(OpCodes.Ldarg_0); il.Emit(OpCodes.Ldarg, i + 1); il.Emit(OpCodes.Stfld, fields[parameters[i]]); }
            il.Emit(OpCodes.Ret);
        }
        // Gen.Name(args) = new Frame(args).Start()
        {
            var entry = Entry = gen.DefineMethod(name, MethodAttributes.Public | MethodAttributes.Static, typeof(Task<object>), Enumerable.Repeat(typeof(object), parameters.Length).ToArray());
            var il = entry.GetILGenerator();
            for (int i = 0; i < parameters.Length; i++) il.Emit(OpCodes.Ldarg, i);
            il.Emit(OpCodes.Newobj, ctor); il.Emit(OpCodes.Call, typeof(AsyncFrame).GetMethod("Start")); il.Emit(OpCodes.Ret);
        }
        var mn = Frame.DefineMethod("MoveNext", MethodAttributes.Public | MethodAttributes.Virtual | MethodAttributes.HideBySig, typeof(void), Type.EmptyTypes);
        IL = mn.GetILGenerator();
        tmp = IL.DeclareLocal(typeof(object));
        end = IL.DefineLabel();
        // 整个函数体包在 try { … } catch (Exception e) { Fail(e) } 里
        IL.BeginExceptionBlock();
    }

    public Label ResumeLabel(int n) => resume.TryGetValue(n, out var l) ? l : resume[n] = IL.DefineLabel();

    /// <summary>恢复点分派：state == n 就跳到 target（缺省为恢复点 n 的标签）。用 beq 链，Lcil 没有 switch。</summary>
    public void Dispatch(params (int state, Label target)[] cases)
    {
        foreach (var (s, l) in cases) { IL.Emit(OpCodes.Ldarg_0); IL.Emit(OpCodes.Ldfld, stateF); IL.Emit(OpCodes.Ldc_I4, s); IL.Emit(OpCodes.Beq, l); }
    }
    public void Dispatch(params int[] states) => Dispatch(states.Select(s => (s, ResumeLabel(s))).ToArray());

    public void Ld(string f) { IL.Emit(OpCodes.Ldarg_0); IL.Emit(OpCodes.Ldfld, fields[f]); }
    public void St(string f) { IL.Emit(OpCodes.Stloc, tmp); IL.Emit(OpCodes.Ldarg_0); IL.Emit(OpCodes.Ldloc, tmp); IL.Emit(OpCodes.Stfld, fields[f]); }
    public void LdInt(string f) { Ld(f); IL.Emit(OpCodes.Unbox_Any, typeof(int)); }
    public void StInt(string f) { IL.Emit(OpCodes.Box, typeof(int)); St(f); }
    public void Call(string rt) => IL.Emit(OpCodes.Call, typeof(RT).GetMethod(rt));

    /// <summary>(await task)：栈上 task → 栈上结果。</summary>
    public void Await(int n)
    {
        IL.Emit(OpCodes.Stloc, tmp);
        IL.Emit(OpCodes.Ldarg_0); IL.Emit(OpCodes.Ldloc, tmp); IL.Emit(OpCodes.Ldc_I4, n);
        IL.Emit(OpCodes.Call, typeof(AsyncFrame).GetMethod("Suspend"));
        IL.Emit(OpCodes.Brtrue, ResumeLabel(n));
        IL.Emit(OpCodes.Leave, end);                 // 挂起：离开所有 try；finally 有 state 守卫
        IL.MarkLabel(ResumeLabel(n));
        IL.Emit(OpCodes.Ldarg_0); IL.Emit(OpCodes.Call, typeof(AsyncFrame).GetMethod("Resume"));
    }

    /// <summary>栈上的值作为结果完成。</summary>
    public void Complete()
    {
        IL.Emit(OpCodes.Stloc, tmp); IL.Emit(OpCodes.Ldarg_0); IL.Emit(OpCodes.Ldloc, tmp);
        IL.Emit(OpCodes.Call, typeof(AsyncFrame).GetMethod("Complete"));
        IL.Emit(OpCodes.Leave, end);
    }

    /// <summary>用户 finally 块的开头：state >= 0（挂起中）就跳过块体。返回跳过标签，块体结束时 MarkLabel。</summary>
    public Label BeginGuardedFinally()
    {
        IL.BeginFinallyBlock();
        var skip = IL.DefineLabel();
        IL.Emit(OpCodes.Ldarg_0); IL.Emit(OpCodes.Ldfld, stateF); IL.Emit(OpCodes.Ldc_I4_0); IL.Emit(OpCodes.Bge, skip);
        return skip;
    }

    public Type Finish()
    {
        IL.BeginCatchBlock(typeof(Exception));
        IL.Emit(OpCodes.Stloc, tmp); IL.Emit(OpCodes.Ldarg_0); IL.Emit(OpCodes.Ldloc, tmp); IL.Emit(OpCodes.Castclass, typeof(Exception));
        IL.Emit(OpCodes.Call, typeof(AsyncFrame).GetMethod("Fail"));
        IL.Emit(OpCodes.Leave, end);
        IL.EndExceptionBlock();
        IL.MarkLabel(end);
        IL.Emit(OpCodes.Ret);
        return Frame.CreateType();
    }
}

public static class Program
{
    public static Type BuildGen(ModuleBuilder mod)
    {
        var gen = mod.DefineType("Gen", TypeAttributes.Public | TypeAttributes.Abstract | TypeAttributes.Sealed);
        var entries = new Dictionary<string, MethodBuilder>();
        MethodBuilder Entry(string n) => entries[n];

        // Echo(task) = await task
        {
            var f = new FrameBuilder(mod, gen, "Echo", new[] { "task" }, new string[0]); entries["Echo"] = f.Entry;
            f.Dispatch(1);
            f.Ld("task"); f.Await(1); f.Complete();
            f.Finish();
        }
        // Loop(n): i=0,sum=0; while i<n { await Yield(); sum+=i; i++ }; sum
        {
            var f = new FrameBuilder(mod, gen, "Loop", new[] { "n" }, new[] { "i", "sum" }); entries["Loop"] = f.Entry;
            var il = f.IL; var top = il.DefineLabel(); var done = il.DefineLabel();
            f.Dispatch(1);
            il.Emit(OpCodes.Ldc_I4_0); f.StInt("i"); il.Emit(OpCodes.Ldc_I4_0); f.StInt("sum");
            il.MarkLabel(top);
            f.LdInt("i"); f.LdInt("n"); il.Emit(OpCodes.Bge, done);
            f.Call("Yield"); f.Await(1); il.Emit(OpCodes.Pop);
            f.LdInt("sum"); f.LdInt("i"); il.Emit(OpCodes.Add); f.StInt("sum");
            f.LdInt("i"); il.Emit(OpCodes.Ldc_I4_1); il.Emit(OpCodes.Add); f.StInt("i");
            il.Emit(OpCodes.Br, top);
            il.MarkLabel(done);
            f.Ld("sum"); f.Complete();
            f.Finish();
        }
        // TryFinally(task): try { r = await task } finally { FinallyCount++ }; r
        {
            var f = new FrameBuilder(mod, gen, "TryFinally", new[] { "task" }, new[] { "r" }); entries["TryFinally"] = f.Entry;
            var il = f.IL; var preTry = il.DefineLabel(); var after = il.DefineLabel();
            f.Dispatch((1, preTry));                       // 外层：跳到 try 入口前
            il.MarkLabel(preTry);
            il.BeginExceptionBlock();
            f.Dispatch(1);                                 // 内层：进入 try 后再分派到恢复点
            f.Ld("task"); f.Await(1); f.St("r");
            il.Emit(OpCodes.Leave, after);
            var skip = f.BeginGuardedFinally();
            var cnt = typeof(RT).GetField("FinallyCount");
            il.Emit(OpCodes.Ldsfld, cnt); il.Emit(OpCodes.Ldc_I4_1); il.Emit(OpCodes.Add); il.Emit(OpCodes.Stsfld, cnt);
            il.MarkLabel(skip);
            il.EndExceptionBlock();
            il.MarkLabel(after);
            f.Ld("r"); f.Complete();
            f.Finish();
        }
        // TryCatch(task): try { r = await task } catch (Exception e) { r = Message(e) }; r
        {
            var f = new FrameBuilder(mod, gen, "TryCatch", new[] { "task" }, new[] { "r" }); entries["TryCatch"] = f.Entry;
            var il = f.IL; var preTry = il.DefineLabel(); var after = il.DefineLabel();
            f.Dispatch((1, preTry));
            il.MarkLabel(preTry);
            il.BeginExceptionBlock();
            f.Dispatch(1);
            f.Ld("task"); f.Await(1); f.St("r");
            il.Emit(OpCodes.Leave, after);
            il.BeginCatchBlock(typeof(Exception));
            f.Call("Message"); f.St("r");
            il.Emit(OpCodes.Leave, after);
            il.EndExceptionBlock();
            il.MarkLabel(after);
            f.Ld("r"); f.Complete();
            f.Finish();
        }
        // Nested(task) = await Echo(task)
        {
            var f = new FrameBuilder(mod, gen, "Nested", new[] { "task" }, new string[0]); entries["Nested"] = f.Entry;
            f.Dispatch(1);
            f.Ld("task"); f.IL.Emit(OpCodes.Call, Entry("Echo")); f.Await(1); f.Complete();
            f.Finish();
        }
        // Recurse(n): if n==0 { await Yield(); 0 } else { 1 + await Recurse(n-1) }
        {
            var f = new FrameBuilder(mod, gen, "Recurse", new[] { "n" }, new string[0]); entries["Recurse"] = f.Entry;
            var il = f.IL; var notZero = il.DefineLabel();
            f.Dispatch(1, 2);
            f.LdInt("n"); il.Emit(OpCodes.Brtrue, notZero);
            f.Call("Yield"); f.Await(1); il.Emit(OpCodes.Pop);
            il.Emit(OpCodes.Ldc_I4_0); il.Emit(OpCodes.Box, typeof(int)); f.Complete();
            il.MarkLabel(notZero);
            f.LdInt("n"); il.Emit(OpCodes.Ldc_I4_1); il.Emit(OpCodes.Sub); il.Emit(OpCodes.Box, typeof(int));
            il.Emit(OpCodes.Call, Entry("Recurse")); f.Await(2);
            il.Emit(OpCodes.Unbox_Any, typeof(int)); il.Emit(OpCodes.Ldc_I4_1); il.Emit(OpCodes.Add); il.Emit(OpCodes.Box, typeof(int)); f.Complete();
            f.Finish();
        }
        // SyncRecurse(n): if n==0 { NoteStack(); 0 } else { 1 + await SyncRecurse(n-1) }   —— 全程同步完成，看栈深
        {
            var f = new FrameBuilder(mod, gen, "SyncRecurse", new[] { "n" }, new string[0]); entries["SyncRecurse"] = f.Entry;
            var il = f.IL; var notZero = il.DefineLabel();
            f.Dispatch(1);
            f.LdInt("n"); il.Emit(OpCodes.Brtrue, notZero);
            f.Call("NoteStack"); il.Emit(OpCodes.Pop);
            il.Emit(OpCodes.Ldc_I4_0); il.Emit(OpCodes.Box, typeof(int)); f.Complete();
            il.MarkLabel(notZero);
            f.LdInt("n"); il.Emit(OpCodes.Ldc_I4_1); il.Emit(OpCodes.Sub); il.Emit(OpCodes.Box, typeof(int));
            il.Emit(OpCodes.Call, Entry("SyncRecurse")); f.Await(1);
            il.Emit(OpCodes.Unbox_Any, typeof(int)); il.Emit(OpCodes.Ldc_I4_1); il.Emit(OpCodes.Add); il.Emit(OpCodes.Box, typeof(int)); f.Complete();
            f.Finish();
        }
        // Context(): a = (Param.Value, ThreadParam); await Yield(); Pair(a, (…))
        {
            var f = new FrameBuilder(mod, gen, "Context", new string[0], new[] { "a" }); entries["Context"] = f.Entry;
            var il = f.IL;
            var param = typeof(RT).GetField("Param"); var getValue = typeof(AsyncLocal<object>).GetProperty("Value").GetGetMethod(); var tp = typeof(RT).GetField("ThreadParam");
            void Snapshot() { il.Emit(OpCodes.Ldsfld, param); il.Emit(OpCodes.Callvirt, getValue); il.Emit(OpCodes.Ldsfld, tp); f.Call("Pair"); }
            f.Dispatch(1);
            Snapshot(); f.St("a");
            f.Call("Yield"); f.Await(1); il.Emit(OpCodes.Pop);
            f.Ld("a"); Snapshot(); f.Call("Pair"); f.Complete();
            f.Finish();
        }
        // Tid(): a = Tid(); await Yield(); Pair(a, Tid())   /  TidFast(task): 同上但等已完成的 task
        {
            var f = new FrameBuilder(mod, gen, "Tid", new string[0], new[] { "a" }); entries["Tid"] = f.Entry;
            f.Dispatch(1);
            f.Call("Tid"); f.St("a"); f.Call("Yield"); f.Await(1); f.IL.Emit(OpCodes.Pop);
            f.Ld("a"); f.Call("Tid"); f.Call("Pair"); f.Complete();
            f.Finish();
        }
        {
            var f = new FrameBuilder(mod, gen, "TidFast", new[] { "task" }, new[] { "a" }); entries["TidFast"] = f.Entry;
            f.Dispatch(1);
            f.Call("Tid"); f.St("a"); f.Ld("task"); f.Await(1); f.IL.Emit(OpCodes.Pop);
            f.Ld("a"); f.Call("Tid"); f.Call("Pair"); f.Complete();
            f.Finish();
        }
        // 闭包：class Clo : Procedure { captured; Invoke1(a) => new BodyFrame(captured, a).Start() }
        {
            var f = new FrameBuilder(mod, gen, "Body", new[] { "captured", "a" }, new string[0]); entries["Body"] = f.Entry;
            f.Dispatch(1);
            f.Ld("a"); f.Await(1); f.IL.Emit(OpCodes.Pop);
            f.Ld("captured"); f.Complete();
            f.Finish();
            var clo = mod.DefineType("Clo", TypeAttributes.Public, typeof(Procedure));
            var captured = clo.DefineField("captured", typeof(object), FieldAttributes.Public);
            var ctor = clo.DefineConstructor(MethodAttributes.Public, CallingConventions.Standard, new[] { typeof(object) });
            var il = ctor.GetILGenerator();
            il.Emit(OpCodes.Ldarg_0); il.Emit(OpCodes.Call, typeof(Procedure).GetConstructor(BindingFlags.NonPublic | BindingFlags.Instance, Type.EmptyTypes));
            il.Emit(OpCodes.Ldarg_0); il.Emit(OpCodes.Ldarg_1); il.Emit(OpCodes.Stfld, captured); il.Emit(OpCodes.Ret);
            var inv = clo.DefineMethod("Invoke1", MethodAttributes.Public | MethodAttributes.Virtual, typeof(object), new[] { typeof(object) });
            il = inv.GetILGenerator();
            il.Emit(OpCodes.Ldarg_0); il.Emit(OpCodes.Ldfld, captured); il.Emit(OpCodes.Ldarg_1); il.Emit(OpCodes.Call, Entry("Body")); il.Emit(OpCodes.Ret);
            clo.CreateType();
        }
        return gen.CreateType();
    }

    static Type gen;
    static Task<object> Call(string name, params object[] args) => (Task<object>)gen.GetMethod(name).Invoke(null, args);
    static void Check(string name, bool ok, string detail) => Console.WriteLine($"{(ok ? "PASS" : "FAIL")}  {name,-12} {detail}");

    static void RunTest(string test)
    {
        switch (test)
        {
            case "fast":
            {
                var t = Call("Echo", RT.Done(42));
                var tid = Call("TidFast", RT.Done(1)).Result;
                Check(test, t.IsCompletedSuccessfully && (int)t.Result == 42, $"completed synchronously = {t.IsCompletedSuccessfully}, result {t.Result}, threads {tid} (main {Environment.CurrentManagedThreadId})");
                break;
            }
            case "suspend":
            {
                var t = Call("Echo", RT.Delay(50));
                bool pending = !t.IsCompleted;
                var r = t.Result;
                var tid = Call("Tid").Result;
                Check(test, pending && (int)r == 50, $"pending after call = {pending}, result {r}, threads before/after await {tid}");
                break;
            }
            case "loop":
            {
                var r = (int)Call("Loop", 1000).Result;
                Check(test, r == 499500, $"1000 awaits in a loop, sum {r}");
                break;
            }
            case "tryfinally":
            {
                RT.FinallyCount = 0;
                var r1 = Call("TryFinally", RT.Delay(20)).Result;
                var r0 = Call("TryFinally", RT.Done(5)).Result;
                string err = null;
                try { Call("TryFinally", RT.Fail("boom")).Wait(); } catch (AggregateException e) { err = RT.Message(e.InnerException).ToString(); }
                var r2 = Call("TryCatch", RT.Fail("caught")).Result;
                var r3 = Call("TryCatch", RT.Delay(20)).Result;
                Check(test, RT.FinallyCount == 3 && (int)r1 == 20 && (int)r0 == 5 && err == "InvalidOperationException: boom" && (string)r2 == "InvalidOperationException: caught" && (int)r3 == 20,
                      $"finally ran {RT.FinallyCount}/3 (suspended, sync, throw), throw -> {err}, catch -> {r2}, catch no-throw -> {r3}");
                break;
            }
            case "exception":
            {
                var t = Call("Echo", RT.Fail("direct"));
                var ex = t.Exception?.InnerException;
                var tf = Call("Echo", Task.Run<object>(async () => { await Task.Delay(10); throw new InvalidOperationException("late"); }));
                Exception late = null; try { tf.Wait(); } catch (AggregateException e) { late = e.InnerException; }
                Check(test, ex is InvalidOperationException { Message: "direct" } && late is InvalidOperationException { Message: "late" },
                      $"faulted task -> {RT.Message(ex)}, after suspension -> {RT.Message(late)}");
                break;
            }
            case "nested":
            {
                var sync = Call("Nested", RT.Done(7));
                var r = Call("Nested", RT.Delay(20)).Result;
                Check(test, sync.IsCompletedSuccessfully && (int)sync.Result == 7 && (int)r == 20, $"sync path completed = {sync.IsCompletedSuccessfully}, suspended result {r}");
                break;
            }
            case "closure":
            {
                var p = (Procedure)Activator.CreateInstance(gen.Assembly.GetType("Clo"), "captured-value");
                var t = (Task<object>)p.Invoke1(RT.Delay(20));
                Check(test, (string)t.Result == "captured-value", $"Invoke1 returned {t.GetType().Name}, result {t.Result}");
                break;
            }
            case "context":
            {
                RT.Param.Value = "async-local"; RT.ThreadParam = "thread-static";
                var r = (string)Call("Context").Result;
                RT.Param.Value = null; RT.ThreadParam = null;
                Check(test, r == "((async-local, thread-static), (async-local, ))", $"(before, after) = {r}");
                break;
            }
            case "deep":
            {
                foreach (var depth in new[] { 10_000, 100_000, 1_000_000 })
                {
                    object r = null; Exception ex = null;
                    var th = new Thread(() => { try { r = Call("Recurse", depth).Result; } catch (Exception e) { ex = e; } }, 256 * 1024 * 1024);
                    var sw = Stopwatch.StartNew(); th.Start(); th.Join();
                    Check(test, ex == null && r != null && (int)r == depth, $"depth {depth}: {(ex == null ? $"result {r}" : ex.GetType().Name)}, {sw.ElapsedMilliseconds} ms (descent on 256MB stack, resumption on pool threads)");
                }
                break;
            }
            case "stack":
            {
                RT.MaxStackDepth = 0;
                var r = Call("SyncRecurse", 1000).Result;
                Check(test, (int)r == 1000, $"1000-deep all-sync recursion: max managed stack frames {RT.MaxStackDepth} (~{RT.MaxStackDepth / 1000.0:F1} per level)");
                break;
            }
            case "concurrency":
            {
                var sw = Stopwatch.StartNew();
                var all = Task.WhenAll(Enumerable.Range(0, 100).Select(_ => Call("Echo", RT.Delay(300))));
                var sum = all.Result.Sum(o => (int)o);
                Check(test, sw.ElapsedMilliseconds < 1000 && sum == 30000, $"100 x 300ms awaits took {sw.ElapsedMilliseconds} ms");
                break;
            }
            case "bench":
            {
                var echo = gen.GetMethod("Echo").CreateDelegate<Func<object, Task<object>>>();
                var nested = gen.GetMethod("Nested").CreateDelegate<Func<object, Task<object>>>();
                var done = RT.Done(1);
                for (int i = 0; i < 100_000; i++) { echo(done); nested(done); }
                const int N = 10_000_000;
                var sw = Stopwatch.StartNew(); for (int i = 0; i < N; i++) echo(done); var a = sw.Elapsed.TotalNanoseconds / N;
                sw.Restart(); for (int i = 0; i < N; i++) nested(done); var b = sw.Elapsed.TotalNanoseconds / N;
                sw.Restart(); for (int i = 0; i < N; i++) RT.Identity(done); var c = sw.Elapsed.TotalNanoseconds / N;
                sw.Restart(); for (int i = 0; i < N; i++) RT.DelayAsync0(done); var d = sw.Elapsed.TotalNanoseconds / N;
                Check(test, true, $"sync path per call: frame Echo {a:F1} ns, frame Nested (2 levels) {b:F1} ns, plain call {c:F1} ns, C# async/await {d:F1} ns");
                break;
            }
            default: Console.WriteLine("unknown test " + test); break;
        }
    }

    static readonly string[] All = { "fast", "suspend", "loop", "tryfinally", "exception", "nested", "closure", "context", "deep", "stack", "concurrency", "bench" };

    public static int Main(string[] args)
    {
        Console.WriteLine($".NET {Environment.Version}");
        var tests = args.Length == 0 || args[0] == "all" ? All : args;
        var dll = Path.Combine(AppContext.BaseDirectory, "Spike.Gen.dll");
        if (tests[0] == "save")
        {
            var ab = new PersistedAssemblyBuilder(new AssemblyName("Spike.Gen"), typeof(object).Assembly);
            BuildGen(ab.DefineDynamicModule("Spike.Gen"));
            ab.Save(dll);
            Console.WriteLine("saved " + dll);
            return 0;
        }
        if (tests[0] == "load")
        {
            gen = Assembly.LoadFrom(dll).GetType("Gen");
            Console.WriteLine("loaded " + dll);
            tests = tests.Skip(1).DefaultIfEmpty("all").ToArray();
            if (tests[0] == "all") tests = All;
        }
        else
        {
            var ab = AssemblyBuilder.DefineDynamicAssembly(new AssemblyName("Spike.Gen"), AssemblyBuilderAccess.RunAndCollect);
            gen = BuildGen(ab.DefineDynamicModule("Spike.Gen"));
        }
        foreach (var t in tests)
        {
            try { RunTest(t); }
            catch (Exception e)
            {
                while (e is TargetInvocationException or AggregateException && e.InnerException != null) e = e.InnerException;
                Check(t, false, "threw " + RT.Message(e));
            }
        }
        return 0;
    }
}

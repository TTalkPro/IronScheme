// iron-048：验证 .NET 10 的 Runtime Async 能否当 async-lambda 的后端
//   fast        —— 等待已完成的 Task 时同步返回、不换线程
//   suspend     —— 等待未完成的 Task 时挂起，恢复后结果正确
//   loop        —— 循环体内 await
//   tryfinally  —— try/finally、try/catch 跨 await
//   exception   —— 被等待的 Task 出错时异常原样传到 async 方法内外
//   nested      —— async 方法调用 async 方法
//   closure     —— Procedure 子类的 Invoke 包装一个 async 静态方法
//   context     —— AsyncLocal 与 [ThreadStatic] 跨 await 的行为
//   deep        —— 深递归，每层都挂起，恢复时是否栈溢出
//   concurrency —— 100 个各等 300 ms 的任务并发总耗时
//   tail        —— async 方法体内能否用 tail. 前缀
//   bench       —— 同步完成路径上每次 await 的开销
//   save / load —— PersistedAssemblyBuilder 保存后另行加载运行
// 用法：DOTNET_RuntimeAsync=1 dotnet run -c Release -- all
using System.Diagnostics;
using System.Reflection;
using System.Reflection.Emit;
using System.Runtime.CompilerServices;

public abstract class Procedure
{
    public virtual object Invoke1(object a) => throw new InvalidOperationException("arity 1");
}

public static class RT
{
    public static readonly AsyncLocal<object> Param = new();
    [ThreadStatic] public static object ThreadParam;
    public static int FinallyCount;

    public static object Tid() => Environment.CurrentManagedThreadId;
    public static object Done(object v) => Task.FromResult(v);
    public static object Fail(object msg) => Task.FromException<object>(new InvalidOperationException((string)msg));
    public static object Delay(object ms) => DelayAsync((int)ms);
    static async Task<object> DelayAsync(int ms) { await Task.Delay(ms).ConfigureAwait(false); return ms; }
    // 一定会挂起：在另一个池线程上完成
    public static object Yield()
    {
        var tcs = new TaskCompletionSource<object>(TaskCreationOptions.RunContinuationsAsynchronously);
        ThreadPool.UnsafeQueueUserWorkItem(_ => tcs.SetResult(null), null);
        return tcs.Task;
    }
    public static object Identity(object o) => o;
    public static async Task<object> DelayAsync0(object t) => await (Task<object>)t;
    public static object Message(Exception e) => e.GetType().Name + ": " + e.Message;
    public static object Pair(object a, object b) => (a, b).ToString();
}

public static class Program
{
    static readonly MethodInfo AwaitObj = typeof(AsyncHelpers).GetMethods()
        .Single(m => m.Name == "Await" && m.IsGenericMethodDefinition
                  && m.GetParameters()[0].ParameterType.GetGenericTypeDefinition() == typeof(Task<>))
        .MakeGenericMethod(typeof(object));
    static MethodInfo RTM(string n) => typeof(RT).GetMethod(n);
    static readonly Type TaskObj = typeof(Task<object>);
    static MethodBuilder echoMb;

    static MethodBuilder AsyncMethod(TypeBuilder tb, string name, int arity)
    {
        var mb = tb.DefineMethod(name, MethodAttributes.Public | MethodAttributes.Static, TaskObj,
                                 Enumerable.Repeat(typeof(object), arity).ToArray());
        mb.SetImplementationFlags(MethodImplAttributes.Async);
        return mb;
    }

    // 发射的 IL 里，await = castclass Task<object>; call AsyncHelpers.Await<object>
    static void EmitAwait(ILGenerator il)
    {
        il.Emit(OpCodes.Castclass, TaskObj);
        il.Emit(OpCodes.Call, AwaitObj);
    }

    public static Type BuildGen(ModuleBuilder mod, bool withTail)
    {
        var tb = mod.DefineType("Gen", TypeAttributes.Public | TypeAttributes.Abstract | TypeAttributes.Sealed);

        // Echo(task) = await task
        {
            var echoMb0 = AsyncMethod(tb, "Echo", 1); echoMb = echoMb0; var il = echoMb0.GetILGenerator();
            il.Emit(OpCodes.Ldarg_0); EmitAwait(il); il.Emit(OpCodes.Ret);
        }
        // Loop(n): i=0,sum=0; while i<n { await Yield(); sum+=i; i++ } ; return sum
        {
            var il = AsyncMethod(tb, "Loop", 1).GetILGenerator();
            var i = il.DeclareLocal(typeof(int)); var sum = il.DeclareLocal(typeof(int));
            var top = il.DefineLabel(); var end = il.DefineLabel();
            il.Emit(OpCodes.Ldc_I4_0); il.Emit(OpCodes.Stloc, i);
            il.Emit(OpCodes.Ldc_I4_0); il.Emit(OpCodes.Stloc, sum);
            il.MarkLabel(top);
            il.Emit(OpCodes.Ldloc, i); il.Emit(OpCodes.Ldarg_0); il.Emit(OpCodes.Unbox_Any, typeof(int)); il.Emit(OpCodes.Bge, end);
            il.Emit(OpCodes.Call, RTM("Yield")); EmitAwait(il); il.Emit(OpCodes.Pop);
            il.Emit(OpCodes.Ldloc, sum); il.Emit(OpCodes.Ldloc, i); il.Emit(OpCodes.Add); il.Emit(OpCodes.Stloc, sum);
            il.Emit(OpCodes.Ldloc, i); il.Emit(OpCodes.Ldc_I4_1); il.Emit(OpCodes.Add); il.Emit(OpCodes.Stloc, i);
            il.Emit(OpCodes.Br, top);
            il.MarkLabel(end);
            il.Emit(OpCodes.Ldloc, sum); il.Emit(OpCodes.Box, typeof(int)); il.Emit(OpCodes.Ret);
        }
        // TryFinally(task): try { r = await task } finally { FinallyCount++ } ; return r
        {
            var il = AsyncMethod(tb, "TryFinally", 1).GetILGenerator();
            var r = il.DeclareLocal(typeof(object));
            var end = il.DefineLabel();
            il.BeginExceptionBlock();
            il.Emit(OpCodes.Ldarg_0); EmitAwait(il); il.Emit(OpCodes.Stloc, r);
            il.Emit(OpCodes.Leave, end);
            il.BeginFinallyBlock();
            var f = typeof(RT).GetField("FinallyCount");
            il.Emit(OpCodes.Ldsfld, f); il.Emit(OpCodes.Ldc_I4_1); il.Emit(OpCodes.Add); il.Emit(OpCodes.Stsfld, f);
            il.EndExceptionBlock();
            il.MarkLabel(end);
            il.Emit(OpCodes.Ldloc, r); il.Emit(OpCodes.Ret);
        }
        // TryCatch(task): try { r = await task } catch (Exception e) { r = Message(e) } ; return r
        {
            var il = AsyncMethod(tb, "TryCatch", 1).GetILGenerator();
            var r = il.DeclareLocal(typeof(object));
            var end = il.DefineLabel();
            il.BeginExceptionBlock();
            il.Emit(OpCodes.Ldarg_0); EmitAwait(il); il.Emit(OpCodes.Stloc, r);
            il.Emit(OpCodes.Leave, end);
            il.BeginCatchBlock(typeof(Exception));
            il.Emit(OpCodes.Call, RTM("Message")); il.Emit(OpCodes.Stloc, r);
            il.Emit(OpCodes.Leave, end);
            il.EndExceptionBlock();
            il.MarkLabel(end);
            il.Emit(OpCodes.Ldloc, r); il.Emit(OpCodes.Ret);
        }
        // Nested(task) = await Echo(task)   —— async 调 async
        {
            
            var il = AsyncMethod(tb, "Nested", 1).GetILGenerator();
            il.Emit(OpCodes.Ldarg_0); il.Emit(OpCodes.Call, echoMb); il.Emit(OpCodes.Call, AwaitObj); il.Emit(OpCodes.Ret);
        }
        // Recurse(n): if n==0 { await Yield(); return 0 } else { return 1 + await Recurse(n-1) }
        {
            var mb = AsyncMethod(tb, "Recurse", 1);
            var il = mb.GetILGenerator();
            var notZero = il.DefineLabel();
            il.Emit(OpCodes.Ldarg_0); il.Emit(OpCodes.Unbox_Any, typeof(int)); il.Emit(OpCodes.Brtrue, notZero);
            il.Emit(OpCodes.Call, RTM("Yield")); EmitAwait(il); il.Emit(OpCodes.Pop);
            il.Emit(OpCodes.Ldc_I4_0); il.Emit(OpCodes.Box, typeof(int)); il.Emit(OpCodes.Ret);
            il.MarkLabel(notZero);
            il.Emit(OpCodes.Ldarg_0); il.Emit(OpCodes.Unbox_Any, typeof(int)); il.Emit(OpCodes.Ldc_I4_1); il.Emit(OpCodes.Sub);
            il.Emit(OpCodes.Box, typeof(int)); il.Emit(OpCodes.Call, mb); il.Emit(OpCodes.Call, AwaitObj);
            il.Emit(OpCodes.Unbox_Any, typeof(int)); il.Emit(OpCodes.Ldc_I4_1); il.Emit(OpCodes.Add);
            il.Emit(OpCodes.Box, typeof(int)); il.Emit(OpCodes.Ret);
        }
        // Context(): a = (Param.Value, ThreadParam); await Yield(); b = ...; return Pair(a, b)
        {
            var il = AsyncMethod(tb, "Context", 0).GetILGenerator();
            var a = il.DeclareLocal(typeof(object));
            var getParam = typeof(RT).GetField("Param"); var getValue = typeof(AsyncLocal<object>).GetProperty("Value").GetGetMethod();
            var tp = typeof(RT).GetField("ThreadParam");
            void Snapshot() { il.Emit(OpCodes.Ldsfld, getParam); il.Emit(OpCodes.Callvirt, getValue); il.Emit(OpCodes.Ldsfld, tp); il.Emit(OpCodes.Call, RTM("Pair")); }
            Snapshot(); il.Emit(OpCodes.Stloc, a);
            il.Emit(OpCodes.Call, RTM("Yield")); EmitAwait(il); il.Emit(OpCodes.Pop);
            il.Emit(OpCodes.Ldloc, a); Snapshot(); il.Emit(OpCodes.Call, RTM("Pair")); il.Emit(OpCodes.Ret);
        }
        // Tid(): a = Tid(); await Yield(); return Pair(a, Tid())
        {
            var il = AsyncMethod(tb, "Tid", 0).GetILGenerator();
            var a = il.DeclareLocal(typeof(object));
            il.Emit(OpCodes.Call, RTM("Tid")); il.Emit(OpCodes.Stloc, a);
            il.Emit(OpCodes.Call, RTM("Yield")); EmitAwait(il); il.Emit(OpCodes.Pop);
            il.Emit(OpCodes.Ldloc, a); il.Emit(OpCodes.Call, RTM("Tid")); il.Emit(OpCodes.Call, RTM("Pair")); il.Emit(OpCodes.Ret);
        }
        // TidFast(task): 同上，但等待的是已完成的 task
        {
            var il = AsyncMethod(tb, "TidFast", 1).GetILGenerator();
            var a = il.DeclareLocal(typeof(object));
            il.Emit(OpCodes.Call, RTM("Tid")); il.Emit(OpCodes.Stloc, a);
            il.Emit(OpCodes.Ldarg_0); EmitAwait(il); il.Emit(OpCodes.Pop);
            il.Emit(OpCodes.Ldloc, a); il.Emit(OpCodes.Call, RTM("Tid")); il.Emit(OpCodes.Call, RTM("Pair")); il.Emit(OpCodes.Ret);
        }
        if (withTail)
        {
            // Tail(task): await task; tail. call Identity(task); ret
            var il = AsyncMethod(tb, "Tail", 1).GetILGenerator();
            il.Emit(OpCodes.Ldarg_0); EmitAwait(il); il.Emit(OpCodes.Pop);
            il.Emit(OpCodes.Ldarg_0); il.Emit(OpCodes.Tailcall); il.Emit(OpCodes.Call, RTM("Identity")); il.Emit(OpCodes.Ret);
        }

        // 闭包：class Clo : Procedure { object captured; Invoke1(a) => Body(captured, a) }，Body 是 async 静态方法
        var clo = mod.DefineType("Clo", TypeAttributes.Public, typeof(Procedure));
        var captured = clo.DefineField("captured", typeof(object), FieldAttributes.Public);
        {
            var ctor = clo.DefineConstructor(MethodAttributes.Public, CallingConventions.Standard, new[] { typeof(object) });
            var il = ctor.GetILGenerator();
            il.Emit(OpCodes.Ldarg_0); il.Emit(OpCodes.Call, typeof(Procedure).GetConstructor(BindingFlags.NonPublic | BindingFlags.Instance, Type.EmptyTypes));
            il.Emit(OpCodes.Ldarg_0); il.Emit(OpCodes.Ldarg_1); il.Emit(OpCodes.Stfld, captured); il.Emit(OpCodes.Ret);
        }
        var body = AsyncMethod(clo, "Body", 2);   // Body(captured, a): await a; return captured
        {
            var il = body.GetILGenerator();
            il.Emit(OpCodes.Ldarg_1); EmitAwait(il); il.Emit(OpCodes.Pop);
            il.Emit(OpCodes.Ldarg_0); il.Emit(OpCodes.Ret);
        }
        {
            var inv = clo.DefineMethod("Invoke1", MethodAttributes.Public | MethodAttributes.Virtual, typeof(object), new[] { typeof(object) });
            var il = inv.GetILGenerator();
            il.Emit(OpCodes.Ldarg_0); il.Emit(OpCodes.Ldfld, captured); il.Emit(OpCodes.Ldarg_1); il.Emit(OpCodes.Call, body); il.Emit(OpCodes.Ret);
        }
        clo.CreateType();
        return tb.CreateType();
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
                string err = null;
                try { Call("TryFinally", RT.Fail("boom")).Wait(); } catch (AggregateException e) { err = RT.Message(e.InnerException).ToString(); }
                var r2 = Call("TryCatch", RT.Fail("caught")).Result;
                var r3 = Call("TryCatch", RT.Delay(20)).Result;
                Check(test, RT.FinallyCount == 2 && (int)r1 == 20 && err == "InvalidOperationException: boom" && (string)r2 == "InvalidOperationException: caught" && (int)r3 == 20,
                      $"finally ran {RT.FinallyCount}/2, finally+throw -> {err}, catch -> {r2}, catch no-throw -> {r3}");
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
            case "concurrency":
            {
                var sw = Stopwatch.StartNew();
                var all = Task.WhenAll(Enumerable.Range(0, 100).Select(_ => Call("Echo", RT.Delay(300))));
                var sum = all.Result.Sum(o => (int)o);
                Check(test, sw.ElapsedMilliseconds < 1000 && sum == 30000, $"100 x 300ms awaits took {sw.ElapsedMilliseconds} ms");
                break;
            }
            case "tail":
            {
                try { var r = Call("Tail", RT.Delay(10)).Result; Check(test, true, $"tail. inside async method accepted, result {r}"); }
                catch (Exception e) { Check(test, false, $"tail. inside async method rejected: {RT.Message(e is TargetInvocationException ti ? ti.InnerException : e)}"); }
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
                Check(test, true, $"sync path per call: async Echo {a:F1} ns, async Nested (2 levels) {b:F1} ns, plain call {c:F1} ns, C# async/await {d:F1} ns");
                break;
            }
            default: Console.WriteLine("unknown test " + test); break;
        }
    }

    static readonly string[] All = { "fast", "suspend", "loop", "tryfinally", "exception", "nested", "closure", "context", "deep", "concurrency", "tail", "bench" };

    public static int Main(string[] args)
    {
        Console.WriteLine($".NET {Environment.Version}, RuntimeFeature.IsSupported(\"RuntimeAsync\") = {RuntimeFeature.IsSupported("RuntimeAsync")}, DOTNET_RuntimeAsync={Environment.GetEnvironmentVariable("DOTNET_RuntimeAsync")}");
        var tests = args.Length == 0 || args[0] == "all" ? All : args;
        var dll = Path.Combine(AppContext.BaseDirectory, "Spike.Gen.dll");
        if (tests[0] == "save")
        {
            var ab = new PersistedAssemblyBuilder(new AssemblyName("Spike.Gen"), typeof(object).Assembly);
            BuildGen(ab.DefineDynamicModule("Spike.Gen"), withTail: false);
            ab.Save(dll);
            Console.WriteLine("saved " + dll);
            return 0;
        }
        if (tests[0] == "load")
        {
            gen = Assembly.LoadFrom(dll).GetType("Gen");
            Console.WriteLine("loaded " + dll + ", Echo impl flags = " + gen.GetMethod("Echo").GetMethodImplementationFlags());
            tests = tests.Skip(1).DefaultIfEmpty("all").ToArray();
            if (tests[0] == "all") tests = All.Where(t => t != "tail").ToArray();
        }
        else
        {
            var ab = AssemblyBuilder.DefineDynamicAssembly(new AssemblyName("Spike.Gen"), AssemblyBuilderAccess.RunAndCollect);
            gen = BuildGen(ab.DefineDynamicModule("Spike.Gen"), withTail: true);
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

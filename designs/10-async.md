# 10 异步：`async-lambda` 与 `await`

> 目标：用 C# 那样的顺序写法做不占线程的异步 IO。方案由两个 spike 决定：[iron-048](../tasks/iron-048-spike-runtime-async.md)（Runtime Async，可行但是实验特性，**不采用**）和 [iron-049](../tasks/iron-049-spike-async-frame.md)（编译器自己做 Roslyn 式状态机，只用公开 API，**采用**）。
> 决定按 **D<n>** 编号；实现任务见 §8。

## §0 事实（2026-10-09）

**Task 层面**（两个 spike 实测，.NET 10.0.12，Linux x64）
- 现有 `(ironscheme async)` 的 `await` 是 `GetAwaiter().GetResult()`：写法顺序，但在池线程上阻塞。100 个各等 300 ms 的任务要 30 s（线程池饥饿），改成状态机后 302 ms。
- 状态机方案每次 async 调用约 22 ns（含一个帧对象与一个 Task 的分配），await 本身零分配；首次挂起时 builder 再分配一个 `AsyncStateMachineBox`，之后复用。深递归每层挂起一百万层不溢出。
- 被等待的 Task 出错时，`GetResult()` 抛出原异常（不是 `AggregateException`）。`AsyncLocal` 跨 await 保留，线程局部数据丢失。
- `AsyncTaskMethodBuilder.Start` 在同步部分前后保存、恢复 `ExecutionContext`：async 方法内对 `AsyncLocal` 的修改**不会**流回调用方。
- ILVerify 对状态机形状全部通过；PersistedAssemblyBuilder 保存后加载正常。

**编译器现状**（[03](03-compiler.md) §4.1，`src/scheme/lib/ironscheme/compiler/`）
- 没有 ANF 和闭包转换 pass：`codegen.sls` 直接从 L3 树按上下文（value / effect / test / tail）生成栈式代码；lambda 在 codegen 里变成 `Procedure` 子类。变量存放由 `vars` 表决定：`(arg . i)`、`(local . i)`、`(field . 名字)`、`(self)`。
- 命名 let 与 `do` 是 letrec 绑定的 lambda，**各自是一个类**；循环是该 lambda 自己方法里的自尾调用（`starg` + `br`）。
- 只有 `$try/finally` 在当前方法里产生 IL try 区域。`call/cc` 是对 `Control.CallWithCurrentContinuation` 的静态调用，try/catch 在 C# 里。
- `dynamic-wind` 是过程 `(in) ($try/finally (proc) (out))`；`parameterize` 是宏（swap thunk + `dynamic-wind`）；`guard` 是宏（`call/cc` + `with-exception-handler` + `call-with-values`）；`with-exception-handler` 是对参数对象 `*current-exception-handlers*` 的 `parameterize`。⇒ 这些形式的体**都是嵌套 lambda**。
- `operands!` 已有 lift-try：后面的操作数含 `try` 时，先把全部操作数存进临时变量。
- 参数对象（`make-parameter`，`boot/expander/compat.sls`）用 `Thread.AllocateDataSlot` 存值：线程局部，不随 `ExecutionContext` 流动。`IronScheme.Core` 没有任何 `[ThreadStatic]`。
- 互操作：`Interop.ConvertFrom` 对 `Task<T>` 原样放行；发射器静态解析的调用（`EmitInterop.ConvertFrom`）对引用类型直接返回，不经过 `Interop.ConvertFrom`；`ToDelegate` 的返回值走 `ConvertTo(returnType)`。
- Lcil（[04](04-lcil-and-emitter.md)）：`(base …)`、`override`、任意嵌套的 `try` 且块内可显式 `leave`、所有 `OpCodes` 按名字可用（含 `switch`、`beq`、`ldflda`；iron-049 说"没有 `switch`"不对）。普通类型引用不支持 `Name<A>` 语法，泛型实例要写反射名（``System.Threading.Tasks.Task`1[System.Object]``）。

## §1 语言表面

**D1 形式**：
```scheme
(async-lambda fmls body ...)                 ; 求值得到过程；调用它返回 Task<object>
(define-async (name . fmls) body ...)        ; = (define name (async-lambda fmls body ...))
(await e)                                    ; e 求值为 Task；挂起直到完成，值为结果
```
`fmls` 与 `lambda` 相同（含剩余参数）。没有 `async-case-lambda`；需要多子句时在外面套 `case-lambda` 再调 async 过程。返回值永远是 `Task<object>`：体的值（多值则是 `MultipleValues` 对象）为结果；体抛出的异常（Scheme 条件与 .NET 异常都一样）让 Task 失败，异常原样保存。

**D2 `await` 的位置**：只能出现在 `async-lambda` 的体里，而且**不能跨过普通 lambda**——与 C# 相同（`for-each` 的回调里不能 await）。例外是编译器会内联进帧的那些形式（§3 D9、D10）：命名 let / `do` 循环、`dynamic-wind`、`parameterize`、`with-exception-handler`、`guard` 的体、`call/cc` 的接收者、立即调用的 lambda。违反时**编译期**报错 "await outside async-lambda"。

**D3 `await` 接受什么**：`Task<object>`（这是 CLR 后端的表示；可移植的契约只是"task 对象"，见 [11](11-portability.md) §3）；其他 `Task<T>` 由互操作转换（§2 D6）；非泛型 `Task` 的结果是未指定值。不接受任意 awaitable（没有 duck typing）；`ValueTask` 以后再说。给非 Task 的值报 `&assertion`。

**D4 线程与上下文**：恢复可能在另一个线程上。与 C# 默认一致：`await` 捕获 `SynchronizationContext`（有的话回到它，没有就在池线程继续）。Scheme 侧不提供 `ConfigureAwait(false)`；要绕开上下文，等的 Task 自己 `ConfigureAwait` 不行（返回的不是 Task），所以提供 `task-run` 把工作扔到线程池。

**D5 库 `(ironscheme async)`**：全部重写，导出
`async-lambda` `define-async` `await`（核心形式的再导出）；
`task?` `task-completed?` `task-faulted?` `task-result`（阻塞等待，解包异常）`task-from-result` `task-from-exception` `task-delay` `task-yield` `task-run`（在线程池上跑 thunk）`task-then`（回调式续接）`task-when-all` `task-when-any`；
`make-task-source` `task-source-task` `task-source-set-result!` `task-source-set-exception!`（TCS，从回调式 API 造 Task）；
`for-each-async` `map-async`（顺序执行，内部是 `async-lambda` 加 `await`，供回调里不能 await 的场景）。
旧的 `start`、`started?`、`status` 删除（新 Task 都是已启动的）。这些过程用 C# 原语实现（`Tasks.cs`，iron-050 已做，在 `(ironscheme core)` 里），不走 `clr-dynamic`。细节：`task-faulted?` 对失败与取消都为真；`task-then` 在 task 成功后以结果调用回调、回调返回 task 时展开、task 失败则不调回调；`task-when-all` / `task-when-any` 取**一个列表**，前者结果是结果列表，后者结果是最先完成的那个 task；`task-run` 的 thunk 返回 task 时展开（async-lambda 可直接传入）；`task-from-exception` 与 `task-source-set-exception!` 接受 .NET 异常或 Scheme 条件（后者包成 `SchemeException`）；`task-yield` 返回一个在线程池上完成的 task（它不会同步完成）。

## §2 运行时（`IronScheme.Core`）

**D6 `AsyncFrame` 基类**（形状见 iron-049 的 spike）：
```csharp
public abstract class AsyncFrame : IAsyncStateMachine
{
    AsyncTaskMethodBuilder<object> builder; TaskAwaiter<object> awaiter;
    public int state = -1;                      // -1 运行中；>= 0 挂起在恢复点 n；-2 已完成
    public abstract void MoveNext();
    public Task<object> Start();                // builder.Start(ref this); return builder.Task
    public bool Suspend(object task, int next); // 已完成返回 true；否则 state = next，登记恢复，返回 false
    public object Resume();                     // state = -1; return awaiter.GetResult()
    public void Complete(object v);             // state = -2; builder.SetResult(v)
    public void Fail(Exception e);              // state = -2; builder.SetException(e)
}
```
所有 `ref`、结构体、泛型操作都在这里；生成代码只做普通调用，Lcil 不需要新能力。`Suspend` 的参数检查（非 Task 报条件）也在这里。

**D7 参数对象改为 `AsyncLocal`**：`make-parameter` 的存储由 `Thread.AllocateDataSlot` 改为每个参数一个 `AsyncLocal<object>`（C# 原语 `$make-param-slot` / `$param-ref` / `$param-set!`）。于是 `parameterize` 的值、异常处理器栈 `*current-exception-handlers*`（它本身是参数）都随 `ExecutionContext` 跨 await 流动，恢复到另一个线程后 `raise` 仍能找到 `guard` 装的处理器。
偏离：async 体内直接赋值参数（`(p v)`）对调用方不可见（§0 的 `ExecutionContext` 规则）；`parameterize` 的动态范围不受影响。`make-parameter` 里"创建线程上的赋值同时更新一份回退值"的逻辑**保留**（搬进 C#）：没有自己值的上下文读到的是回退值——创建时的初始值与之后创建线程上的赋值。于是 async 体在第一个 await 之前（仍在调用线程上同步运行）若在参数的创建线程上赋值，和同步代码一样更新回退值；await 之后在池线程上的赋值只影响自己的上下文。iron-050 实测删掉它会坏掉宿主：启动时主线程上 `(current-library-collection …)`、库路径等用 `(p v)` 设置，Kestrel 的请求线程（缺省 `ExecutionContext`）读不到就无法 `eval`。
实现（iron-050，`Parameters.cs`）：槽是 `ParamSlot`，空表 `'()` 在运行时是 `null`、与 `AsyncLocal` 的"未设置"冲突，所以空表用哨兵存放，`(p '())` 不再被当成未设置（旧实现的一个小 bug）。处理器栈不再是参数对象，而是 C# 里单独的 `AsyncLocal`（`ExceptionHandlers`，原语 `$current-handlers` / `$set-current-handlers!`），`with-exception-handlers` 改为 `$try/finally` 保存恢复，不再经过 `parameterize`（少一层 `dynamic-wind` 和 swap 闭包，也让 §3 的 `lower-async` 少内联一种形式）；设为空表等于缺省表。

**D8 互操作里的 Task**：
- `Interop.ConvertFrom` 与 `EmitInterop.ConvertFrom`：返回值是 `Task<T>`（T ≠ object）时包成 `Task<object>`（C# 辅助 `Tasks.Box<T>(Task<T>)`，一个 `ContinueWith`，保留异常与取消）；非泛型 `Task` 包成结果为未指定值的 `Task<object>`。`Task<object>` 原样。
- `ToDelegate`：委托返回类型是 `Task<T>` 时，过程返回的 `Task<object>` 转成 `Task<T>`（`Tasks.Unbox<T>`）；返回 `Task` 时直接用。于是 Scheme 的 async 过程能当 `Func<Task<int>>` 传给 .NET。实现上这条放在 `Interop.ConvertTo` 里（目标类型是 Task 时走 `Tasks.ToTaskType`），所以 `clr-cast` 等也适用；过程返回的不是 task 而是普通值时包成已完成的 `Task<T>`，普通 lambda 也能当 `Func<Task<int>>` 用。
- 声明类型为 `object` 的返回值与字段值按运行时类型转换（与 `long` → fixnum 同一条规则），所以运行时拿到的任何 `Task<T>` 都会包成 `Task<object>`；C# 的 async `Task` 方法实际返回的 `Task<VoidTaskResult>` 按非泛型 `Task` 处理。
- `clr-call` 等的可选参数照旧不自动填充（`CancellationToken` 要显式传），这是互操作的既有规则，不在本设计改。

## §3 编译器

### 3.1 管线上的位置

| 步骤 | 改动 |
|---|---|
| 展开器 | 核心宏 `async-lambda`（`core.sls`，注册在 buildscript 的 `expander-system-macros`）；`define-async` 是普通宏。builders 产生 Lcore 形式 `(async-lambda fmls body)`；`await` 是导出的特殊原语（PrimGen `specials` 加 `await`，种类 `await`），Lcore 中写作 `(await e)` |
| `rewrite`（`internal.sls`） | 像 `lambda` 一样显式走 `async-lambda` 的体 |
| parse-core（`parse.sls`） | L0 新节点 `(async-lambda nm (x* …) (maybe x) body)`（单子句）与 `(await e)` |
| **`lower-async`（新 pass，L0 → L0）** | 只处理 `async-lambda` 的体：循环降级（D9）、内联（D10）、拆分（D11）、检查（D2）。不含 `async-lambda` 的单元直接跳过，普通代码的输出不变 |
| analyze … uncover-free | `async-lambda` 按 lambda 处理（赋值、捕获、自由变量）；新增节点 `await` `label` `jump` `escape-frame` 逐 pass 透传 |
| codegen | `async-lambda` → 过程类 + 帧类（D12）；帧的 `MoveNext` 用 async 方法上下文（D13） |

### 3.2 `lower-async`

**D9 局部循环降级**：async 体内 `letrec`/`letrec*` 绑定的 lambda `f`，若它的每个引用都是**参数个数相符的调用、且处于 `f` 自己的体或该 letrec 体的尾位置**，则 `f` 不再是 lambda：
```
(letrec ([f (lambda (x …) fbody)]) body)  ⇒  (label f (x …) body′ fbody′)
(f e …) 在尾位置                             ⇒  (jump f e …)
```
`body′` 先执行，其中对 `f` 的尾调用 `jump` 到 `fbody′`。命名 let 与 `do` 都是这个形状。codegen 把 `jump` 编成"求值实参到临时变量、写入 `f` 的参数字段、`br L_f`"，`label` 的值就是 `fbody′` 正常结束时的值。只在 async 体内做：普通代码保持现状（命名 let 是静态单例类，自尾调用已是循环），全局推广属于 iron-034 的优化。
不满足条件（`f` 被当值传出、非尾位置调用、参数个数不符）的循环里若有 `await`，按 D2 报错，错误信息提示原因。

**D10 内联**：async 体内，以下形式在实参是**字面 lambda**、或是 `let`/`letrec` 绑定的 lambda 且该变量的全部引用都在这类位置（如 `parameterize` 展开出来的 `swap`）时内联，绑定随之删除：

| 形式 | 变成 |
|---|---|
| `((lambda (x …) body) e …)` | `(let ([x e] …) body)` |
| `(dynamic-wind (lambda () b) (lambda () body) (lambda () a))` | `(begin b (try-finally body a))` |
| `(with-exception-handler h (lambda () body))` | `(let ([old ($current-handlers)]) ($set-current-handlers! (cons h old)) (try-finally body ($set-current-handlers! old)))` |
| `(call-with-values (lambda () body) consumer)` | `(let ([t body]) (call-with-values (lambda () t) consumer))` |
| `(call/cc (lambda (k) body))` | `(escape-frame k body)` |

`dynamic-wind`、`with-exception-handler`、`call-with-values`、`call/cc` 按**绑定身份**识别（`(boot exceptions)` / 原语的库变量，不是按名字）。`$current-handlers` / `$set-current-handlers!` 是新的 C# 原语，`*current-exception-handlers*` 的存储移到 C#（`AsyncLocal`，D7），`(boot exceptions)` 的 `with-exception-handlers`、`raise` 改用这两个原语；语义不变。
`escape-frame` 是 `call/cc` 的内联版本：codegen 生成 `k = new EscapeContinuation(); try { body } catch (ContinuationException e) { if (e.Continuation != k) rethrow; 值 = e.Value } finally { k.Invalidate() }`，与 `Control.CallWithCurrentContinuation` 相同。
这五条合起来覆盖 `guard` 的整个展开（`((call/cc (lambda (k) (with-exception-handler H (lambda () (call-with-values (lambda () body) C))))))`），**不改 `guard` 和 `parameterize` 宏**。`guard` 的子句体、`dynamic-wind` 的 before/after、`try-finally` 的 finally 里仍然不能 `await`（Roslyn 对 catch/finally 里的 await 有专门变换，以后需要再做）。

**D11 拆分（spill）**：挂起点上求值栈必须只有那个 Task。`lower-async` 保证 `await` 只出现在**语句位置**：lambda 体、`let`/`letrec` 的体和右边、`if` 的两个分支、`begin` 的元素、`try-finally` 的体、`escape-frame` 的体、`label` 的体。其他位置（调用的操作符与操作数、`if` 的测试、`set!` 的右边、`and`/`or`、原语与互操作形式的参数、`jump` 的实参 …）若含 `await`，把该节点的子表达式**从左到右**依次 `let` 绑定到临时变量，原节点改为引用临时变量：
```
(f a (await x) (g y))  ⇒  (let* ([t0 f] [t1 a] [t2 (await x)] [t3 (g y)]) (t0 t1 t2 t3))
(and a (await b))      ⇒  (if a (await b) #f)
```
Scheme 不规定操作数求值顺序，这里固定为从左到右（codegen 本来也是）。临时变量在 codegen 里是帧字段，所以挂起后不丢。

### 3.3 codegen

**D12 两个类**：`async-lambda` 生成
- 过程类 `X : Procedure`（无自由变量时照旧是静态单例）：`InvokeK(args)` = `newobj XFrame(c0 …, args); call AsyncFrame::Start; ret`（`Task<object>` 当 `object` 返回）。`InvokeN`、`Arity` 等与普通 lambda 相同；有剩余参数时打包后再建帧。
- 帧类 `XFrame : AsyncFrame`：字段 = 自由变量副本 + 形参 + 体内所有局部变量与临时变量（`vars` 表中一律 `(field . 名字)`，`new-local!` 在 async 上下文里分配字段而不是 IL 局部变量）；`override MoveNext`。
已知过程的直接调用规则不变：库里无自由变量、不被 `mset!` 的 async 过程，参数个数相符时直接 `call X::C0`（它新建帧并 `Start`）。

**D13 `MoveNext` 的生成**（async 方法上下文，`mctx` 加 `async?` 与恢复点表）：
- 整个体在 `try { … } catch (Exception e) { Fail(e) }` 里；体的值（尾上下文）→ `Complete(v); leave END`。
- `tail-ok?` 恒为假；自尾调用不再是"重新赋参数跳回开头"（async 体没有 loop-label），而是普通调用后 `Complete`。
- `(await e)`：`<e>; stloc tmp; ldarg 0; ldloc tmp; ldc.i4 n; call Suspend; brtrue L_n; leave END; L_n: ldarg 0; call Resume`。
- **分派**：`MoveNext` 开头对体内每个恢复点 `n` 发 `ldarg 0; ldfld state; ldc.i4 n; beq 目标`（或 `switch`）。恢复点在 try 区域里时，外层目标是该 try 的入口前标签，进入 try 后再对区域内的恢复点分派一次；逐层嵌套同理。
- **finally 守卫**：`try-finally` 的 finally 体前加 `ldarg 0; ldfld state; ldc.i4 0; bge SKIP`，挂起时的 `leave` 不执行用户的 finally。`escape-frame` 的 `finally { k.Invalidate() }` 同样守卫（挂起时续延仍有效）。
- `label` / `jump`：如 D9。`jump` 的实参先全部求值到临时字段再写入参数字段（并行赋值）。
- 变量存取：`ldarg 0; ldfld` / `<值>; stloc tmp; ldarg 0; ldloc tmp; stfld`（值含 await 的情况已被 D11 排除，但统一走临时变量最简单）。
- `operands!` 的 lift-try 规则扩展为"后面的操作数含 `try` 或恢复点"——D11 之后这种情况不会出现，保留作为断言。

**D14 Lcil 与发射器**：不需要新指令。帧类的方法引用里写 `"IronScheme.Core.AsyncFrame"` 和返回类型反射名 ``"System.Threading.Tasks.Task`1[System.Object]"``。`ilverify` 命令不用改。

## §4 偏离与限制

| 项 | 行为 |
|---|---|
| `await` 在未内联的嵌套 lambda 里 | 编译错误。用 `for-each-async` / `map-async` 或显式循环 |
| `guard` 子句、`dynamic-wind` before/after、finally 里的 `await` | 编译错误（第一版） |
| `dynamic-wind` 与挂起 | 挂起、恢复**不**触发 before/after（一次性续延语义，与 C# finally 一致） |
| 逃逸续延跨线程 | async 体内捕获的 `k` 在帧完成前有效；从别的线程调用它只会在那个线程上抛异常，不会回到帧（与现在"续延只能向上逃逸"一致，文档写明） |
| 参数对象 | async 体内 `(p v)` 对调用方不可见（D7） |
| 尾调用 | async 体内没有 `tail.`；async 过程互相尾递归一百万层也不溢出（续延链在堆上），但比循环慢 |
| 多值 | `(await t)` 若 Task 的结果是 `MultipleValues`，按多值返回（和普通调用一致） |
| stage0 与 boot 镜像 | boot 源码不用 `async-lambda`，stage0 不实现它；`(ironscheme async)` 是普通系统库 |

## §5 验证

- `src/scheme/tests/async/*.sps`：iron-049 的测试矩阵改写成 Scheme（快路径不换线程、挂起后恢复、循环、`parameterize` / `dynamic-wind` / `guard` / `with-exception-handler` 跨 await、异常原样、async 调 async、闭包捕获、深递归、100 × 300 ms 并发 < 1 s、`clr-call` 返回 `Task<int>`、把 async 过程当 `Func<Task<int>>` 传给 .NET）；加上编译错误的用例（嵌套 lambda 里 await、非尾位置循环里 await）。
- 自举不动点不受影响（boot 不用 async）；编译整个种子的统计输出不变（`lower-async` 对无 async 的单元是恒等）。
- 系统库编译与 ILVerify 通过；`(ironscheme async)` 的 `.fasl` 过 ILVerify。
- 性能基线：同步完成的 `(await t)` 每次调用 ≤ 50 ns（spike 22 ns，加上 Scheme 调用约定的开销）。

## §6 不选的方案

- **Runtime Async**（iron-048）：语义相同、编译器几乎不用改，但要环境变量开关、不开则含 async 方法的类型加载失败、ILVerify 不认识。等它在后续 .NET 版本默认开启后，可以作为第二个后端替换 D12/D13，语言表面不变。
- **CPS 闭包**：把 async 体做 CPS 变换、每个 await 一个闭包、用 TCS 完成。不需要帧类，但同步路径每个 await 都分配、栈随同步完成的次数增长、`guard`/`dynamic-wind` 跨 await 要自己维护处理器链，和 D10 相比没有优势。
- **全程序 CPS**：顺带得到完整 `call/cc`，但所有代码变慢、互操作边界全要包装，README 已明确放弃。
- **线程式**（现有库 + `Task.Run`）：不改编译器，但每个进行中的 async 占一个线程，并发一高就饿死线程池。保留 `task-run` 给确实要跑在线程池上的同步工作。

## §7 与其他文档的关系

- [02](02-runtime.md) §6：异常处理器栈的存储移到 C#（D7、D10），`call/cc` 多一个内联版本 `escape-frame`（D10）；§4 过程模型加 `AsyncFrame`。
- [03](03-compiler.md) §2 Lcore 加 `async-lambda` 与 `await`；§4 pass 链加 `lower-async`；§5 尾调用加"async 体内无尾调用"。
- [06](06-r6rs-and-testing.md) §1 偏离表加 §4 的条目。

## §8 任务

| 任务 | 内容 | 依赖 |
|---|---|---|
| iron-050 运行时 | `AsyncFrame`；`Tasks.cs` 原语（D5 的过程、`Box<T>`/`Unbox<T>`）；参数对象改 `AsyncLocal`（D7）；处理器栈原语 `$current-handlers`（D10）；互操作 Task 转换（D8）；`(boot exceptions)` 改用新原语 | iron-049 |
| iron-051 前端 | 展开器 `async-lambda` / `define-async` / `await`；`rewrite`、parse-core、L0 节点；`lower-async`（D9 ~ D11、D2 检查）；各 pass 透传 | iron-050 |
| iron-052 codegen | 过程类 + 帧类（D12）；async 方法上下文、分派、守卫、`label`/`jump`、`escape-frame`（D13） | iron-051 |
| iron-053 库与测试 | 重写 `(ironscheme async)`（D5）；`tests/async`；文档（README、02、03、06 的更新） | iron-052 |

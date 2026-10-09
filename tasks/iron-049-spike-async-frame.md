# iron-049 验证 AsyncFrame 状态机能否做 async-lambda 的后端

- 里程碑：后续　依赖：iron-048　状态：完成
- 设计依据：[02](../designs/02-runtime.md) §互操作、[03](../designs/03-compiler.md) §5、[04](../designs/04-lcil-and-emitter.md)

## 目标
iron-048 证明 Runtime Async 可行但是实验特性（环境变量开关、不开则类型加载失败、ILVerify 不认识）。本任务验证不依赖它的方案：
编译器自己做 Roslyn 那种状态机变换，只用公开稳定的 `AsyncTaskMethodBuilder<object>` / `TaskAwaiter<object>` / `IAsyncStateMachine`。

形状：
- 运行时加一个 C# 基类 `AsyncFrame : IAsyncStateMachine`，持有 builder、awaiter、`state`，提供 `Start()`、`Suspend(task, n)`、`Resume()`、`Complete(v)`、`Fail(e)`。所有 `ref` 操作都在基类里，发射的代码只做普通调用。
- 每个 `async-lambda` 编译成 `AsyncFrame` 的子类：参数与局部变量都是字段，`MoveNext` 是函数体，入口 `InvokeN(args) = new Frame(args).Start()` 返回 `Task<object>`。
- `(await e)` 在 ANF 之后降成：`if (!Suspend(e, n)) leave END; L_n: Resume()`。
- `MoveNext` 开头按 `state` 分派到恢复点（spike 用 `beq` 链；Lcil 的 `switch` 也可用）；恢复点在 try 块里时，外层先跳到 try 入口前，进入 try 后再分派一次（IL 不许从外面跳进 try）。
- `finally` 块体用 `state < 0` 守卫，挂起时的 `leave` 不执行用户的 finally。
- 整个函数体包在 `try { … } catch (Exception e) { Fail(e) }` 里。

## 结论（2026-10-09，.NET 10.0.12，Linux x64）

验证程序：`spikes/iron-049/`（`dotnet run -c Release -- all`，或 `save` 后 `load all`）。测试项与 iron-048 相同（去掉 `tail`），另加 `stack`。

| 项 | 结论 | 说明 |
|---|---|---|
| 已完成的 Task | **同步返回** | 不换线程；每次 async 调用约 22 ns（Runtime Async 12 ns，C# 编译器 async/await 26 ns），含一个帧对象与一个 Task 的分配；await 本身零分配 |
| 未完成的 Task | **挂起** | 调用方立刻拿到未完成的 Task，恢复在池线程；首次挂起时 builder 再分配一个 `AsyncStateMachineBox`，之后复用 |
| 循环体内 await | **可行** | 恢复点在循环中间，循环变量是字段 |
| try/finally 跨 await | **可行** | 分派进 try、finally 守卫两个技巧都验证了：挂起后恢复、同步完成、await 抛异常三种路径 finally 各恰好一次 |
| try/catch 跨 await | **可行** | `Resume()` 抛出的异常被同方法的 catch 接住 |
| 异常传播 | **原样** | 和 Runtime Async 一致，因为由 Task 决定 |
| async 调 async | **可行** | 普通 `call` 入口方法再 await |
| `Procedure` 包装 | **可行** | `Invoke1` 新建帧并 `Start()`，`Task<object>` 当 `object` 返回 |
| 上下文 | 与 C# 一致 | `AsyncLocal` 保留，`[ThreadStatic]` 丢失 |
| 深递归、每层挂起 | **不溢出** | 一百万层 8 s（Runtime Async 2 s）；恢复链由 Task 的续延机制展开，栈不足时自动排队到线程池 |
| 全程同步完成的深递归 | 每层约 2 个托管栈帧 | 入口 + `MoveNext`，和普通递归量级相同 |
| 并发 | **不占线程** | 100 × 300 ms 共 302 ms |
| PersistedAssemblyBuilder | **可行** | 保存后加载，全部通过 |
| ILVerify | **通过** | 全部类型与方法验证通过 |
| 开关 | **无** | 任何 .NET 版本都能跑 |

## Lcil 需要的能力
全部已有：`(base …)`、`override` 方法、`newobj` / `ldfld` / `stfld`、`beq` / `brtrue` / `leave`（`switch` 也有）、嵌套 `try` 且块内显式 `leave`。不需要 `ldflda`、byref 参数或结构体局部变量；基类已实现 `IAsyncStateMachine`，子类不用声明接口。

## 对设计的影响
- **选这条路**，不用 Runtime Async。iron-048 的语义结论（异常、上下文、并发）在这里同样成立。
- 编译器要做的：
  1. `async-lambda` 核心形式；`await` 只能直接出现在它的函数体里（和 C# 相同），嵌套 lambda 里出现则报错。
  2. ANF：`await` 只能在"语句"位置，复用 linearize 的 `remove-complex-opera*`。
  3. async 函数体内所有变量提升为帧字段；函数体内不发 `tail.`；自尾调用不能再用"重新赋参数跳回开头"以外的方式。
  4. 恢复点分派：每个包含恢复点的 try 块入口处再分派一次；`$try/finally` 的 finally 体加 `state < 0` 守卫；逃逸续延帧（try/catch）内的 await 同理。
  5. `guard` 的处理器体、`dynamic-wind` 的 before/after 里暂不允许 await（Roslyn 对 catch/finally 里的 await 有专门变换，可以之后再做）。
- 运行时要做的：`AsyncFrame` 基类；`parameterize` 等线程局部状态改用 `AsyncLocal`；互操作里 `Task<T>` → `Task<object>` 的转换；`(ironscheme async)` 改为这套实现。

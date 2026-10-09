# iron-048 验证 Runtime Async 能否做 async-lambda 的后端

- 里程碑：后续　依赖：iron-003　状态：完成
- 设计依据：[02](../designs/02-runtime.md) §互操作、[03](../designs/03-compiler.md) §5

## 目标
在给 Scheme 加 `async-lambda` / `await`（顺序写法、不占线程的异步 IO）之前，确认 .NET 10 的 Runtime Async 能否直接当后端：
发射器把 `async-lambda` 的函数体发射成带 `MethodImplAttributes.Async` 标记、返回 `Task<object>` 的方法，`await` 降成一条 `call AsyncHelpers.Await<object>`，挂起与恢复全部交给 JIT，编译器不做 CPS。

## 工作内容
用 Reflection.Emit 手工发射这类方法，覆盖 codegen 会生成的几种形状：循环体内 await、try/finally 与 try/catch 跨 await、async 调 async、`Procedure` 子类的 `Invoke1` 包装 async 静态方法、深递归每层挂起；并测异常传播、上下文流动、并发耗时、同步路径开销、`tail.`、PersistedAssemblyBuilder 保存后加载、ILVerify，以及不开启开关时的行为。

## 结论（2026-10-09，.NET 10.0.12，Linux x64）

验证程序：`spikes/iron-048/`（`DOTNET_RuntimeAsync=1 dotnet run -c Release -- all`，或 `save` 后 `load all`）。

| 项 | 结论 | 说明 |
|---|---|---|
| 发射方式 | **可行** | 方法签名返回 `Task<object>`，`SetImplementationFlags(MethodImplAttributes.Async)`（值 0x2000），方法体里 `ret` 时栈上是 `object`；`await` = `castclass Task<object>; call AsyncHelpers.Await<object>` |
| 已完成的 Task | **同步返回** | 不换线程，返回的 Task 已完成；每次 await 约 12 ns（C# 编译器 async/await 约 29 ns，普通调用 0.2 ns） |
| 未完成的 Task | **挂起** | 调用方立刻拿到未完成的 Task，恢复在池线程上，结果正确 |
| 循环体内 await | **可行** | 一千次 |
| try/finally、try/catch 跨 await | **可行** | finally 恰好执行一次；await 处抛出的异常被同一方法的 catch 接住。`$try/finally`（`dynamic-wind`）和 `guard` 因此不需要特殊处理 |
| 异常传播 | **原样** | 被等待的 Task 出错时，async 方法内看到的是原异常（不是 `AggregateException`），同步失败与挂起后失败都一样 |
| async 调 async | **可行** | 普通 `call`，JIT 自动用 async 调用约定；同步路径不多分配 |
| `Procedure` 包装 | **可行** | `Invoke1` 返回 `object` 的虚方法 `call` 一个 async 静态方法并把 `Task<object>` 当 `object` 返回 |
| 上下文 | 与 C# 一致 | `AsyncLocal` 跨 await 保留；`[ThreadStatic]` 恢复后丢失。运行时里的线程局部状态（参数对象等）要改用 `AsyncLocal` 或随帧保存 |
| 深递归、每层挂起 | **不溢出** | 一百万层，恢复链在池线程上展开，约 2 s；十万层 40 ms |
| 并发 | **不占线程** | 100 个各等 300 ms 的 await 总耗时 306 ms（现有 `(ironscheme async)` 的阻塞式 await 要 30 s） |
| `tail.` 前缀 | 不报错 | async 方法体内 `tail. call` 被接受（是否真尾调用未测）；codegen 对 async 方法体应直接不发 `tail.`，和 C# 一样 |
| PersistedAssemblyBuilder | **可行** | 保存后 `Assembly.LoadFrom` 加载，impl flags 仍是 `Async`，全部测试通过 |
| ILVerify | **不认识** | 对 async 方法报 `StackUnexpected`（期望 `ret` 时栈上是 `Task<object>`）。`ilverify` 命令要跳过带 `Async` 标记的方法 |
| 开关 | **只能用环境变量** | 必须 `DOTNET_RuntimeAsync=1`；libcoreclr 里没有对应的 `runtimeconfig.json` 属性；`RuntimeFeature.IsSupported("RuntimeAsync")` 恒为 false，不能用来探测 |
| 不开开关 | **类型加载失败** | 含 async 方法的类型 `CreateType` / 加载时抛 `TypeLoadException`（"format is invalid"），不是调用时才失败。所以带 `async-lambda` 的库在没开开关的进程里整个加载不了；boot 镜像里不能用 async-lambda，除非编译器在没开开关时降级 |

## 对设计的影响
- **结论：不采用。** 实验特性的三个问题（环境变量开关、不开则类型加载失败、ILVerify 不认识）在 [iron-049](iron-049-spike-async-frame.md) 的 AsyncFrame 状态机方案里都不存在，语义结论则完全一致；后端选 iron-049。以下是本方案自身的评估，留作记录。
- 后端可行，且比 CPS 方案省掉整个 pass：`async-lambda` 在 codegen 里只是"方法加 `Async` 标记、`ret` 前不装 Task、不发 `tail.`"，`await` 是一个内联原语。
- 代价是实验特性：.NET 10 需要环境变量；标记和 `AsyncHelpers` 的形状在 .NET 11 可能变。语言表面（`async-lambda`、`define-async`、`await`，返回 `Task<object>`）要和后端解耦，必要时可退回 CPS 后端。
- 需要先解决的问题：
  1. 没开开关时的行为——编译时检测（`Environment.GetEnvironmentVariable`）并报错，或降级为线程式实现。
  2. `parameterize` 等线程局部运行时状态改为 `AsyncLocal`（或在挂起点保存、恢复）。
  3. `ilverify` 跳过 async 方法。
  4. `Task<T>` → `Task<object>` 的转换放进互操作，Scheme 侧只见 `Task<object>`。

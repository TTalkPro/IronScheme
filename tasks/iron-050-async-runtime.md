# iron-050 异步：运行时支持

- 里程碑：后续　依赖：iron-049　状态：完成
- 设计依据：[10 §2](../designs/10-async.md) D6 ~ D8、§1 D5

## 目标
给 `IronScheme.Core` 加上状态机基类、Task 原语、随 `ExecutionContext` 流动的参数对象，以及互操作里的 Task 转换。这一步完成后编译器才有东西可以调用；在此之前 `(ironscheme async)` 仍是旧实现。

## 工作内容
1. **`AsyncFrame`**（`Control.cs` 旁新文件 `AsyncFrame.cs`）：照 `spikes/iron-049/Program.cs` 的基类移植，`Suspend` 对非 `Task<object>` 的参数报 `&assertion`（who = `await`）；`state` 字段公开给生成代码。
2. **`Tasks.cs`**：D5 列出的过程用 `[Primitive]` 实现（`task?` `task-completed?` `task-faulted?` `task-result` `task-from-result` `task-from-exception` `task-delay` `task-yield` `task-run` `task-then` `task-when-all` `task-when-any`、TCS 四个）；`task-result` 用 `GetAwaiter().GetResult()` 解包异常；`task-then` 的回调结果若是 Task 则展开。另加 `Tasks.Box<T>(Task<T>)` → `Task<object>`、`Tasks.Unbox<T>(Task<object>)` → `Task<T>`、非泛型 `Task` 的包装（结果为未指定值）。
3. **参数对象改 `AsyncLocal`**（D7）：原语 `$make-param-slot` / `$param-ref` / `$param-set!`（每个参数一个 `AsyncLocal<object>`，未设置时回退到初始值）；`boot/expander/compat.sls` 的 `make-parameter` 改用它们；"创建线程上的赋值更新回退值"的逻辑搬进 C#（见结论）。
4. **异常处理器栈移到 C#**：原语 `$current-handlers` / `$set-current-handlers!`（`AsyncLocal<object>`，缺省为"抛 `SchemeException`"的处理器表）；`(boot exceptions)` 的 `*current-exception-handlers*`、`with-exception-handlers`、`raise`、`raise-continuable` 改用它们，语义不变。
5. **互操作**（D8）：`Interop.ConvertFrom` 与 `EmitInterop.ConvertFrom` 对 `Task<T>`（T ≠ object）和 `Task` 返回值包成 `Task<object>`；`ToDelegate` 对返回 `Task<T>` / `Task` 的委托做反向转换。
6. 重新生成 `primitives.ss`（PrimGen）。

## 验收标准
- 全部现有测试通过（参数对象与异常处理器的改动不改变单线程语义；`parameterize` 的测试、R6RS `exceptions` 测试、自举不动点）。
- 新 C# 测试：`Box`/`Unbox` 保留结果、异常与取消；`parameterize` 的值在 `Task.Run` 的子任务里可见（`AsyncLocal` 流入）、子任务里的赋值不流出。
- `(clr-static-call File ReadAllTextAsync …)` 在 Scheme 里得到 `Task<object>`；把返回 Task 的 Scheme 过程 `clr-cast` 成 `Func<Task<int>>` 后在 C# 里 await 得到整数。

## 结论
- 新文件 `src/IronScheme.Core/AsyncFrame.cs`、`Tasks.cs`、`Parameters.cs`（`ParamSlot` + `Parameters` 原语 + `ExceptionHandlers`）；`Interop.ConvertFrom` 按运行时类型把任何 `Task` 包成 `Task<object>`，`Interop.ConvertTo` 对目标 Task 类型走 `Tasks.ToTaskType`（`Task<object>` → `Task<T>`，普通值包成已完成的 Task），`ToDelegate` 因此不用改；`EmitInterop.ConvertFrom` 对静态已知的 `Task<T>` / `Task` 返回类型直接 `call Tasks.Box`。
- `AsyncFrame.Suspend` 对非 `Task<object>` 的 `Task` 兜底包装，只对非 Task 报 `&assertion`。
- 原语登记在两个构建脚本的 `identifier->library-map` 里：`$` 原语在 `(ironscheme unsafe)`，Task 原语在 `(ironscheme core)`；`primitives.ss` 已重新生成（157 项）。
- **种子两步走**：`compat.sls` 是构建脚本自己从源码加载的四个展开器文件之一，用新原语会在旧种子上报 "cannot find identifier"。按 [05 §5](../designs/05-bootstrap.md) 新加的说明做了两步（临时 `clr-static-call` → 构建 → `build.cs seed` → 换回原语 → 构建 → `seed`），种子已重新生成。
- 偏离与细节已写回 [10](../designs/10-async.md) D5、D7、D8 与 [02 §6](../designs/02-runtime.md)：`with-exception-handlers` 不再经过 `parameterize`，空表不再被当作"未设置"；**"创建线程上的赋值更新回退值"保留**（设计原想删，实测 WebServer 示例的请求线程因此读不到主线程启动时设置的库集合，`eval` 失败）。
- `task-result` 与 `AsyncFrame.Resume` 对以 Scheme 条件失败的 task 重新 `raise`（本系统的 `guard` 不接 .NET 原生异常），其他 .NET 异常原样抛出。
- 测试：`tests/IronScheme.Core.Tests/AsyncTests.cs`（帧的快路径 / 挂起恢复 / 异常 / 非 Task / `AsyncLocal` 跨挂起、Box/Unbox、ConvertFrom/ConvertTo/ToDelegate、各原语、参数槽、处理器栈）；`src/scheme/tests/async/interop.sps` 由 `tests/IronScheme.Tests/AsyncTests.cs`（类别 `Async`）运行，覆盖验收标准第三条与原语、`parameterize` 流入 `task-run`、处理器流入线程池。

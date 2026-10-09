# iron-053 异步：`(ironscheme async)` 库、测试与文档

- 里程碑：后续　依赖：iron-052　状态：完成
- 设计依据：[10 §1](../designs/10-async.md) D5、§4、§5

## 目标
把 `(ironscheme async)` 换成新实现，补齐测试与文档，async 功能对用户可用。

## 工作内容
1. **重写 `lib/ironscheme/async.sls`**：导出 D5 的全部名字；`async-lambda` / `define-async` / `await` 是核心形式的再导出；Task 过程直接用 iron-050 的原语，不再有 `clr-dynamic`；`for-each-async` / `map-async` 用 `async-lambda` 加显式循环实现；删除 `start`、`started?`、`status`。
2. **测试 `src/scheme/tests/async/`**（测试类别 `Async`，接进 `dotnet test`）：
   - 语义：快路径不换线程、挂起后恢复、循环内 await、`parameterize` / `dynamic-wind` / `guard` / `with-exception-handler` 跨 await、被等待的 Task 失败时异常原样、async 调 async、闭包捕获、深递归一万层、多值结果；
   - 互操作：`clr-call` 返回 `Task<int>` 可 await、Scheme async 过程转 `Func<Task<int>>` 给 C# await、`task-then` / `task-when-all` / TCS；
   - 并发：100 × 300 ms 总耗时 < 1 s；
   - 编译错误用例（与 iron-051 的一致）；
   - `bench.sps`：同步 await 每次调用的纳秒数。
3. **文档**：README 加 async 一节（写法、限制、与 .NET Task 的互操作）；[06 §1](../designs/06-r6rs-and-testing.md) 偏离表加 10 §4 的条目；`docs/` 里若有旧 async 说明一并更新。
4. 把示例 `examples/` 里适合的地方（如 HTTP 或文件 IO）改成 async 写法，作为用法展示。

## 验收标准
- `dotnet test --filter TestCategory=Async` 通过；全部测试通过；系统库编译与 ILVerify 通过。
- `(import (ironscheme async))` 后 README 里的示例可直接运行。

## 结论
- `lib/ironscheme/async.sls` 重写：再导出 `async-lambda` / `define-async` / `await`，Task 过程来自 `(ironscheme core)` 的 C# 原语，`for-each-async` / `map-async` 是 `define-async` + 命名 let（f 须返回 task；要并发用 `(task-when-all (map f l))`）；`start` / `started?` / `status` 删除；库加进 `system-libraries.ironscheme.ss`（`compile-system-libraries` 会编译它，`SystemLibraries` 测试覆盖）。
- 测试 `tests/async/`（类别 `Async`，`AsyncTests.cs`）：`basic.sps`（iron-052，状态机语义 34 项）、`interop.sps`（iron-050，Task 转换与原语 26 项）、`library.sps`（本任务 23 项：再导出、`for-each-async` / `map-async` 顺序与并发写法、多值跨 await、六个编译期错误用例经 `eval` 验证错误信息、`Func<Task<int>>` 互操作、失败经 task 传递）、`bench.sps`（Release 下 async 调用比同步调用多 7 ns）。
- 文档：README 加 Async 一节（写法、限制、与 .NET Task 的互操作）；06 §1 偏离表加 10 §4 的条目；`docs/` 目录不存在，无旧说明要改。
- 示例：`examples/WordCount` 改为用 `File.ReadAllTextAsync` + `task-when-all` 并发读文件（自包含发布测试 `PublishTests` 因此也覆盖了 async 的整程序编译）。

# iron-007 运行时钩子取代 Glue.il

- 里程碑：M1　依赖：iron-006　状态：完成
- 设计依据：[02 §6](../designs/02-runtime.md)、[01 §2](../designs/01-current-state.md)

## 目标
C# 调用 Scheme 定义的过程（`raise`、`assertion-violation` 等）改为通过钩子，去掉对 boot dll 方法名的硬编码。

## 工作内容
1. `RuntimeHooks`：对应 `IronScheme.Glue.il` 中 15 个方法的 `Procedure` 字段。
2. 原语 `$set-runtime-hook!`。
3. C# 侧的错误报告辅助方法（`AssertionViolation`、`UndefinedError`、`LexicalError` 等）通过钩子调用；钩子未登记时（启动早期）抛出带说明的 .NET 异常。
4. 列出 boot 镜像初始化时需要登记的钩子清单，供 iron-013 在 `build/exceptions.sls` 等处加入登记代码。

## 验收标准
- 单元测试：登记测试用钩子后，C# 报错能调用到它；未登记时有明确错误。

## 结论（2026-10-08）

### 实现（`IronScheme/IronScheme.Core/`）

| 文件 | 内容 |
|---|---|
| `RuntimeHooks.cs` | 15 个 `Procedure` 字段，与旧 `IronScheme.Glue.il` 的方法一一对应，名字取 Scheme 过程名；`Set`/`Get`/`Clear`/`Names`；原语 `$set-runtime-hook!`（参数为符号与过程）与 `$runtime-hooks-missing`（返回尚未登记的钩子名列表，boot 初始化结束后应为 `'()`） |
| `Errors.cs`（重写） | 报错入口经钩子调用 Scheme 条件过程：`AssertionViolation`（把 irritants 展开为剩余参数，对应旧 `assertion-violation+`；`who` 为 null 时传 `#f`）、`UndefinedError`、`LexicalError`、`SyntaxError`、`IOPortViolation`、`FileNotFoundViolation`、`FileInUseViolation`、`FileAlreadyExistsViolation`、`IODecodingError`、`IOEncodingError`、`Raise`。钩子未登记时退回：抛 `SchemeRuntimeError`；`Raise` 则与 Scheme 默认处理器一致，抛 `SchemeException` |
| `Errors.cs` 中的 `SchemeCalls` | 非报错类钩子：`Exact`、`Inexact`、`RaiseContinuable`、`WithExceptionHandler`；未登记时抛 `InvalidOperationException` 并说明 |
| `SchemeException.cs` | 移植自旧运行时：携带条件对象。可读打印由宿主用 Scheme 打印器生成（iron-029） |

`Procedure.ArityError`、`symbol-value` 的未绑定错误等，都已自动经由钩子报告。

### boot 镜像需要登记的钩子（供 iron-013）

| 钩子 | 定义所在文件（`IronScheme.Console/build/`） |
|---|---|
| `assertion-violation`、`undefined-error`、`lexical-error`、`syntax-error`、`i/o-port-violation`、`file-not-found-violation`、`file-in-use-violation`、`file-already-exists-violation`、`io-decoding-error`、`io-encoding-error`、`raise`、`raise-continuable`、`with-exception-handler` | `exceptions.sls` |
| `exact`、`inexact` | `numbers.sls` |

建议写法：在两个库的库体末尾各加一组 `($set-runtime-hook! 'raise raise)`。由于 `exceptions.sls` 在 boot 顺序中先于 `numbers.sls`（见 01 §2 的构建顺序），`exact`/`inexact` 未登记前若有 C# 代码调用它们会抛出 `InvalidOperationException`，需要在 iron-013 中确认启动顺序。boot 初始化结束时调用 `($runtime-hooks-missing)` 断言为空。

`assertion-violation` 在 Scheme 中是 `(assertion-violation who message irritant ...)`，C# 侧按剩余参数展开调用；旧系统依赖的 `assertion-violation+` 方法名不再需要。

### 测试

`IronScheme.Core.Tests/RuntimeHooksTests.cs` 新增 10 项（标为不并行，每项结束清空钩子），全部 45 项通过：15 个钩子名与旧胶水一致、`$set-runtime-hook!` 正常与错误用法、`$runtime-hooks-missing`、`assertion-violation` 参数展开与 `who` 为空、参数个数错误经钩子报告、未绑定符号经 `undefined-error` 钩子、其余 8 个报错钩子的参数、未登记时的退回行为、非报错钩子。

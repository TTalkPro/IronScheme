# iron-006 过程模型与控制原语

- 里程碑：M1　依赖：iron-005　状态：完成
- 设计依据：[02 §4、§6](../designs/02-runtime.md)

## 目标
实现 `Procedure` 基类及控制相关原语。

## 工作内容
1. `Procedure`：`Invoke0..Invoke4`、`InvokeN`、默认分派、`ArityError`、`Name`。
2. `Box`。
3. `apply`、`values`、`call-with-values`。
4. 逃逸续延：`EscapeContinuation`、`ContinuationException`（带标记）、帧退出后失效检测；`call/cc` 的运行时部分（编译器负责生成捕获帧，见 iron-025）。
5. 手写几个 `Procedure` 子类测试分派规则（固定参数、剩余参数、case-lambda 式多子句）。

## 验收标准
- 单元测试覆盖：参数个数错误、剩余参数打包、`InvokeN` 回退、多值、续延正常逃逸与失效后报错。

## 结论（2026-10-08）

### 实现（`IronScheme/IronScheme.Core/`）

| 文件 | 内容 |
|---|---|
| `Procedure.cs` | `Procedure`：`Invoke0` ~ `Invoke4`、`InvokeN`（统一入口，按长度分派）、`Name`、`ToString`、`ArityError`；`VariadicProcedure`：`InvokeK` 转发到抽象的 `InvokeN`，`RestList` 打包剩余参数；`Box` |
| `Control.cs` | `apply`（展开最后一个列表参数，检查正规列表，≤4 个参数走 `InvokeK`）、`call-with-values`（原语）、`Values`（C# 辅助，`values` 仍由 `build/exceptions.sls` 定义，与旧系统分工一致）、`call/cc` 与 `call-with-current-continuation`（逃逸续延）、`EscapeContinuation`、`ContinuationException` |

### 设计细节（已写回 02 §4）

拆成两个基类：固定参数过程继承 `Procedure` 并只重写对应 `InvokeK`；剩余参数过程继承 `VariadicProcedure` 并实现 `InvokeN`。单一基类加双向默认转发会在参数个数错误时无限递归。

### 逃逸续延

- `call/cc` 在 try 中调用接收者；续延被调用时抛 `ContinuationException`，捕获帧按续延对象身份接住并返回值（多个值包装为 `MultipleValues`）。
- 捕获帧在 finally 中使续延失效；之后再调用报 `assertion-violation`："continuation is no longer valid (only escaping, one-shot continuations are supported)"，取代旧系统的模糊错误。
- 其他异常照常穿过捕获帧，同样使续延失效。
- 续延调用发生在 try 区域内，不是尾调用（CIL 限制，与 03 §5 一致）。

### 测试

`IronScheme.Core.Tests/ProcedureTests.cs` 新增 16 项，全部 35 项通过：固定参数分派与错误、剩余参数打包、case-lambda 式多子句、打印、`Box`、`apply` 的三种调用形式与超过 4 个参数、`apply` 错误、`call-with-values` 的多值/单值/零值、`values` 单值不包装、续延带值逃逸、正常返回、多值逃逸、内层逃逸到外层帧、帧退出后失效、其他异常穿过并使续延失效。

### 留给后续任务

- 原语登记表需要支持 `params object[]` 形式的原语（如 `apply`），包装为 `VariadicProcedure`：iron-008。
- `procedure?` 等谓词在 Scheme 中改为 `(clr-is Procedure …)`：iron-013。
- `with-clr-exception-handler` 必须放行 `ContinuationException`：iron-008。
- 编译器可以把 `call/cc` 内联成捕获帧，运行时版本供 stage0 与非内联调用使用：iron-025。

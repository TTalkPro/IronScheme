# iron-007 运行时钩子取代 Glue.il

- 里程碑：M1　依赖：iron-006　状态：未开始
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

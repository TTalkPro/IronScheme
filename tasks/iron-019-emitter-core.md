# iron-019 发射器：类型、方法、指令与异常块

- 里程碑：M3　依赖：iron-018　状态：未开始
- 设计依据：[04 §4、§5](../designs/04-lcil-and-emitter.md)

## 目标
把 Lcil 对象模型发射成程序集，支持持久化与内存两种模式。

## 工作内容
1. 类型与成员名字解析（按全名、命名空间列表、引用程序集），按名字加载 `IronScheme.Core.dll`。
2. 类型、字段、方法（静态 / 实例 / 重写）定义；方法体指令发射；标签；`tail.` 前缀。
3. 结构化 `try/finally`、`try/catch`。
4. 互操作指令决议（04 §5）：唯一时静态调用 + 转换，否则调用 `Interop.*`。
5. 持久化模式（`PersistedAssemblyBuilder.Save`）与内存模式（`RunAndCollect`）。
6. 命令行 `iron-emit in.lcil -o out.dll`。
7. 可选：ILVerify 校验开关。

## 验收标准
- 手写 Lcil：阶乘（循环与递归）、闭包计数器、try/finally、相互尾递归一百万层、调用 `System.String::ToUpper` 与 `Interop.Call`，都能生成 dll 并正确运行。
- ILVerify 无错误。

# iron-006 过程模型与控制原语

- 里程碑：M1　依赖：iron-005　状态：未开始
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

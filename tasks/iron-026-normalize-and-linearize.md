# iron-026 上下文规范化、try 提升与线性化

- 里程碑：M4　依赖：iron-025　状态：未开始
- 设计依据：[03 §4](../designs/03-compiler.md) 第 12 ~ 15 步、§5

## 目标
生成 Lcil 文本。

## 工作内容
1. `normalize-context`：值 / 副作用 / 谓词上下文。
2. `lift-try`：表达式位置的 try 提升为语句。
3. `linearize`：栈式指令、局部变量分配、`.maxstack` 计算、分支汇合点栈形状检查、`tail.` 决定（try 区域内不加）。
4. 常量收集为常量表（调用 iron-020 的编码器）。
5. `emit-lcil`：输出文本。

## 验收标准
- 对若干小程序端到端：Lcore → Lcil → iron-emit → 运行，结果正确。

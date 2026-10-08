# iron-025 调用、原语与互操作降级

- 里程碑：M4　依赖：iron-024、iron-012　状态：未开始
- 设计依据：[03 §4](../designs/03-compiler.md) 第 10 ~ 11 步、§6、§7

## 目标
把应用、原语、全局访问、互操作形式降成接近 Lcil 的调用形式。

## 工作内容
1. 应用 → 静态调用 / `InvokeK` / `InvokeN`；全局读写 → 值槽访问与未绑定检查。
2. 原语：内联 IL 模板库（对应旧系统 56 个内联发射器）、静态调用、特殊原语（`$try/finally`、`$throw`、`call/cc` 逃逸帧、`values`、`call-with-values` 内联、`apply`）。
3. `clr-*-internal` → Lcil 互操作指令；`clr-using`/`clr-reference` 收集为方法级上下文。
4. `ffi-*`、`pinvoke-call-internal` → 运行时辅助调用。

## 验收标准
- 快照测试；对每个内联模板有对照用例。

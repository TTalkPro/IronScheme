# iron-024 闭包转换、类提升与循环降级

- 里程碑：M4　依赖：iron-023　状态：未开始
- 设计依据：[03 §4](../designs/03-compiler.md) 第 6 ~ 9 步、[02 §4](../designs/02-runtime.md)

## 目标
把 lambda 变成 `Procedure` 子类与静态方法，自尾调用变成循环。

## 工作内容
1. `uncover-free`、`convert-closures`（扁平闭包；无自由变量者提升为静态方法 + 单例；已知调用直接化）。
2. `lift-to-classes`：模块入口 `Initialize`；`library-letrec*` 绑定写入 loc 值槽。
3. `lower-loops`：自尾调用、命名 let、`do`。
4. case-lambda 与剩余参数对应的 `InvokeK` / `InvokeN` 重写方案。

## 验收标准
- 快照测试；类数量、静态方法比例的统计输出。

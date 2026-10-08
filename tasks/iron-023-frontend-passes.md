# iron-023 前中端 pass

- 里程碑：M4　依赖：iron-022　状态：未开始
- 设计依据：[03 §4](../designs/03-compiler.md) 第 2 ~ 5 步

## 目标
实现 `recognize-let`、`simplify-letrec`、`cp0-lite`、`convert-assignments`。

## 工作内容
1. 四个 pass 及其中间语言。
2. `cp0-lite` 只折叠原语表标为 `pure` 的 fixnum/flonum/谓词运算，结果经中立编码可表示。
3. 快照测试。

## 验收标准
- boot 源文件全部通过；L2 中不存在对被捕获变量的 `set!`（由文法保证）。

# iron-022 引入 nanopass 与 parse-core

- 里程碑：M4　依赖：iron-017、iron-012　状态：未开始
- 设计依据：[03 §1 ~ §3](../designs/03-compiler.md)

## 目标
建立编译器库结构，定义 Lcore 与 L0，实现第一个 pass。

## 工作内容
1. `IronScheme.Console/lib/ironscheme/compiler/` 下的库划分（iron-020 起编译器库放在这里，`compiler/` 只放原语表与测试）（语言定义、各 pass、驱动、原语表读取）。
2. `parse-core`：解析 03 §2 的固定文法；符号三分类（词法 / 原语 / 全局位置）；`case-lambda` 规范化；注解剥离并保留源位置。
3. 从文本种子中取若干库的核心形式作为真实 Lcore 样本，建立快照测试。开发与运行都在 stage0 上进行。

## 验收标准
- 文本种子中的全部核心形式都能通过 `parse-core`，无未知形式。

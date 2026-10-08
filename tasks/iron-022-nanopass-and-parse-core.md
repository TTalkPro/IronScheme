# iron-022 引入 nanopass 与 parse-core

- 里程碑：M4　依赖：iron-017、iron-012　状态：完成
- 设计依据：[03 §1 ~ §3](../designs/03-compiler.md)

## 目标
建立编译器库结构，定义 Lcore 与 L0，实现第一个 pass。

## 工作内容
1. `IronScheme.Console/lib/ironscheme/compiler/` 下的库划分（iron-020 起编译器库放在这里，`compiler/` 只放原语表与测试）（语言定义、各 pass、驱动、原语表读取）。
2. `parse-core`：解析 03 §2 的固定文法；符号三分类（词法 / 原语 / 全局位置）；`case-lambda` 规范化；注解剥离并保留源位置。
3. 从文本种子中取若干库的核心形式作为真实 Lcore 样本，建立快照测试。开发与运行都在 stage0 上进行。

## 验收标准
- 文本种子中的全部核心形式都能通过 `parse-core`，无未知形式。

## 结论（2026-10-08）

完成。

- **库划分**（`Console/lib/ironscheme/compiler/`）：`primitives.sls`（原语表读取）、`languages.sls`（L0 ~ L3）、`parse.sls`（parse-core）、`front.sls`（分析与前中端 pass）、`closures.sls`（uncover-free）、`codegen.sls`（代码生成）、`lcil.sls`（文本写出）、`constants.sls`（iron-020）；驱动 `(ironscheme compiler)` 在 `lib/ironscheme/compiler.sls`。语言定义与 pass 分属不同库，nanopass 语言跨库导出在 stage0 上实测可用。
- **parse-core**：只接受 03 §2 的固定文法；符号三分类（词法 / 库变量 / 原语 / 全局位置）只看绑定与原语表；各种 case-lambda 统一为 `(lambda 名字 (clause …) …)`，绑定右边的 lambda 以变量名（去掉 gensym 装饰）为过程名；注解剥离，第一版不保留源位置；`$and?` 等 special 原语变为 `and`/`or`/`throw`/`break`/`try-finally`。
- **互操作说明的文本化**：类型说明 `(Name A B)` 写成 `"Name<A,B>"`，泛型方法 `(Name #(G …) P …)` 写成 `("Name" ("P" …)|#f ("G" …))`。为此扩展了 Lcil 规格（04 §2.5）与发射器（泛型方法总由运行时决议；泛型类型名转成 TypeResolver 的说明）。
- 注意：nanopass 的元变量名不能以 `?` 结尾；模式变量必须以元变量名开头（如 `x1*`）。

验收：`compiler/tests/parse-seed.sps`——文本种子 38 个形式全部通过 parse-core。快照：`compiler/tests/snapshots/*.l0`（见 iron-026）。

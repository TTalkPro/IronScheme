# iron-017 在 stage0 上跑通 psyntax 与 nanopass

- 里程碑：M2　依赖：iron-015、iron-016、iron-002　状态：未开始
- 设计依据：[05 §3](../designs/05-bootstrap.md)、[00 §6 风险](../designs/00-overview.md)

## 目标
stage0 解释执行文本种子，得到可用的 R6RS 环境，并在其上加载运行 nanopass。

## 工作内容
1. stage0 执行 `boot-seed.core`：登记钩子、安装 `(rnrs …)` 与 psyntax 库。
2. 跑 R6RS 冒烟测试（`(import (rnrs))` 下的常用操作、`syntax-case` 宏、`eval`）。
3. 把 nanopass 子模块目录加入库搜索路径，`(import (nanopass))`，跑通研究笔记 `nanopass.md` §8 的 `remove-when` 与 `to-cil` 示例。
4. nanopass 需要而运行时或 stage0 缺失的功能（iron-002 的清单），逐项补齐；适配文件的修改放在子模块之外。
5. 记录耗时：种子执行时间、nanopass 加载时间。

## 验收标准
- 两个 nanopass 示例在 stage0 上的输出与 Chez 上一致。
- 补齐与修改的清单记录在本任务文件末尾。

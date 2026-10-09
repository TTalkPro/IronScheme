# iron-045 std：持久数据结构

- 里程碑：M9　依赖：iron-041　状态：未开始
- 设计依据：[08](../designs/08-std-library.md) §1 D1、§2

## 工作内容
`(ironscheme std persistent …)`：pfds 的 queues、deques、bbtrees（sorted-maps）、sets、dlists（difference-lists）、psqs（priority-search-queues）、fingertrees（finger-trees）、sequences、heaps、hamts（hash-maps），以及 `:101`（random-access-lists，冲突名加 `ra-`）、`:116`（lists）。测试由 pfds 的 `tests.scm` 与 SRFI 测试改写。

## 验收标准
- pfds 原测试（255 项）改写后全部通过；D2 守卫通过。

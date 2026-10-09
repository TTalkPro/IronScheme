# iron-044 std：惰性序列、记录、时间、测试等

- 里程碑：M9　依赖：iron-041　状态：未开始
- 设计依据：[08](../designs/08-std-library.md) §2、§3

## 工作内容
`streams`（:41）、`lazy-sequences`（:127）、`generators`（:158，从 Chez 实现移植）、`comprehensions`（:42）、`records`（:99）、`conditions`（:35）、`time`（:19）、`random`（:27）、`testing`（:64 :78）、`regexp`（:115）、`args`（:37）、`system`（:98 :112）、`localization`（:29）、`format`（:54）、`ports`（:6 :38）、`queues`（:117），各带测试。

## 验收标准
- 原 SRFI 测试中对应部分全部通过；D2 守卫通过。

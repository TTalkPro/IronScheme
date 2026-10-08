# iron-031 R6RS 测试与系统库编译达标

- 里程碑：M6　依赖：iron-030　状态：未开始
- 设计依据：[06](../designs/06-r6rs-and-testing.md)

## 目标
新系统在符合性测试与系统库编译上达到 iron-001 记录的基线。

## 工作内容
1. `IronScheme.Tests` 改为 net10.0，宿主换成 `IronScheme.Host`。
2. 运行 `tests/r6rs/run.sps`、`trigtest.sps`、`clisp-number-tests.sps`、`fp-test.sps`，与基线逐项对比。
3. `compile-system-libraries`：全部库编译成 dll 并可独立加载（含 srfi、pfds）。
4. 对每个新增失败定位到运行时、编译器或发射器并修复；确属 call/cc 偏离的，记入 06 §1。

## 验收标准
- 失败数不超过基线；系统库数量与基线一致。

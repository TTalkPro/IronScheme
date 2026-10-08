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

## 从 iron-010 转来

- `eqv?` 对 `0.0` 与 `-0.0` 返回 `#t`（旧系统与新运行时均如此：`IsEqualValue` 用 `Equals`，而 .NET 的 `double.Equals(0.0, -0.0)` 为真）。R6RS 要求返回 `#f`。
- 旧打印器把 `-0.0` 写成 `0.0`，把名为 `|` 的符号写成裸 `|`（无法读回）：打印器在 Scheme 中（`build/generic-writer.sls`），按需修正。

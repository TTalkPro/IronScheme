# 06 R6RS 符合性与测试

## 1. 符合性范围

保留 psyntax 与现有 R6RS 库实现，目标是**不低于现状**的符合程度。

### 明确的偏离

| 项 | 现状 | 新系统 |
|---|---|---|
| `call/cc` | 逃逸续延（异常实现） | 相同；续延失效后调用给出明确错误（02 §6） |
| 重入、多次进入续延 | 不支持 | 不支持 |
| `dynamic-wind` | try/finally | 相同；没有重入，`before` 只在进入时执行一次 |
| `guard` 无匹配时的再抛出 | 在 guard 的动态环境中 `raise-continuable` | 相同（psyntax 不改） |
| try/finally 区域内的尾调用 | 不是真尾调用 | 相同（CIL 限制，03 §5） |
| 记录作为 CLR 类型 | 支持 | **不支持**（02 §7） |
| FFI（`ffi-callout`、`ffi-callback`、`pinvoke-call`）与 `define-clr-class` | 支持 | 暂不支持：编译为运行时报"尚不支持"（`Calls.Unsupported`），相关库仍可编译、加载 |
| 调试器（`(ironscheme debugger)` 的 `step-into`） | 依赖 DLR 调试设施 | 保留导出，调用时报不支持（02 §10） |

### 必须保持的

- **真尾调用**：除 try 区域外，所有尾位置调用不增长栈（03 §5）。
- 数值塔（含 bignum、有理数、复数、精确/非精确）、Unicode、字节向量、哈希表、枚举、条件与异常、端口、`eval` 与 `environment`、`syntax-case`。

## 2. 测试分层

| 层 | 内容 | 何时建立 |
|---|---|---|
| 运行时单元测试 | `IronScheme.Core`：符号驻留、过程分派与参数个数错误、逃逸续延、记录、fasl 往返、reader | M1 |
| stage0 测试 | 手写 Lcore 小程序；执行文本种子后的 R6RS 冒烟测试；nanopass 示例 | M2 |
| 发射器测试 | 手写 Lcil → dll → 运行；互操作决议；常量；try/finally；`tail.` 深递归 | M3 |
| pass 快照测试 | 典型 Lcore 输入每个 pass 后的 `unparse` 输出 | M4 |
| 单库编译 | 用新编译器编译 `build/` 中的单个库并加载运行 | M4 |
| 自举 | Phase A（stage0）产出 stage1；Phase B stage2 == stage3 | M5、M6 |
| R6RS 符合性 | `tests/r6rs/run.sps`、`trigtest.sps`、`clisp-number-tests.sps`、`fp-test.sps` | M6 |
| 系统库 | `compile-system-libraries` 全部成功，dll 可独立加载 | M6 |

## 3. 验收基线

iron-001 已用旧系统实测（2026-10-08，.NET 10，`DOTNET_ROLL_FORWARD=Major`），结果与 `IronScheme.Tests` 中的期望完全一致：

| 测试 | 当前期望（来自 `IronScheme.Tests`） | 新系统要求 |
|---|---|---|
| `tests/r6rs/run.sps` | 3 of 8971 failed | 失败数不增加 |
| `tests/trigtest.sps` | Failed 8 of 17707 | 不增加 |
| `tests/clisp-number-tests.sps` | Failed 3 of 2476 | 不增加 |
| `tests/fp-test.sps` | 无输出 | 无输出 |
| 系统库编译 | 232 个（含 srfi、pfds） | 数量相同 |
| 自举 | 两遍 + IL 校验 | 不动点 + ILVerify |

iron-031 实测（新宿主 + 新 boot）：R6RS 为 3 of **8973** failed——同样的 3 项；多出的 2 项是 `(unless (eqv? 0.0 -0.0) …)` 保护的用例，`eqv?` 区分 `±0.0` 后开始运行并通过。其余各项与基线相同，232 个系统库全部通过 ILVerify。

## 4. 运行方式

- 测试仍按"每个测试一个进程"的方式运行（现有 `TestRunner.cs`），宿主换成 `IronScheme.Host`。
- `IronScheme.Tests` 改为 net10.0。
- `tests/windtests.sps`（含重入用例）继续不纳入。

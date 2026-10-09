# iron-041 std 基础：目录、约定与语法类库

- 里程碑：M9　依赖：iron-040　状态：完成
- 设计依据：[08](../designs/08-std-library.md) §1、§5

## 目标
建立 `(ironscheme std …)` 的目录、许可证与测试约定，完成基础库 promise 改造（D7）与第一批库。

## 工作内容
1. `src/scheme/lib/ironscheme/std/`、`LICENSES/`；测试脚本目录 `src/scheme/tests/std/` 与测试类别 `Std`；检查 D2 的守卫脚本（每个 std 库与 `(ironscheme)` 无冲突、无转导出）。
2. 基础库 `delay`/`force` 改为迭代强制（SRFI-45 / R7RS 语义），重建 boot。
3. 库：`syntax` `procedures` `boxes` `lazy`，各带测试。

## 验收标准
- 新库测试通过、D2 守卫通过、全部原有测试通过。

## 结论（2026-10-09）

完成。

**目录与约定**
- 库在 `src/scheme/lib/ironscheme/std/`，许可证全文在 `std/LICENSES/`（`chez-srfi.txt`；`pfds.txt` 供 iron-045 使用）。每个库的文件头写明出处（SRFI 号、作者）、与 SRFI 文本不同的取舍、"你要的在 IronScheme 里叫什么"对照（D1、D2、D4）。
- 测试在 `src/scheme/tests/std/<库>.sps`。公共检查宏在 `tests/std/check.ss`（`check … => …`、`check-raises`、`check-report`），脚本以 `(include "tests/std/check.ss")` 引入；每个脚本最后打印 `名字: all passed (n checks)`。
- C# 测试类别 `Std`（`tests/IronScheme.Tests/StdTests.cs`）：自动发现 `tests/std/*.sps` 逐个运行。
- D2 守卫 `tests/std/check-std.sps`：列出 `std/` 下全部库（`private/`、`LICENSES/` 除外），逐个加载，确认其导出与 `(ironscheme)` 没有交集。这样同时排除了"同名不同义"和"转导出基础库已有名字"两种情况。

**基础库 promise（D7）**
- `boot/r5rs.sls`：promise 改为一个盒子 `(完成? . 值或 thunk)`，`force` 按 R7RS 参考实现迭代强制（共享盒子，相当于 `promise-update!`），长的 lazy 链不增长栈；`delay` 的语义不变。
- 新增 `make-lazy-promise`、`make-eager-promise`，在两份构建脚本的图例中登记到 `(ironscheme core)`；boot 已重建，种子已再生成，达到不动点。

**库**
| 库 | 内容 | 测试 |
|---|---|---|
| `syntax` | `cond-expand`（特性只有 `r6rs`、`ironscheme`、操作系统与体系结构，不声明 `srfi-N`）、`and-let*`、`receive`、`fluid-let`、`rec`、`assume`（总是检查） | 55 项 |
| `procedures` | `cut` `cute` `<>` `<...>`、`is` `isnt`、SRFI 51 的 rest-values 族、SRFI 102 的三个过程（基于基础库的 `procedure-arity`） | 58 项 |
| `boxes` | SRFI 111，即 R6RS 记录 | 6 项 |
| `lazy` | `lazy` `delay-force` `eager`（`delay`/`force` 在基础库） | 9 项，含百万层 lazy 链 |

**与原 SRFI 测试的对照（D8：原通过数是下限）**
- and-let*：原 36 项，std 36 项全部保留；
- cut：原 30 项，std 30 项（26 个用例 + 4 项 `<>`/`<...>` 的卫生性检查）；
- boxes：原 3 项，std 6 项；
- fluid-let：原测试在新系统上失败（依赖完整续延，新系统只支持逃逸续延），std 改用逃逸场景的测试，通过；
- rec、procedure-arity 原测试没有断言（只打印）；lazy 原测试是需要手动中断的内存泄漏测试，std 用百万层 lazy 链代替。

**验证**：完整测试 Core.Tests 229/229、IronScheme.Tests 62/62（含 Std 5 项）；check-std 全部通过。

**留给 iron-042**：参照实现大段并入时的兼容层 `(ironscheme std private compat)`（chez-srfi 的 `SRFI-23-error->R6RS`、`check-arg`、`vanish-define`）在第一个需要它的库（lists）中建立。

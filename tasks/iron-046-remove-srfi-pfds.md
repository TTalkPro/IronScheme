# iron-046 删除 srfi 与 pfds，迁移依赖方

- 里程碑：M9　依赖：iron-042 ~ iron-045　状态：完成
- 设计依据：[08](../designs/08-std-library.md) §1 D5、§4

## 工作内容
1. 依赖方改用 std：wak、`lib/diff.sls`、示例、测试脚本与 C# 测试。
2. 删除 `src/scheme/lib/srfi`、`lib/pfds`；`system-libraries.ss` 改为 std 清单；测试类别 `SRFI` 改为 `Std`；更新 `THIRD-PARTY.md`、README、设计文档。

## 验收标准
- 仓库中不再有 `(srfi …)`、`(pfds …)` 的引用；全部测试通过；系统库编译与 ILVerify 通过。

## 结论（2026-10-09）

完成。

**删除**：`src/scheme/lib/srfi`、`src/scheme/lib/pfds` 两个目录，以及 `system-libraries.srfi.ss`。`(srfi …)`、`(pfds …)` 库名不再提供，对照表见 08 §3。`lib/THIRD-PARTY.md` 改为记录 std 库所依据的 chez-srfi、pfds 上游版本（提交号不变），许可证全文在 `std/LICENSES/`。

**依赖方迁移**
| 依赖方 | 原来 | 改为 |
|---|---|---|
| `lib/diff.sls` | `(srfi :1)` `(srfi :8)` | std `lists`、`syntax` |
| `wak/foof-loop`、`foof-loop/nested` | `:1` `:8` `:45` | std `lists`、`syntax`、`lazy` |
| `wak/riastreams` | `:45` | std `lazy` + 基础库 `delay`/`force` |
| `wak/trc-testing`、`restart`、`parameters`、`port-tracker` | `:8` `:9` `:13` `:39` | std `syntax`、`strings`，基础库 `make-parameter`/`parameterize`；SRFI 9 形式的记录（含 `private/test.scm`）改写为 R6RS 记录 |
| `wak/fmt`、`fmt/c` | `:1` `:6` `:13` `:69` | std `lists`、`strings`、`ports`，R6RS 散列表（SRFI 69 的三个过程在 fmt.sls 中按 R6RS 散列表定义，避免 SRFI 125 兼容名的废弃警告）；原依赖 SRFI 1 的谓词版 `remove` 以 `(rename (only (rnrs lists) remp) (remp remove))` 引入 |
| `lib/simple-regression-testing.sls` | `(srfi parameters)` `(srfi format)`（本就不存在，库无法加载） | 基础库 |
| 示例 WordCount | `(srfi :1 lists)` | `(ironscheme std lists)` |
| `system-libraries.ss` | 包含 srfi 清单与 pfds 一段 | 包含新的 `system-libraries.std.ss`（46 个 std 库） |
| `tests/repl-hooks.sps`、`LineEditorTests` | `(srfi :1 …)` 的补全 | `(ironscheme std li…)` |
| C# 测试 | `SRFITests.cs`（24 项）、Other 的 PFDS | 删除；由 Std 类别（`tests/std/*.sps`，47 个脚本）取代 |

**fmt 的验证**：迁移后用 SRFI 64 适配文件运行 fmt 自带测试。test-fmt-c 37/37，test-fmt-js 2/2；test-fmt 170 项中 157 项通过，失败的 13 项全部是 `fmt-columns`/`columnar`/`tabular`，它们靠重新进入续延实现，新系统只支持逃逸续延（与本任务无关）。

**整合四个并行分支时的处理**
- 两个分支各写了一份 SRFI 64 适配文件（`srfi64-shim.ss`、`check-64.ss`），合并为 `srfi64-shim.ss`（保留能显示测试名的实现）。
- Std 的 hashtables 在 C# 中失败：原 SRFI 126 测试打印的说明含 "XFAIL" 字样，被"输出不得含 FAIL"的判定误认；删去该说明。
- 分支跑原 SRFI 42 基线时在 `src/scheme` 留下的临时文件 `tmp1` 已删除。
- SystemLibraries 的库总数由 232 改为 125：其中 std 46 个、内部库 6 个，其余为 ironscheme 系统库、wak、minikanren 等（逐个核对过）。
- 08 设计按各分支的建议补充了 §1 内部库名单、§2 各库说明、D8 的测试公共文件。

**验证**：47 个 std 测试脚本全部通过；完整测试 Core.Tests 229/229；IronScheme.Tests 80 项中，SystemLibraries 两项因库总数常数未更新而失败，更新后 2/2 通过，其余全部通过。

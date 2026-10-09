# iron-056 boot 与 std 去 `clr-*`

- 里程碑：后续　依赖：无（与 iron-050 ~ 053 独立）　状态：未开始
- 设计依据：[11 §1](../designs/11-portability.md) D2、D3、D5

## 目标
语言核心（`boot/`）与标准库（`lib/ironscheme/std/`）不再直接使用 `(ironscheme clr)`，宿主功能全部经过 C# 原语。原语表因此成为完整的宿主接口；顺带把这些调用变成可带 `pure` / 内联模板的原语调用。

## 工作内容
1. **盘点**：按文件统计 `clr-call` / `clr-static-call` / `clr-new` / `clr-is` / `clr-cast` / `clr-prop-get` 等的使用（当前约 1000 处、28 个 boot 文件 + 6 个 std 文件），按"同一个 .NET 成员"归并，得到需要新增的原语清单。
2. **分批改写**，每批一个任务提交单元，顺序：`io/ports`（145）→ `bytevectors`（63）→ `numbers`（43）→ `hashtables`（31）→ `base`（28）→ 其余 boot 文件 → std 的 6 个文件。每处 `(clr-call X M a …)` 改为原语调用 `($x-m a …)`；原语在 `IronScheme.Core` 对应的文件里用 `[Primitive]` 实现，命名跟随现有 `$` 前缀的内部原语惯例；能标 `pure` 的标上。
3. **宿主侦测原语**（D5）：`host-type`、`host-version`、`machine-type` 作为 `(ironscheme)` 的导出，C# 原语实现（`machine-type` 由 `$host-type`、`$cpu-architecture`、`$os-name` 在 boot 里拼成）；`(ironscheme std system)` 的 `cpu-architecture` / `os-name` / `os-version` / `machine-name` 与 `(ironscheme std syntax)` 的 `cond-expand` 特性改为调用这些原语，std 批次由此不再有 `clr-*`。
4. **互操作形式只留给平台库**：改写完成后 `boot/` 与 `std/` 不再导入 `(ironscheme clr)`（`(boot exceptions)` 等的 `clr-using` 也一并去掉）；`(ironscheme clr)` 本身仍是用户可用的库。
5. 每批重新生成 `primitives.ss`、重新生成文本种子（`dotnet run tools/build.cs -- seed`），跑自举不动点。
6. 更新 [02 §5](../designs/02-runtime.md)（原语表是宿主契约）与 [11 §0](../designs/11-portability.md) 的分布表。

## 验收标准
- `grep -rE "\(clr-" src/scheme/boot src/scheme/lib/ironscheme/std` 为空（`clr.sls` 自身与平台库不算）。
- `(host-type)` 返回 `clr`，`(machine-type)` 在本机返回 `clr-x86-64-linux` 这样的符号，`cond-expand` 的 `clr` 特性成立。
- 全部测试通过；自举 stage1 / stage2 / stage3 字节相同；系统库编译与 ILVerify 通过。
- 编译整个种子的统计输出与性能基线不劣化（`io/ports` 一批做完后跑一次 I/O 基准，原语调用应略快于 `clr-call`）。

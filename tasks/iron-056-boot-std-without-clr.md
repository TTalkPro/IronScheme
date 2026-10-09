# iron-056 boot 与 std 去 `clr-*`

- 里程碑：后续　依赖：无（与 iron-050 ~ 053 独立）　状态：完成
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

## 结论
- 盘点：实际约 580 处（原估计 1000 是按行数算的），去重后约 300 个不同的 .NET 成员；最多的是 `clr-static-call`（191）、`clr-is`（99）、`clr-prop-get` / `clr-call`（各 68）。
- 新原语：`R6RS/PortPrimitives.cs`（`$port-*`，60 个：端口的谓词、打开关闭、位置、读写、转码器、自定义端口）、`Reader/Annotation.cs`（`$annotation-*`）、`Runtime/HostPrimitives.cs`（约 165 个：宿主侦测 `host-type` / `host-version` / `machine-type` / `$os-name` / `$cpu-architecture`，类型谓词，字符与字符串，向量、表与散列表，字节向量的编解码与整数 / 浮点转换，大整数、有理数、复数与数学函数，记录描述符与过程信息，文件与路径，信号量、线程、时区与区域）。全部 `$` 原语登记在两个构建脚本的 `(ironscheme unsafe)` 表里，`primitives.ss` 已重新生成（454 项）。
- 改写：28 个 boot 文件 + 6 个 std 文件全部改为原语调用；`clr-guard` 改成它的展开 `with-clr-exception-handler`（本来就是原语）；`boot/` 与 `std/` 不再导入 `(ironscheme clr)`，`clr-using` 全部删除。`grep -rE "\(clr-" boot std` 只剩 `predicates.sls` 导出的 `clr-string?` 与 `misc.sls` 导出的 `clr-type?` 两个**名字**（用户可见的谓词名沿用，实现已是原语）。
- 展开器的 `compat.sls` 与 `main.sls` 按 [05 §5](../designs/05-bootstrap.md) 的两步法改：先改其他文件、构建、生成种子，再改这两个文件、构建、再生成种子。种子最终又生成了一次（去掉了 6 个无用的 `(ironscheme clr)` 导入之后）。
- 两处实测修正：`$uint->bytes` / `$sint->bytes` 对超过 64 位有符号范围的大整数要经十进制文本转换（IntX 没有到 ulong 的转换）；`$string-normalize` 的形式符号沿用旧写法 `FormC` 等，也接受 `nfc` 等。
- `(ironscheme std syntax)` 的 `cond-expand` 特性改由 `$os-name` / `$cpu-architecture` 给出，并新增 `clr` 特性（11 D4）；`(ironscheme std system)` 的 `cpu-architecture` / `os-name` / `machine-name` / `os-description` 都是原语的薄包装。
- 验收：`grep -rE "\(clr-" boot std` 只剩两个谓词名；Core.Tests 254 项、整套 `IronScheme.Tests` 84 项（含用重新生成的种子做的自举不动点、126 个系统库编译与 ILVerify、发布）全部通过；I/O 没有做单独的基准（原语调用与原来经发射器静态决议的 `clr-call` 生成的都是直接 `call`，没有理由变慢）。

# iron-047 Scheme 源码树整理

- 里程碑：M8　依赖：iron-035　状态：完成
- 设计依据：[07 §1](../designs/07-tooling-and-embedding.md)

## 目标
参照 Chez Scheme（`s/` 按 boot 文件组织、内置库由声明合成、测试在 `mats/`），让 `src/scheme/` 的目录按用途划分：编进 boot 镜像的、按需加载的、测试，各在一处；删除无人使用的草稿代码。

## 工作内容
1. 删除 `playground/`（上游作者的试验代码，不参与构建，无测试）及唯一依赖它、且未被运行的 `tests/source-optimizer.sps`。
2. `build/` 改名为 `boot/`；`psyntax/` 移到 `boot/psyntax/`；`boot-seed.core`、两份构建脚本移到 `boot/`；boot 镜像的输出目录随之改为 `boot/`。
3. `compiler/primitives.ss` 移到 `boot/primitives.ss`；`compiler/tests/` 移到 `tests/compiler/`；删除 `compiler/`。
4. boot 内部模块统一命名为 `(boot …)`，与路径一一对应；展开器目录 `boot/psyntax/` 改为 `boot/expander/`，库名不再用 `(psyntax …)`（用户追加）。
5. 更新构建脚本、MSBuild 目标、宿主、`tools/build.cs`、测试、`.gitignore`、README 与设计文档中的路径；重新生成种子并确认两种生成方式产物相同。

## 验收标准
- `dotnet build`、`dotnet test` 全部通过；`seed` 与 `seed --stage0` 产物逐字节相同。

## 结论（2026-10-09）

完成，布局与理由见 07 §1。

**调整后的 `src/scheme/`**
- `boot/`：原 `build/` 的核心库、`boot/psyntax/`、`primitives.ss`、`boot-seed.core`、`ironscheme-buildscript-nano.sps`、`seed-buildscript.sps`，以及生成的 `ironscheme.boot.{dll,lcil}`（`.gitignore` 同步修改）；
- `lib/`：未变。编译器 `(ironscheme compiler …)` 留在这里，因为构建时它与 nanopass 一样按库名从库搜索路径找到；它虽编进镜像，但不作为已安装的库，运行时导入仍从源码加载（已核实）；
- `tests/compiler/`：原 `compiler/tests/`；`compiler/` 目录删除；
- 删除 `playground/` 与依赖它、未被任何测试运行的 `tests/source-optimizer.sps`；从 08 §4 与 iron-046 中去掉对它的迁移。

**`(ironscheme files)` 同名问题**
- 核实后发现：boot 源码中的库名只在构建期间使用，对外可见的库由构建脚本的图例合成（相当于 Chez 的 `primdata.ss`）。因此 `build/files.sls` 从未作为 `(ironscheme files)` 安装，用户导入的一直是 `lib/ironscheme/files.sls`。两者只是同名，并非两份定义同时生效；
- 随下面的统一改名成为 `(boot files)`，同名消除。`file-exists?`、`delete-file`、`file-mtime` 仍经图例由 `(rnrs files)`、`(ironscheme)` 导出。

**库名统一为 `(boot …)`（用户追加）**
- 31 个核心模块 `(ironscheme X …)` → `(boot X …)`；展开器 `(psyntax expander)` → `(boot expander core)`（文件 `core.sls`），其余 `(psyntax Y)` → `(boot expander Y)`；图例内部库 `(psyntax system $all)`/`$bootstrap` → `(boot system all)`/`(boot system bootstrap)`，`null-environment-5`、`scheme-report-environment-5`、`primlocs` 同样移到 `(boot …)` 下。完整对照见 07 §1。
- 用户选的是 `(ironscheme boot …)`，实施时改为 `(boot …)`：构建脚本按库名从源码导入展开器，`(boot expander internal)` 经当前目录 `src/scheme` 正好找到 `boot/expander/internal.sls`；`(ironscheme boot …)` 需要 `ironscheme/boot/` 目录，与布局冲突。
- 构建脚本中的标识符 `psyntax-exports`、`psyntax-system-macros` 改为 `expander-…`；Scheme 源码、C# 注释与设计文档中的 “psyntax” 改称“展开器”（README 与 07 §1 保留出处说明，历史任务记录不改）。
- 过渡自举：旧镜像只有 `(psyntax system $bootstrap)`，而展开器源码改为导入 `(boot system bootstrap)`。先用一个临时转接库（以新名字重新导出旧库，放在临时目录，经 `-I` 加入）让旧镜像生成新种子；再由新种子经 stage0 构建新镜像；之后不用转接库，以新系统与 stage0 分别再生成种子，二者逐字节相同，用它重建镜像后再生成一次仍相同。转接库未留在仓库中。

**路径更新**：两份构建脚本的文件表、种子与输出路径，原语表的默认路径（`lib/ironscheme/compiler/primitives.sls`），`GenerateBootImage` 的输入与输出，宿主的镜像替换约定，`tools/build.cs`，测试（PrimitiveTable、Host、Stage0Script、Bootstrap、TestRunner），C# 注释，README，设计 02 ~ 08 中仍有效的路径（顺带修正了 iron-035 时漏改的 `Console/…` 路径）。已完成任务的记录保持原样。

**顺带修复**：完整测试中 Publish.StandaloneApplication 一次失败，查明是发布时 Emit 被以两种配置构建、并发写同一目录（与本任务无关，记入 iron-036 与 07 §3）；Emit 声明 `IsRidAgnostic=true`。

**验证**
- 种子按新路径再生成，`seed` 与 `seed --stage0` 产物逐字节相同；
- 目录调整后、库名统一后、修复 Emit 发布竞争后各跑一次完整测试，最后一次：Core.Tests 229/229，IronScheme.Tests 62/62；种子不动点保持。

# iron-040 srfi 与 pfds 纳入仓库

- 里程碑：M8　依赖：iron-035　状态：完成
- 设计依据：[07 §1](../designs/07-tooling-and-embedding.md)

## 目标
把 git 子模块 srfi（chez-srfi）与 pfds 的文件直接纳入本仓库，删除这两个子模块。

## 工作内容
1. 子模块目录改为普通目录；从 `.gitmodules`、`.git/config` 与 `.git/modules` 中移除。
2. 记录来源与提交；检查本仓库与库自带的 `.gitignore` 是否会漏掉文件。
3. 运行 SRFI、Other（PFDS）、SystemLibraries 测试。

## 验收标准
- 两个目录的全部文件可作为普通文件加入；相关测试通过。

## 结论（2026-10-09）

完成。

**处理**
- 删除 `src/scheme/lib/srfi`、`src/scheme/lib/pfds` 中指向子模块仓库的 `.git` 文件；
- 从 `.gitmodules` 删除两个条目，从 `.git/config` 删除对应配置节，删除 `.git/modules` 下这两个子模块的仓库数据；
- 顺带删除早已移除的 BuildTools 子模块（iron-032）残留在 `.git/config` 与 `.git/modules` 中的配置和数据；
- 新增 `src/scheme/lib/THIRD-PARTY.md`，记录来源仓库与纳入时的提交：
  - srfi：`6804f60f2acc319f5c5686da80b519ee56984ea0`
  - pfds：`7a945ce18cb70630d3140cdff4d33605c37f1273`

**文件检查**
- srfi 自带的 `.gitignore` 有一条 `and-let*.sls`，通配后会匹配上游实际跟踪的 `%3a2/and-let%2a.sls`，导致它在加入时被漏掉。因此删除该 `.gitignore`，同时删除对本仓库无效的上游 CI 配置 `.github/`。
- 用 `git add --dry-run` 确认：srfi 的 363 个文件（上游 365 个减去以上两项）与 pfds 的 36 个文件都会作为普通文件加入，其余文件未改动。
- nanopass 仍是子模块，克隆时仍需 `--recurse-submodules`。

**测试**：SRFI 24 项、Other（含 PFDS 自测 255/255、MiniKanren、FFI、ReplHooks）、SystemLibraries（232 个库，含 srfi 与 pfds）共 30 项全部通过。

**提交说明**：git 索引未改动。提交时用 `git add -A`，git 会删除旧路径上的两个子模块条目（gitlink），并把两个目录的文件作为普通文件加入。

# iron-035 目录结构调整

- 里程碑：M8　依赖：iron-032　状态：完成
- 设计依据：[07 §1](../designs/07-tooling-and-embedding.md)

## 目标
仓库改为 `src/`、`tests/`、`examples/` 布局，Scheme 源码树改名为 `src/scheme/`。

## 工作内容
1. 移动 C# 项目到 `src/`、测试项目到 `tests/`，`IronScheme/IronScheme.Console` 改为 `src/scheme/`；`Directory.Build.props`、`NuGet.config` 等移到根目录。
2. 子模块随目录移动：更新 `.gitmodules` 的 `path` 与 `.git/modules/*/config` 的 `worktree`（不改 git 索引）。
3. 更新解决方案、项目引用、MSBuild 目标、测试路径、`tools/build.cs`、CI、README、设计文档中的路径。

## 验收标准
- 根目录 `dotnet build` / `dotnet test` 全部通过；干净副本只运行 `dotnet test` 通过。

## 结论（2026-10-09）

完成。仓库布局见 07 §1：
- C# 项目在 `src/`（Core、Emit、Host、Stage0、PrimGen、Oyster.IntX），测试项目在 `tests/`；
- Scheme 源码树 `IronScheme/IronScheme.Console` 改为 `src/scheme/`；
- `Directory.Build.props`、`NuGet.config`、`.editorconfig`、`LICENSE.txt` 移到根目录；图标与 logo 移到 `assets/`；
- 空的 `Directory.Build.targets` 已删除；
- 解决方案 `IronScheme.slnx` 按 `/src/`、`/tests/` 分文件夹。

子模块：`.gitmodules` 的 `path` 改为 `src/scheme/lib/…`，名字不变。`.git/modules/…/config` 的 `worktree` 已同步，子模块中的 `.git` 文件因目录深度不变而无需修改。git 索引未改动，提交时需 `git add -A`，让 git 记录子模块与文件的新位置。

同步修改的路径：
- 项目引用；
- `IronScheme.Host.csproj` 的 boot 生成目标（`SchemeDir`）；
- 测试中的目录定位（`Paths.RepoDir`/`SrcDir`/`SchemeDir`，HostTests、Stage0ScriptTests、PrimitiveTableTests）；
- `tools/build.cs`、`.gitignore`、README，以及设计文档 02–05 中描述当前结构的路径。

00、01 描述旧系统，路径保持原样。

验证：根目录 `dotnet test` 通过，Core.Tests 210/210，IronScheme.Tests 40/40；干净副本（含子模块，无构建产物）只运行 `dotnet test` 也全部通过。

`IronScheme/` 目录下只剩用户的 IDE 目录 `.idea`。

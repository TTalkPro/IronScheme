# iron-032 删除 DLR、旧编译器与旧目标框架

- 里程碑：M7　依赖：iron-031　状态：未开始
- 设计依据：[00 §1、§2](../designs/00-overview.md)

## 目标
仓库只保留新系统，构建只依赖 .NET SDK。

## 工作内容
1. 删除 `Microsoft.Scripting`、`IronScheme.Closures`、`IronScheme.FrameworkPAL`、旧 `IronScheme` 运行时与编译器、旧 `IronScheme.Console` 宿主（或将其改名为新宿主）。
2. 删除 net20、netcoreapp2.1、net462 等目标与相关脚本（`build.cmd`、`test-netbefore9.sh`、`cov-*.cmd` 等按需保留或改写）。
3. BuildTools 子模块已在 2026-10-08 删除，`Directory.Build.props/targets` 中的导入已去掉；此处清理 `build.sh`、`build.cmd`、`clean.cmd` 及旧项目文件中残留的 BuildTools 引用，并删除 `legacy-stage0/`。
4. 更新 `build.sh`、`test.sh`、README 中的构建说明。

## 验收标准
- 全新克隆（含 srfi、pfds 子模块，不含 BuildTools）只用 .NET SDK 即可构建、自举并通过测试。

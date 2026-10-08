# iron-001 构建旧系统并记录测试基线

- 里程碑：M0　依赖：无　状态：完成
- 设计依据：[01 §1](../designs/01-current-state.md)、[05 §2](../designs/05-bootstrap.md)、[06 §3](../designs/06-r6rs-and-testing.md)

## 目标
得到可运行的旧 IronScheme（DLR 版）作为自举 stage0，并实测记录测试基线。

## 工作内容
1. 初始化三个子模块（`IronScheme.BuildTools`、`lib/srfi`、`lib/pfds`），只做 `git submodule update --init`，不提交。
2. 按 `IronScheme/build.sh` 在本机（.NET SDK 10）构建；记录遇到的问题与绕过办法（如 net20 引用程序集、net9 运行时前滚 `--roll-forward Major`）。
3. 运行 `test.sh`，记录 `tests/r6rs/run.sps`、`trigtest.sps`、`clisp-number-tests.sps`、`fp-test.sps`、自举测试、系统库数量的实际结果。
4. 记录 stage0 的启动命令（如 `dotnet --roll-forward Major IronScheme.ConsoleCore.dll`）。
5. 若构建失败且短期无法解决，评估备选 stage0（已发布的 IronScheme 二进制，见 05 §5）。

## 验收标准
- 能用旧系统运行 `ironscheme-buildscript.sps` 并生成新的 boot dll。
- 基线数字写回 `designs/06-r6rs-and-testing.md` §3。

## 结论（2026-10-08，本机 .NET SDK 10.0.401，只有 .NET 10 运行时）

### 构建方法

1. `git submodule update --init --recursive`：BuildTools 自己还有三个嵌套子模块（`cecil`、`gplex`、`gppg`），必须递归初始化。
2. `cd IronScheme && DOTNET_ROLL_FORWARD=Major sh build.sh`
   - BuildTools 里的 gplex/gppg 等工具是 net9 程序；本机只有 .NET 10 运行时，不设 `DOTNET_ROLL_FORWARD=Major` 时 gplex 以退出码 150 失败（找不到 9.0 运行时）。
   - 不需要修改任何文件。
3. 构建产物：`IronScheme/IronScheme.Console/bin/Release/net9.0/IronScheme.ConsoleCore.dll`。
4. 构建会生成未跟踪的 `IronScheme/IronScheme/Compiler/IronScheme.lex.cs`、`NumberLexer.lex.cs`、`IronScheme/Microsoft.Scripting/Bin/`，属正常产物。

### stage0（旧系统）运行方法

在 `bin/Release/net9.0/` 目录下：`DOTNET_ROLL_FORWARD=Major dotnet IronScheme.ConsoleCore.dll <脚本>`。

### 基线（实测，与 `IronScheme.Tests` 中的期望一致）

| 测试 | 结果 |
|---|---|
| `tests/r6rs/run.sps` | 3 of 8971 tests failed |
| `tests/trigtest.sps` | Failed 8 of 17707 tests |
| `tests/clisp-number-tests.sps` | Failed 3 of 2476 tests |
| `tests/fp-test.sps` | 无输出 |
| `compile-system-libraries.sps` | 232 个库，约 18 秒 |
| `ironscheme-buildscript.sps` | 成功，约 6 秒（展开约 3.4 秒 CPU，代码生成约 1.5 秒 CPU）；连续两遍均成功，产物 1,210,368 字节 |

未做：ILVerify（需全局安装 `dotnet-ilverify`，会改动用户环境，留待需要时再装）。

### 对后续任务的意义

- 旧系统可以作为第 0 步生成文本种子的工具（iron-015）。
- 展开 36 个 boot 源文件只需约 3 秒，第 0 步成本很低。

### 后续变更（2026-10-08）

按用户要求删除了 IronScheme.BuildTools 子模块（`git submodule deinit` + `git rm`，只暂存不提交），并去掉 `IronScheme/Directory.Build.props/targets` 中对它的导入。删除前已把构建产物保存到仓库根目录 `legacy-stage0/`（换回原始种子，附 README）。旧系统从此只能运行，不能重新构建。

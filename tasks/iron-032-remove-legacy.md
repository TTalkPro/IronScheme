# iron-032 删除 DLR、旧编译器与旧目标框架

- 里程碑：M7　依赖：iron-031　状态：完成
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

## 从 iron-031 转来

- FFI 与 `define-clr-class` 在新系统中未实现（06 §1）。删除旧系统前决定：按 iron-011 的运行时辅助（`Helpers.FFIConvertTo<T>` 等）或静态生成实现，或明确放弃并从 `lib/` 中移除相关库。
- 仓库仍跟踪旧格式的 `IronScheme.Console/ironscheme.boot.dll` 种子；新 boot 由 `tools/build-stage1.sh` 生成在 `build/`（已忽略）。删除旧系统时一并决定种子与 boot 的存放方式。

## 结论（2026-10-08）

仓库只保留新系统，构建、自举与测试只依赖 .NET SDK（10.0）。

删除：
- 旧项目：`Microsoft.Scripting`（DLR）、`IronScheme`（旧运行时与 C# 编译器）、`IronScheme.Closures`、`IronScheme.FrameworkPAL`、`IronScheme.Nuget`、`IronScheme.Tests.Extensions`、`IronSchemeCore.sln`、`IronScheme/tools/`（gplex 模板、旧 profiler）。
- 旧宿主：`IronScheme.Console` 中的 C# 项目文件、`Program.cs`、`Properties/`、运行时配置、ngen 脚本、旧格式的 `ironscheme.boot.dll` 与 `ironscheme-buildscript.sps`。`IronScheme.Console` 目录保留为 Scheme 源码树（`build/`、`psyntax/`、`lib/`、`tests/`、种子与构建脚本）。
- 旧脚本：`build.cmd`、`test.cmd`、`clean.cmd`、`bf.cmd`、`ci-artefact.cmd`、`cov-*.cmd`、`coverage.cmd`、`nuget.*`、`package.*`、`test-netbefore9.sh`；根目录 `appveyor.yml`。
- BuildTools 子模块（目录与 `.gitmodules` 条目；git 索引中的 gitlink 留待提交时 `git rm`）、`legacy-stage0/`、依赖旧系统的 `spikes/iron-010-reader-compare`、`tools/port-legacy-runtime.py`。
- 目标框架：`Oyster.IntX` 去掉 net20，全部项目只有 net10.0；`Directory.Build.props/targets` 去掉 BuildTools 相关内容。

种子：删除 `legacy-stage0/` 之前先确认新系统能自行再生成种子。`seed-buildscript.sps` 只需与 nano 构建脚本一样不把 `clr-call-internal`/`clr-cast-internal` 当原语取值，就能在新宿主（约 16 秒）和 stage0（约 40 秒）上运行。两者产物逐字节相同，两次生成也相同；用再生成的种子构建的 stage1 与原 stage1 逐字节相同。`tools/gen-seed.sh` 改为默认用新宿主，`--stage0` 用 stage0。种子已按当前源码再生成（05 §5、§8）。

FFI（转来事项）：选择实现。`ffi-callout-internal`、`ffi-callback-internal`、`pinvoke-call-internal` 改为运行时原语（`IronScheme.Core/Interop/Ffi.cs`）：
- 按签名生成委托类型，经 `Marshal` 调用或取函数指针；
- 表达式树生成参数与返回值的转换代码；
- `pinvoke-call` 首次调用时经 `NativeLibrary` 加载库。

编译器（parse）与 stage0 不再把它们当特殊形式；原语表已再生成。`(ironscheme ffi)` 的 `dlopen`/`dlsym`/`dlclose` 原先写死 kernel32，现改用 `NativeLibrary`，可跨平台。`define-clr-class` 明确不支持（06 §1，`lib/` 中无使用者）。新增 `tests/ffi-test.sps` 与测试 `Other.FFI`（macOS 上跳过，因 pinvoke 用例按 libc.so.6 / msvcrt 查找）。

顺带修正：
- `procedure-name` 原先用 `ToString` 得到 `#<procedure car>`，导致打印成 `#<procedure #<procedure car>>`；改用 `Procedure.Name`。
- `(ironscheme-build)` 改为加载 `ironscheme-buildscript-nano.sps`。
- `(ironscheme-test)` 先在当前目录找 `tests/r6rs/run.sps`，因为新宿主在 `IronScheme.Host/bin` 下。

构建说明：
- `IronScheme/build.sh`：编译 C# 项目，再运行 `tools/build-stage1.sh`。
- `IronScheme/test.sh`：先构建，再 `dotnet test IronSchemeNext.slnx`。
- `.github/workflows/build.yml`：改为 .NET 10，安装 ILVerify 后运行 `./test.sh`。
- README 的构建、运行、测试说明已重写。

验收：把受跟踪文件（含 srfi、pfds、nanopass 子模块）与新增文件复制到空目录（没有 BuildTools、`legacy-stage0/`、boot 镜像和任何构建产物），只运行 `./test.sh`，全部通过：IronScheme.Core.Tests 210/210，IronScheme.Tests 40/40（Bootstrap、Conformance、SRFI、Other、SystemLibraries；装有 ILVerify，无跳过），总耗时约 12 分钟。

## 后续变更（2026-10-09）

为了兼容 Windows，`IronScheme/build.sh`、`IronScheme/test.sh`、`tools/build-stage1.sh`、`tools/gen-seed.sh`、`tools/ilverify.sh` 合并为一个 .NET 10 单文件 C# 程序 `tools/build.cs`。用法是 `dotnet run tools/build.cs -- build|stage1|test|seed|ilverify`。它不依赖 shell，三个平台通用。

`.sh` 脚本已删除。随后又把日常构建并入 MSBuild，方法如下：
- 解决方案移到仓库根目录，即 `IronScheme.slnx`；`Directory.Solution.props` 让默认配置为 Release；
- `IronScheme.Host.csproj` 的 `GenerateBootImage` 目标运行 stage0，按输入增量生成 boot 镜像，并复制到输出目录。

因此 `dotnet build` / `dotnet test` 即可完成全部构建和测试，CI 也改为 `dotnet test`。`tools/build.cs` 只保留常规构建之外的命令：`stage1 <目录>`、`seed`、`ilverify`。测试中查找 ILVerify 时改用用户目录（Windows 上为 `ilverify.exe`），也可用环境变量 `ILVERIFY` 指定。原先按 `$HOME` 查找，在 Windows 上 ILVerify 用例会被跳过。

两个测试项目对 `IronScheme.Host` 加了只影响构建顺序的引用（`ReferenceOutputAssembly="false"`）。原因：`dotnet test` 只构建测试项目及其引用，不加引用时干净目录里不会生成 boot 镜像。

验证：干净副本（无 boot 镜像与构建产物）在根目录只运行 `dotnet test`，Core.Tests 210/210，IronScheme.Tests 40/40。

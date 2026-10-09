# 07 工程结构、编译产物、发布、REPL 与嵌入

M8 的设计：在自举闭合、旧系统删除之后，补齐日常使用所需的工程能力。不涉及 NativeAOT（运行时没有 JIT，`eval` 与宏展开需要即时编译，见 00 §2 非目标）。

## 1. 目录结构（iron-035、iron-047）

```
IronScheme.slnx                 解决方案（Directory.Solution.props：默认 Release）
Directory.Build.props           全部项目共用（NoWarn 等）
src/
  IronScheme.Core/  IronScheme.Emit/  IronScheme.Hosting/  IronScheme.Host/
  IronScheme.Stage0/  IronScheme.PrimGen/
  scheme/                       Scheme 源码树（原 IronScheme/IronScheme.Console）
      boot/                     编进 boot 镜像的一切（见下）
      lib/                      按需加载的库：ironscheme/*（含编译器）、第三方、nanopass 子模块
      tests/                    Scheme 测试脚本：compiler/、std/、r6rs/ …
      examples/  docs/
tests/
  IronScheme.Core.Tests/  IronScheme.Tests/
examples/
  WebServer/                    嵌入示例（§5）
tools/build.cs                  常规构建之外的命令（05 §5、本文 §3）
designs/  tasks/  spikes/
```

- `scheme/` 是"运行时的工作目录"：宿主默认从这里找 `lib/`、`boot/ironscheme.boot.dll`，测试也以它为当前目录。
- `src/scheme/` 的划分参照 Chez Scheme（iron-047）：Chez 的 `s/` 按 boot 文件组织源码，`(rnrs …)`、`(chezscheme)` 由 `primdata.ss` 的声明合成而没有库源文件，测试在 `mats/`。对应地：
  - `boot/`：boot 镜像的源码与产物。核心库（列表、数值、端口、记录等，原 `build/`）、展开器 `boot/expander/`（原 `psyntax/`，见下）、原语表 `primitives.ss`（PrimGen 生成，原 `compiler/primitives.ss`）、文本种子 `boot-seed.core`、两份构建脚本，以及生成的 `ironscheme.boot.{dll,lcil}`（不跟踪）。这里的库名只在构建期间使用：对外可见的库由构建脚本的图例（`library-legend` 与 `identifier->library-map`）合成，作用同 Chez 的 `primdata.ss`。boot 内部模块一律命名为 `(boot …)`，与文件路径一一对应（`boot/lists.sls` 是 `(boot lists)`，`boot/io/ports.sls` 是 `(boot io ports)`，`boot/expander/core.sls` 是 `(boot expander core)`），不会与 `lib/` 中的库同名。构建脚本按库名导入展开器的源码副本时，`(boot expander internal)` 经库搜索路径中的当前目录（`src/scheme`）找到 `boot/expander/internal.sls`；若用 `(ironscheme boot …)` 则要求目录为 `ironscheme/boot/`，与布局冲突，所以不加 `ironscheme` 前缀。
  - 展开器源自 Ghuloum 的 psyntax（Ikarus 的可移植 R6RS 展开器，名字取自 Dybvig 等人为 Chez 写的 `psyntax.ss`），原库名 `(psyntax …)`，iron-047 改名：`(psyntax expander)` → `(boot expander core)`，`compat`、`internal`、`library-manager`、`builders`、`main` → `(boot expander 同名)`；图例合成的内部库 `(psyntax system $all)`、`(psyntax system $bootstrap)` → `(boot system all)`、`(boot system bootstrap)`，`(psyntax null-environment-5)`、`(psyntax scheme-report-environment-5)`、`(psyntax primlocs)` → `(boot …)` 同名。
  - `lib/`：运行时按库名从库搜索路径加载。编译器 `(ironscheme compiler …)` 也在这里：构建 boot 时同样按库名找到它与 nanopass，编进镜像，但不作为已安装的库，运行时导入它仍从源码加载。
  - `tests/compiler/`：编译器测试与快照（原 `compiler/tests/`），由 stage0 运行（Stage0ScriptTests）。
  - 上游的试验代码 `playground/` 已删除（不参与构建、无测试）。
- 子模块随 `scheme/lib/` 移动；`.gitmodules` 中子模块的名字不变，只改 `path`。srfi 与 pfds 在 iron-040 中改为普通目录，iron-046 改写进 `(ironscheme std …)` 后删除（来源与提交见 `src/scheme/lib/THIRD-PARTY.md`）；只有 nanopass 仍是子模块。

## 2. compile-file 与 .fasl（iron-037）

照 Chez 的接口，把源文件编译成可直接加载的编译产物，扩展名 `.fasl`。文件内容是一个 .NET 程序集（与 `compile-library` 生成的 dll 同一格式，04 §6），只是用 `.fasl` 命名。

| 过程 | 作用 |
|---|---|
| `(compile-file "a.ss" ["a.fasl"])` | 文件以 `library` 形式开头时同 `compile-library`，否则同 `compile-program`（与 `load` 对源文件的处理一致：`load` 的文件是以 `(import …)` 开头的顶层程序，程序体中可以有 `library` 形式） |
| `(compile-library "a.sls" ["a.fasl"])` | 编译库文件；加载时安装其中的库 |
| `(compile-program "a.sps" ["a.fasl"])` | 编译 R6RS 顶层程序；加载即运行 |
| `(load "a.fasl")` | 按扩展名识别编译产物并执行；`.ss`/`.sls`/`.sps` 仍按源码加载 |
| `IronScheme.Host a.fasl 参数…` | 宿主直接运行编译后的程序 |

- 默认输出文件名为源文件名换成 `.fasl`。
- 库的查找：导入库时，若源文件旁有同名 `.fasl` 且不比源文件旧，加载 `.fasl`（与 Chez 的 compiled-file 行为一致）。原有的 `compile-system-libraries`（dll 与 `compiled.lst`）保持不变。
- 编译产物的入口返回 `(ironscheme-fasl 1 libraries (库描述 …))` 或 `(ironscheme-fasl 1 program ((id 名字) …) thunk)`。库描述与 `compile-system-libraries` 的库 dll 相同（13 元素），加载时经 `try-load-from-file` 核对依赖库 id 后安装。程序加载时逐个核对依赖库的 id，再调用 thunk。
- 依赖库的编译实例：库从源码重新展开时位置符号与 id 都会变，引用它的编译产物随之失效（与 Chez 相同，报"requires a different compilation of a library"）。`(compile-imported-libraries #t)` 时，编译期间从源码加载的库也编译为各自源文件旁的 `.fasl`，之后导入时使用它们，id 保持不变。
- `.fasl` 按字节加载（原语 `load-fasl`）：不锁文件，每次加载在独立的加载上下文中，同名程序集不冲突。
- 内部生成库 dll 的驱动由 `compile-library` 改名为 `compile-library-dll`（`(ironscheme core)`），名字让给 Chez 接口。

## 3. 自包含发布（iron-036）

`dotnet run tools/build.cs -- publish [app.sps] [-r RID] [-o 目录] [-n 名字] [-I 库目录]…`：自包含、单文件发布（`PublishSingleFile`、`SelfContained`），目标机器不需要安装 .NET。默认 RID 为当前平台，默认输出 `artifacts/publish/<名字>-<RID>/`。

- **发布宿主**（不带 `app.sps`）：可执行文件 `IronScheme.Host`。boot 镜像作为嵌入资源 `ironscheme.boot.dll` 编入（宿主项目的属性 `EmbedBootImage=true`）；`lib/` 作为目录放在可执行文件旁（`ExcludeFromSingleFile`）。可运行脚本、REPL，也可以 `compile-library` 等。
- **发布应用**（带 `app.sps`）：
  1. 先在新宿主上运行 `(compile-whole-program "app.sps" 目录)`：程序展开期间从源码加载的每个库编译为一个 `libN.fasl`（按安装顺序，依赖在前），程序编译为 `program.fasl`，清单 `ironscheme.app` 每行 `library 文件` 或 `program 文件`。展开时不使用已有的编译产物，保证每个库都从源码展开、都能序列化。
  2. 发布宿主时把这些文件作为嵌入资源（属性 `IronSchemeApp=目录`），可执行文件名改为应用名（`IronSchemeAppName`），不带 `lib/`。为此用单独的中间与输出目录，不影响常规构建。
  3. 可执行文件启动时发现嵌入的清单，进入应用模式：按清单把各 `.fasl` 按字节加载，经展开器的钩子 `load-fasl-content` 安装库、运行程序。参数原样作为 `(command-line)`，条件导致退出码 1。
- **boot 镜像的来源**：命令行 `--boot`；否则可执行文件旁的 `ironscheme.boot.dll`；再否则入口程序集的嵌入资源（`SchemeRuntime` 按字节加载）。单文件中程序集没有文件位置，`Builtins.ApplicationDirectory` 改用 `AppContext.BaseDirectory`。
- **不裁剪**（trimming）：互操作的运行时决议依赖反射元数据。
- 同一次发布中，每个被引用的项目只能有一种构建配置，否则会并发写同一输出目录：宿主的中间与输出目录在 `IronScheme.Host.csproj` 中按 `IronSchemeAppName` 设置（不作为全局属性传入）；`IronScheme.Emit` 是可执行项目，声明 `IsRidAgnostic=true`，宿主与 IronScheme.Hosting 才会按同一配置构建它。
- 在测试等输出被重定向的场合，`tools/build.cs` 给 `dotnet build`/`publish` 加 `-nodeReuse:false`：常驻的 MSBuild 节点会继承输出管道，调用方等不到输出结束。

## 4. REPL（iron-038）

宿主的交互输入改为自己实现的行编辑器（只用 `System.Console`，Windows / Linux / macOS 通用）；标准输入被重定向时退回现有的逐行读取，保证测试与管道使用不变。

| 功能 | 说明 |
|---|---|
| 行编辑 | 左右移动、Home/End、Backspace/Delete、Ctrl+A/E/K/U/W、Ctrl+左右按词移动 |
| 多行输入 | 括号未闭合时回车换行继续输入（续行提示 `. `），闭合后求值 |
| 历史 | 上下键浏览；保存到用户目录 `.ironscheme_history` |
| 补全 | Tab：当前词为前缀补全交互环境中绑定的名字（含宏与语法关键字）；在 `(import …)` 中补全库名（来自已安装库与 `lib/` 下的文件）；多个候选时第一次补全公共前缀，再按一次列出候选 |
| 提示 | 光标位于 `(名字 ` 之后且在行尾时，在同一行末尾以暗色显示该过程各子句的形参（多于两个子句时显示首尾两个）。形参来自 `procedure-form`：编译器为每个过程类生成 `get_Form`（各子句的 `(名字 . 形参)`，形参名由展开器的 gensym 还原），C# 原语取方法的参数名；都没有时按 `procedure-arity` 显示 `_`。语法关键字不提示 |
| 括号匹配 | 输入右括号时短暂高亮与之匹配的左括号 |

补全与提示所需的信息由 Scheme 侧提供：`(boot expander main)` 登记 `repl-complete`（交互环境的名字；库名来自已安装的库与库搜索路径下的 `.sls` 文件）和 `repl-describe`（参数提示），宿主经符号值槽调用，不在 C# 中重复实现环境查询。

光标定位：Unix 终端上不查询光标位置。查询要与终端往返；有的伪终端不回应，等待回应时会吞掉按键。编辑器记录光标相对当前输入行起点的行列，用 ANSI 相对移动（`ESC[nA/B/C`、回车）定位，用 `ESC[J` 清除残留，终端滚动不影响它。Windows 控制台的光标查询是本地 API 调用，用 `SetCursorPosition` 绝对定位。终端不支持所需控制时退回逐个读取数据。

## 5. 嵌入与示例（iron-039）

- 新库项目 `IronScheme.Hosting`（引用 Core 与 Emit），是 C# 程序嵌入 IronScheme 的入口：
  - `SchemeRuntime.Initialize(选项)`：登记原语、加载 boot 镜像（路径或嵌入资源）、设置库搜索路径；
  - `Eval(string 代码)`、`Eval(string 代码, params string[] 导入库)`：在交互环境或指定导入下求值；
  - `Import(string 库名)`、`GetProcedure(string 库名, string 名字)`：取得库导出的过程，作为 `Procedure` 或强类型委托（`Func<…>`）调用；
  - Scheme 值与 C# 值的转换沿用 `Interop` 的规则（02 §9）。
  `IronScheme.Host` 改用它初始化。
  - `GetFunction<T>` 的委托经一层包装调用过程，引发的条件同样转为 `SchemeError`（其 `Message` 为 Scheme 打印器给出的条件描述）。
  - 线程：交互环境与展开器不是线程安全的，嵌入程序应串行调用（示例中用锁）。
  - 运行时文件：boot 镜像的生成目标（`GenerateBootImage`）在 `IronScheme.Hosting.csproj` 中，在复制输出之前执行；镜像与 `lib/ironscheme`（`(ironscheme clr)` 等不在 boot 中的系统库源码）作为内容项，随项目引用复制到宿主、示例等应用的输出目录。应用目录下的 `lib/` 总是加入库搜索路径。
- CLR 互操作边界的补充（iron-039 实现示例时发现，02 §9）：声明类型为 `object` 的返回值与字段值，按运行时类型把 Scheme 不直接使用的 CLR 数值类型（long、short、byte、uint、ulong、float 等）转为 Scheme 数；原先只转换声明为值类型的结果，且不转换 long 等，`ExecuteScalar` 返回的装箱 `Int64` 因此不是 Scheme 数。`clr-reference` 的简单名字在默认探测失败后，还在当前目录、库搜索路径与应用目录中查找 `名字.dll`。
- `examples/WebServer`：ASP.NET Core 最小 API（.NET SDK 自带的共享框架）。HTTP 路由在 C# 中，业务逻辑在 Scheme 库中（`examples/WebServer/scheme/`），C# 通过 `IronScheme.Hosting` 调用 Scheme 过程；Scheme 代码经 CLR 互操作直接使用 `Microsoft.Data.Sqlite`（NuGet 包）查询 SQLite 数据库，结果返回给 C# 序列化为 JSON。示例附带测试（类别 Examples）。

# 00 总体设计

## 1. 目标

1. **去掉 DLR**：删除 `IronScheme/Microsoft.Scripting`（旧 DLR 分支，程序集 `IronScheme.Scripting`，约 2.57 万行），以及建在它上面的 C# 编译器（`IronScheme/IronScheme/Compiler/`）。
2. **nanopass 直出 CIL**：编译器用 Scheme 写，基于 nanopass 框架，把展开器展开后的核心形式编译成 CIL。
3. **只依靠 .NET 自身自举**：不依赖 ClojureCLR、Chez 或任何外部语言实现；构建和自举只需要 .NET SDK。
4. **服务 R6RS**：保留展开器和 R6RS 标准库；**不支持完整 call/cc**（只提供逃逸续延，与现状一致）。

## 2. 约束与非目标

| 项 | 说明 |
|---|---|
| 工作约定 | 本仓库只开发、不提交（不做 git commit / push） |
| 构建命令 | 仓库根目录 `dotnet build` / `dotnet test`（`IronScheme.slnx`，`Directory.Solution.props` 默认 Release）。boot 镜像由 `IronScheme.Host.csproj` 的 `GenerateBootImage` 目标运行 stage0 增量生成（`-p:BuildBootImage=false` 跳过）。常规构建之外的命令在 `tools/build.cs`（.NET 10 单文件 C# 程序：`stage1 <目录>`、`seed`、`ilverify`）。Windows、Linux、macOS 通用，不依赖 shell |
| 目标框架 | 只保留一个现代目标：**net10.0**（本机 SDK 10.0.401、运行时 10.0.x）。放弃 net20、netcoreapp2.1、.NET Framework |
| 外部依赖 | 运行时只用 .NET BCL。nanopass 框架作为**第三方依赖**以 git 子模块引入（`nanopass-framework-scheme`，MIT 许可），属于编译器的构建依赖 |
| 非目标 | 完整 call/cc（可重入、多次进入）；`fmt-columns` 这类依赖重入的第三方代码；旧的嵌入 API（`RuntimeExtensions`）与 SuperConsole 的完整兼容；NativeAOT 下的 `eval` |
| 兼容性 | Scheme 源码（`boot/**/*.sls`、`lib/**`）尽量少改；需要改的主要是 `clr-using` 指向的命名空间与 DLR 类型名 |

## 3. 总体架构

```
                    ┌──────────────────────────────────────────────┐
  源码 (.sls/.sps)  │ 展开器（Scheme，沿用）                  │
        ──────────▶ │   expand → rewrite → 核心形式 Lcore（S 表达式） │
                    └───────────────────────┬──────────────────────┘
                                            ▼
                    ┌──────────────────────────────────────────────┐
                    │ nanopass 编译器（Scheme，新）                   │
                    │   parse-core → … → linearize                   │
                    │   输出：Lcil（文本 S 表达式，中立于宿主运行时）    │
                    └───────────────────────┬──────────────────────┘
                                            ▼
                    ┌──────────────────────────────────────────────┐
                    │ 发射器 IronScheme.Emit（C#，新）                 │
                    │   读 Lcil → Reflection.Emit                     │
                    │   内存程序集（eval）/ PersistedAssemblyBuilder（dll）│
                    └───────────────────────┬──────────────────────┘
                                            ▼
                    ┌──────────────────────────────────────────────┐
                    │ 运行时 IronScheme.Core（C#，新，无 DLR）          │
                    │   值、过程、符号值槽、数值塔、IO、记录、reader、宿主 │
                    └──────────────────────────────────────────────┘
```

## 4. 关键决策

| # | 决策 | 理由 | 详见 |
|---|---|---|---|
| D1 | 新建运行时程序集 `IronScheme.Core`（命名空间 `IronScheme.Core`），与旧运行时**并存**直到自举完成 | 旧系统在生成首个文本种子前仍要能构建运行；新旧互不引用，完成后整体删除旧项目 | 02 |
| D2 | 过程表示为 `Procedure` 抽象类的子类：每个 lambda 编译成一个类，自由变量是字段，按参数个数重写 `Invoke0..Invoke4` / `InvokeN` | 去掉 `CallTarget` 委托和 `CodeContext` 环境链；虚调用即可，不需要运行时生成委托 | 02 |
| D3 | 全局与库绑定使用**符号值槽**：`Symbol` 对象带 `Value` 字段，展开器的位置 gensym 的值就是该绑定 | 与展开器的 `symbol-value` 模型一致；无字典、无 `ModuleGlobalWrapper`；跨库无需静态链接 | 02 |
| D4 | 编译器输入固定为一个**显式文法 Lcore**（展开器 `rewrite` 的输出），编译期不读运行时状态 | 现有编译器靠全局表、`symbol-value`、执行内建函数做折叠，无法交叉编译 | 03 |
| D5 | 编译器输出**文本 Lcil**，由独立的 C# 发射器汇编 | 编译器（Scheme）与发射器（C#）解耦；stage0 解释器的内部对象不会混进产物；可 diff，便于验证不动点 | 04 |
| D6 | 常量用编译器自己定义的**中立编码**（含记录、gensym、共享结构），发射器转成二进制 fasl，运行时读回 | 取代 BinaryFormatter（.NET 9 起已移除）；可携带展开器语法对象 | 04 |
| D7 | 原语表是**数据文件**（由 `IronScheme.Core` 构建时用反射生成），编译器只读数据 | 编译结果只取决于输入，stage0 上与新系统上编译输出一致，才能比较不动点 | 03 |
| D8 | CLR 互操作成员（`clr-call` 等）的重载决议放在**发射器**里做，决议不了的落到运行时动态调用缓存 | 编译器保持纯函数；发射器手里有真实的 `Type` | 03、04 |
| D9 | 尾调用：自尾调用改写成循环；其余尾位置调用发射 CIL `tail.` 前缀（try 区域内除外） | R6RS 要求真尾调用；扩展器 `chi-body*` 等依赖深度尾递归 | 03、06 |
| D10 | call/cc 只做**逃逸续延**（异常实现，一次性、向上）；`dynamic-wind` 用 try/finally | 与现状一致；现有 boot 镜像和 `lib/ironscheme` 的用法全部是逃逸型 | 02、06 |
| D11 | 记录统一表示为 `Record`（RTD + 字段数组），**不再运行时生成 CLR 类型** | 现有 `Records.cs` 在运行时用 TypeBuilder 生成类型，依赖 DLR 代码生成；统一表示更简单 | 02 |
| D12 | reader 改为**手写 C# 递归下降**，取代 gplex/gppg | 生成的分析器代码不在仓库里，构建要靠 BuildTools 子模块；手写后构建只需 .NET SDK | 02 |
| D13 | C# 侧调用 Scheme 函数（`raise` 等）改为**运行时钩子**：boot 初始化时把过程登记到 `RuntimeHooks` | 取代手写 IL 胶水 `IronScheme.Glue.il` 对 `#::'库::名'` 方法名的硬编码 ABI | 02 |
| D14 | 自举 stage0 是**精简的 C# 核心形式解释器**（`IronScheme.Stage0`，跑在新运行时上），解释执行文本种子 `boot-seed.core`（boot 源码展开后的核心形式）来运行展开器、nanopass 与新编译器，编译出新 boot 镜像；之后新系统自己编译自己直到不动点。旧 IronScheme 只用于一次性生成文本种子 | 只依赖本仓库与 .NET；nanopass 不必在旧 DLR 系统上运行；种子是可审阅的文本 | 05 |
| D15 | nanopass 以 git 子模块引入，不复制源码 | 跟随上游（当时与 srfi、pfds 子模块做法一致；这两者自 iron-040 起直接纳入仓库，nanopass 仍是子模块） | 03 |

## 5. 里程碑

| 里程碑 | 内容 | 产出 |
|---|---|---|
| M0 准备与验证 | 构建旧系统、记录测试基线；以子模块引入 nanopass；验证 `tail.`、PersistedAssemblyBuilder | 基线数字、验证结论 |
| M1 新运行时 | `IronScheme.Core`：值、过程、符号、钩子、迁移运行时库、记录、手写 reader、互操作运行时、原语表生成 | 可单元测试的运行时 |
| M2 stage0 | boot 源码适配新运行时、确定性 gensym、旧系统生成文本种子、C# 核心形式解释器、在 stage0 上跑通展开器与 nanopass | 能运行 nanopass 的 stage0 |
| M3 Lcil 与发射器 | Lcil 规格、文本读取、Reflection.Emit 发射、常量编码、加载器 | 能把手写 Lcil 汇编成可运行的 dll |
| M4 编译器 | nanopass pass 链：Lcore → Lcil；编译驱动（在 stage0 上开发与运行） | 能编译单个库 |
| M5 首次自举 | stage0 运行新编译器生成新 boot 镜像；新控制台宿主 | 新系统首次启动 |
| M6 自举闭合 | 新系统编译自己到不动点；R6RS 测试与系统库编译达到基线 | 不动点、测试结果 |
| M7 清理与优化 | 删除 DLR、旧编译器、旧目标框架与 BuildTools 依赖；性能优化 | 只依赖 .NET 的仓库 |
| M8 工程与示例 | 目录结构、compile-file（.fasl）、自包含发布、REPL 行编辑与补全、嵌入 API 与 Web 服务器示例（07） | 可日常使用与嵌入 |

## 6. 主要风险

| 风险 | 影响 | 应对 |
|---|---|---|
| nanopass 在 stage0 上跑不通（iron-002 已验证其在旧 IronScheme 上无需修改即可运行，风险较低；剩余风险是适配文件按名字引用了旧运行时类型 `IronScheme.Runtime.Builtins`） | 编译器无法运行 | 在 stage0 与运行时中补齐 nanopass 所需的原语和语法；修补其 IronScheme 适配文件（以补丁形式维护，不改子模块内容） |
| stage0 解释执行展开器太慢 | 自举耗时过长 | 解释器先把核心形式分析成闭包树；种子与编译器只在自举时跑一次，可以接受分钟级 |
| 旧系统已无法重新构建（BuildTools 子模块已于 2026-10-08 删除） | 若 `legacy-stage0/` 丢失或损坏，无法生成首个文本种子 | 已解除：首个种子生成后，新系统与 stage0 都能再生成种子且达到不动点（05 §5）；M7 已删除 `legacy-stage0/` |
| .NET 上 `tail.` 前缀在某些签名下不被保证 | 深递归栈溢出 | iron-003 实测；必要时对未知尾调用退回蹦床 |
| 展开器语法对象等记录常量的 RTD 身份在重新加载后对不上 | 编译出的库加载后宏失效 | 常量编码按 RTD 名称与 uid 重建（04）；首次自举时专项验证 |
| 运行时与编译器同时重写，问题难定位 | 进度失控 | 分层验收：运行时单测 → 发射器单测 → 单个库 → boot 镜像；Lcil 文本可 diff |
| 性能退化（失去旧编译器的直接调用优化） | 自举与测试变慢 | 先保正确；M7 再做跨库直接调用与拆箱 |

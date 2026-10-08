# 01 现状分析

起点：上游 `562967f5`，未做本地修改。下文路径相对仓库根目录；`IS/` 表示 `IronScheme/IronScheme/`，`Console/` 表示 `IronScheme/IronScheme.Console/`。

## 1. 项目与构建

| 项目 | 目标框架 | 说明 |
|---|---|---|
| `Oyster.IntX` | net20 | 大整数 |
| `Microsoft.Scripting`（程序集 `IronScheme.Scripting`） | net20 | DLR 分支，147 个文件，约 2.57 万行 |
| `IronScheme.Closures` | net20 | `Callable`/`Closure`；编译后经 ILDasm → TailCallMaker → ILAsm 合入 `IronScheme.Glue.il` |
| `IronScheme`（`IS/`） | net20 | 运行时 + 编译器，79 个文件约 2.12 万行；reader 由 gplex/gppg 从 `.lex`/`.y` 生成 |
| `IronScheme.FrameworkPAL` | net9.0; net20; netcoreapp2.1 | 程序集保存、符号、BinaryFormatter |
| `IronScheme.Console` | net9.0; net20; netcoreapp2.1 | 宿主；非 net20 时程序集名为 `IronScheme.ConsoleCore` |
| `IronScheme.Tests` | net462 | NUnit 4，按进程方式跑 Scheme 测试 |

- 三个子模块（`IronScheme.BuildTools`、`lib/srfi`、`lib/pfds`）**均未初始化**。
- BuildTools 提供（根据用法推断）：`ILDasm`/`ILAsm`/`TailCallMaker` 任务、`RuntimeChanger`、gplex/gppg 生成、`Package` 目标（ilrepack 合并）。**缺了它旧系统无法构建**。
- **生成的 lexer/parser C# 代码不在仓库里**（`IS/Compiler/` 只有 `.lex`/`.y` 和 `RealParser.cs`）。

## 2. 现有自举

1. 仓库里提交了种子 `Console/ironscheme.boot.dll`（约 1.26 MB），引用 `IronScheme`、`IronScheme.Closures`、`IronScheme.Scripting`、`Oyster.IntX`。
2. 启动：`IronSchemeLanguageProvider` → `Builtins.Load("~/ironscheme.boot.dll")`（`IS/Hosting/IronSchemeLanguageProvider.cs:42-46`）。
3. `ironscheme-buildscript.sps`（1603 行）用当前 psyntax 展开 36 个源文件（`build/*.sls` + `psyntax/*.sls`，共 14,756 行），再经 `compile-bootfile`（`IS/Runtime/Builtins.cs:464-513`）编译成 `build/ironscheme.boot.dll`。
4. 下次启动时 `Ports.Load`（`IS/Runtime/Ports.cs:182-195`）把新 dll 换上。
5. `BootstrapTests` 跑两遍构建脚本，再做 IL 校验；不做逐字节比较。

**循环依赖**：`IronScheme.Closures` 的 `IronScheme.Glue.il` 通过 `[ironscheme.boot]'#'::'ironscheme.exceptions::raise'` 等 15 个方法名直接调用 boot dll 里的 Scheme 函数；boot dll 又引用 DLR。删掉 DLR 后现有种子无法加载。

## 3. 编译管线

### 3.1 接缝

- psyntax 的 builder 生成核心形式（`Console/psyntax/builders.sls`）。
- `rewrite`（`Console/psyntax/internal.sls:37-113`）只做一件事：`(primitive op)` 换成位置 gensym（Scheme 定义的原语）或裸名字（C# 原语）。
- 三个入口都走 `IronSchemeLanguageContext.CompileExpr`：`compile-core`（eval，`Builtins.cs:593-743`）、`compile-library`（`Builtins.cs:515-588`）、`compile-bootfile`。

### 3.2 现有编译器接受的形式

- **26 个特殊形式**（`[Generator]`）：`quote if begin set! lambda case-lambda annotated-case-lambda typed-lambda typed-case-lambda annotated-typed-case-lambda letrec letrec* library-letrec* annotated-call`，以及 `clr-{call,field-get,field-set!,new,new-array,cast,is,type-of,namespaces,using,reference}-internal`、`ffi-callout-internal`、`ffi-callback-internal`、`pinvoke-call-internal`。
- **56 个内联发射器**（`[InlineEmitter]`）：`$car $cdr $vector-ref $fx+ … $fl/ $try/finally $throw $break $and? $or?`，以及 `car cdr cons eq? eqv? not null? pair? vector void apply` 和记录相关。
- 约 82 个 `[Builtin]` C# 原语。
- **没有固定文法**：表单头部在一张全局表里查找，表里还包括编译时已绑定的全局变量；编译器会调用 `symbol-value`、执行内建函数做常量折叠、绑定到已加载程序集的方法。

### 3.3 优化

25 步 DLR AST 上的遍历（`IS/Compiler/Optimizer.cs:75-114`），包括自尾调用转循环（TCE）、命名 let 循环提升（LoopHoist）、变量类型推断、移除 `tail.`（`AnalyzeProcedureReturns`）。

### 3.4 运行时表示

| 值 | 表示 |
|---|---|
| `'()` | `null` |
| `#t`/`#f` | 装箱 `bool` 单例 |
| 序对 | `Cons`（`car`/`cdr` 字段） |
| 向量 / 字节向量 | `object[]` / `byte[]` |
| 符号 | 装箱 `SymbolId`（DLR），`SymbolTable` 驻留 |
| fixnum / flonum / bignum / 有理数 / 复数 | `int` / `double` / `IntX` / `Fraction` / `ComplexFraction`、`Complex64`（DLR） |
| 字符 / 字符串 | `SchemeChar` / `string` 或 `StringBuilder` |
| 记录 | 运行时用 TypeBuilder 生成的 CLR 类型 |
| 多值 | `MultipleValues` |
| 过程 | `Callable` → `Closure`（`CallTarget0..8`/`CallTargetN` 委托 + `CodeContext` 环境） |
| 全局 | DLR `Scope` 字典 + `ModuleGlobalWrapper` 缓存 |

- 尾调用：尾位置发射 `tail.` 前缀，自尾调用转循环。
- call/cc：`Continuation : Exception`，只能向上逃逸（`IS/Runtime/Control.cs:85-146`）。
- `dynamic-wind`：`(in) ($try/finally (proc) (out))`（`Console/build/exceptions.sls:51-54`）。

## 4. DLR 依赖面

**只用于代码生成**（随新编译器消失）：`.Ast` 全部、`.Generation` 大部分、`ScriptCode`、优化器、内联发射器。

**运行时必须重新安置**：

| 类型 | 用途 |
|---|---|
| `SymbolId` / `SymbolTable` | 符号表示与驻留 |
| `CallTarget0..8` / `CallTargetN` / `CallTargets` | 闭包委托 |
| `CodeContext` / `Scope` / `Storage<T>` / `IAttributesCollection` | 闭包环境链 |
| `CustomSymbolDictionary` / `IModuleDictionaryInitialization` / `ModuleGlobalWrapper` | 编译产物入口与全局 |
| `RuntimeHelpers.True/False/…`、`Uninitialized` | 布尔单例、未初始化哨兵 |
| `Complex64` | 非精确复数 |
| `MethodBinder` 等 | `BuiltinMethod` 与 CLR 互操作的重载决议 |
| `IPAL` / `ISerializer` | BinaryFormatter 序列化 |
| `SourceSpan` / `SyntaxErrorException` 等 | reader |
| `Debugging.*`、`ScriptDomainManager.Options` | 调试钩子、运行时开关 |
| Hosting / Shell | 宿主与 REPL |

boot dll 对 `IronScheme.Scripting` 有 23 个 TypeRef、44 个 MemberRef。没有使用 `System.Linq.Expressions` 或 `System.Dynamic`。

## 5. Scheme 侧依赖

- `build/` 与 `psyntax/` 中内联 CLR 互操作约 360 处（`clr-static-call` 161、`clr-is` 100、`clr-call` 80 …），集中在 `io/ports.sls`、`bytevectors.sls`、`numbers.sls`、`base.sls`、`hashtables.sls`。
- **reader、记录、数值塔是 C# 为主**；其余大部分 R6RS 在 Scheme 里实现。
- `lib/` 下没有 `rnrs/` 目录：所有 `(rnrs …)` 库只存在于 boot 镜像中，由构建脚本的 `library-legend` 合成。

## 6. call/cc 与尾调用

- boot 镜像与 `lib/ironscheme` 中 call/cc、`dynamic-wind` 的用法**全部是逃逸型**；唯一需要重入的是第三方 `lib/wak/fmt/private/fmt-column.scm`，现状下本来就跑不了。
- R6RS 测试中的重入用例已被注释掉（`Console/tests/r6rs/base.sls:1394`），`docs/unsupported.txt` 也声明不支持。
- **真尾调用是必需的**：扩展器 `chi-body*` 每个表单尾调用一次自己，加上大量通过闭包的未知尾调用。

## 7. 测试基线（iron-001 已实测确认）

| 测试 | 期望 |
|---|---|
| `tests/r6rs/run.sps` | 3 of 8971 failed |
| `tests/trigtest.sps` | Failed 8 of 17707 |
| `tests/clisp-number-tests.sps` | Failed 3 of 2476 |
| 自举 | 两遍构建脚本 + IL 校验 |
| 系统库编译 | 232 个库（含 srfi、pfds 子模块） |

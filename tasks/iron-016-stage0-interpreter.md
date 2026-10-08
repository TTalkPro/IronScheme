# iron-016 stage0：C# 核心形式解释器

- 里程碑：M2　依赖：iron-008、iron-009、iron-010、iron-011　状态：完成
- 设计依据：[05 §4](../designs/05-bootstrap.md)、[03 §2](../designs/03-compiler.md)

## 目标
实现精简的 Lcore 解释器 `IronScheme.Stage0`，在新运行时上执行核心形式。

## 工作内容
1. 项目 `IronScheme/IronScheme.Stage0`（net10.0，引用 IronScheme.Core）。
2. 读取 Lcore 文本（含种子的中立编码数据）。
3. 预分析：核心形式 → 闭包树；变量解析为词法地址或符号值槽；原语按名字绑定到运行时登记的 `Procedure`。
4. 覆盖 03 §2 的全部形式：`quote`、`if`、`begin`、`set!`、各类 `case-lambda`、`letrec`、`letrec*`、`library-letrec*`、`annotated-call`、应用、`clr-*-internal`（经 `Interop` 反射执行）、`ffi-*`（可先报"不支持"）。
5. 解释器生成的过程是 `Procedure` 子类，可与原语互相调用。
6. 真尾调用：内部蹦床；`$try/finally`、逃逸续延、多值使用运行时机制。
7. 命令行：`stage0 <seed> <script.sps> [args]`。

## 验收标准
- 手写 Lcore 小程序（闭包、尾递归一百万层、多值、逃逸续延、try/finally、互操作调用）运行正确。
- 规模控制在一两千行 C#。

## 从 iron-011 转来

- `clr-*-internal` 形式直接调用 `Interop`：类型说明用 `TypeResolver.Resolve(说明, 当前命名空间列表)` 解析；`clr-using-internal` / `clr-reference-internal` 维护解释器中的命名空间列表与已加载程序集（编译期副作用，见 03 §7）。

## 从 iron-012 转来

- 原语表中的 `special` 条目 `$and?` `$or?` `$break` `$throw` `$try/finally` 作用于未求值的参数表达式，解释器需专门处理（`$and?`/`$or?` 短路、结果为布尔；`$try/finally` 第二个参数在 finally 中求值；`$throw` 抛出参数；`$break` 调用 `Debugger.Break`）。其余 `$` 原语可直接调用 `IronScheme.Core.Unsafe` 中的实现。

## 从 iron-013 转来

- `(clr-prop-get #f ManagedThreadId x)`（`psyntax/compat.sls`）：类型为 `#f` 表示按实参的运行时类型查找成员。
- `(clr-call String Normalize s 'formc)`（`build/unicode.sls`）：符号实参要转换为枚举值（`NormalizationForm.FormC`，不区分大小写）。
- 种子中没有定义的名字：`compile-core`（psyntax 的 `eval` 经它执行展开结果）由 stage0 提供；`serialize-port`、`deserialize-port`、`compile-library`、`load-library-dll` 等只被导入、在启动路径上不调用。对不在原语表中的 `(primitive x)`，stage0 应退回符号值槽查找，调用时才报未绑定，而不是在加载时失败。
- typed-lambda 的类型注解（`Procedure`、`Object[]`、`Int32`、`Cons`、`Byte[]` 等）在 stage0 中可忽略或只做检查。

## 结论（2026-10-08）

完成。项目 `IronScheme/IronScheme.Stage0`（程序集 `stage0`，已加入 `IronSchemeNext.slnx`），共约 1000 行 C#：

| 文件 | 内容 |
|---|---|
| `Analyzer.cs` | 核心形式 → Node 树。词法变量解析为（层数, 下标）；其余符号为全局（符号值槽，原语由 `PrimitiveRegistry.RegisterAll` 写在同名符号中）。核心关键字、special 原语、`clr-*-internal` 只在未被词法绑定时识别。`clr-using` 的命名空间列表按 lambda / letrec / library-letrec* 词法范围生效（同旧 `SaveReferences`） |
| `Nodes.cs` | 节点、`Frame`、`Closure : Procedure`（蹦床）、`TailCall`、`Backtrace` |
| `ClrNodes.cs` | `clr-call/field-get/field-set!/new/new-array/cast/is/type-of`：类型说明连同分析时的命名空间列表保存，首次执行时解析并缓存；成员经 `Interop` 按实参决议。类型 `#f` 按实例运行时类型推断；成员说明支持符号、`"Name(…)"`（只取名字，同旧系统）、`(Name [#(泛型参数)] 参数类型 …)`。`clr-reference` 在分析时加载程序集 |
| `Interpreter.cs` | 初始化（登记原语、`compile-core`）、`RunFile`、`EvalTopLevel`（经 psyntax 的 `eval-r6rs`）、出错报告（条件逐个打印字段，附解释器过程调用链） |
| `Program.cs` | 命令行，见下；在 512 MB 栈的线程上运行 |

命令行：`stage0 [--time] --core <文件.core> …`（直接解释 Lcore 文件）；`stage0 [--time] <种子> [<脚本.sps> 参数 …]`（执行种子后以 `(load/program 脚本)` 运行顶层程序，`ProgramFailedException` 时退出码 1）。

### 关键做法

- **尾调用**：尾位置上对解释器闭包与 `apply` 原语的调用返回 `TailCall`，由 `Closure.Execute` 循环继续；尾位置调用 `apply` 时在循环中展开参数，经 `apply` 的尾递归也不增长栈。对其他过程（原语、续延）直接调用。`$try/finally` 的两部分都不在尾位置。
- **参数帧**：参数个数正好匹配且无剩余参数时，参数数组直接作为帧。
- **special 原语**：`$and?`/`$or?` 短路、结果为布尔；`$throw` 抛出参数（须为异常对象）；`$break` 只在附加调试器时中断；`$try/finally` 用 C# `try/finally`。逃逸续延、多值、条件都直接用 Core 的机制。
- **`compile-core`**：由 stage0 提供，`(compile-core e)` 返回执行 `e` 的无参过程（psyntax 的 `eval-core` 调用它）。
- **预链接**：`RunFile` 先读入并分析全部形式，对顶层 `library-letrec*` 先建帧、创建全部库级过程并写入位置，再按顺序执行其余初始化。原因：旧 boot 编译器把库级过程静态链接，种子里有跨库的前向引用（如 `(ironscheme exceptions)` 初始化时调用 psyntax compat 中定义的 `make-parameter`），逐个执行会遇到未绑定位置。`compile-core` 执行的代码不预链接。
- 未知的 `(primitive x)` 就是全局引用，调用时才报未绑定；`ffi-*`、`pinvoke-call-internal`、`define-clr-class-internal` 执行时报"不支持"。typed-lambda 的类型说明忽略。

### 对 Core 的修改

- `Interop`：params 数组参数可整体传入可转换的向量（`(clr-static-call String (Concat String[]) (list->vector …))`）；字符与整数之间按数值转换（`(clr-cast Int32 (clr-cast Char c))`，旧编译器生成 IL 数值转换）。

### 验收

1. `Stage0Tests`（10 项，在 `IronScheme.Core.Tests` 中）：闭包与被捕获变量的 `set!`、case-lambda 与剩余参数、自尾调用 / 相互尾调用 / 经 `apply` 的尾调用各一百万层、多值、逃逸续延穿过 `$try/finally`、`$and?`/`$or?`、`$throw` 抛 CLR 异常、互操作（静态与实例调用、推断类型、显式参数类型、字段、`is`、符号转枚举、数组、`clr-using` 范围、params 数组、字符转换）、`library-letrec*` 写位置与过程名、`compile-core`、无钩子时的错误退路。全部 153 项测试通过。
2. 执行文本种子：38 个形式约 0.3 秒；之后运行 R6RS 程序（`display`、bignum 阶乘、`syntax-rules` 宏、`map`、`write`）输出正确。
3. 规模约 1000 行 C#。

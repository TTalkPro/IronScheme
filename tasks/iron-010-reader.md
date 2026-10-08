# iron-010 手写 reader

- 里程碑：M1　依赖：iron-005、iron-007　状态：完成
- 设计依据：[02 §8](../designs/02-runtime.md)

## 目标
用手写递归下降 reader 取代 gplex/gppg 生成的分析器，使构建不再依赖 BuildTools。

## 工作内容
1. R6RS 第 4 章数据语法全集（注释、指令、字面量、数字、字符、字符串、字节向量、缩写）。
2. 数字解析覆盖精度前缀、基数、有理数、复数、`+inf.0`/`+nan.0`，与旧系统 `string->number` 行为对照。
3. `read-annotated`：带源位置的注解对象，结构与 psyntax 期望一致（对照 `IS/Runtime/psyntax/AnnotatedReader.cs`）。
4. 错误通过钩子报告 `lexical-error`。

## 验收标准
- 用旧系统的 `tests/r6rs/reader.sls` 用例与 `clisp-number-tests.sps` 中的数字字面量做对照测试。
- 能读完 `build/`、`psyntax/`、`lib/` 下全部源文件，且结果与旧 reader 一致（写一个对照工具）。

## 从 iron-008 转来

- 原语 `read`、`read-annotated`、`make-annotation`、`string->number`（两个重载；旧版依赖 gppg 数字解析器并借 Scheme 异常处理把错误转成 `#f`，新版解析失败直接返回 `#f`）。
- `Builtins.SourceLocation(string)`：nanopass 适配文件按名字调用 `IronScheme.Runtime.Builtins.SourceLocation`（见 iron-002），需提供兼容实现或覆盖适配文件。

## 结论（2026-10-08）

### 实现（`IronScheme/IronScheme.Core/Reader/`）

| 文件 | 内容 |
|---|---|
| `SchemeReader.cs` | 手写递归下降 reader；`ReaderException`；按端口保存状态（行列、`#!fold-case`、`#!eof`、预读字符，`ConditionalWeakTable`） |
| `NumberParser.cs` | `Builtins.ParseNumber`：完整数字语法；`ToExact` / `ToInexact`（C# 实现，不经钩子）；`MakeRectangular` / `MakePolar`（移植自旧 `Compiler/Helper.cs`） |
| `Annotation.cs` | `Annotation`、`ConsAnnotation`（字段名 `expression`/`source`/`stripped` 与旧系统一致）、`SourceSpan`（`ToString` 与旧格式相同） |
| `ReaderPrimitives.cs` | 原语 `read-annotated`、`make-annotation`、`string->number`（1/2 参数）；`ReadFromPort`；`SourceLocation(string)` |

`read` 在 Scheme 中定义（`build/io/ports.sls`：`read-annotated` 后去掉注解），C# 不提供该原语；stage0 用 `SchemeReader.ReadAll`。

### 语法覆盖（逐条对照旧 `IronScheme.lex` / `IronScheme.y` / `NumberParser.y`）

- R6RS 数据语法全集；注释 `;`、`#| |#`（可嵌套）、`#;`；指令 `#!r6rs` 等（忽略）、`#!fold-case`、`#!no-fold-case`、`#!eof`、`#!/…`。
- IronScheme 扩展：中缀点号 `(a . op . b …)` → `(op a b …)`；值向量 `#vu8(` `#u8(` `#fl(` `#fx(`；标识符中的 `[]` 对（CLR 数组类型名）；旧系统额外接受的标识符 `+o`、`-o`、`@`。
- 字符：BMP 内为 `System.Char`，之外为 `SchemeChar`（旧系统即如此；已更正 02 §2）。
- 字符串：旧转义集合、`\x…;`、行接续（R6RS 形式，允许 `\` 后有行内空白）、删除裸 `\r`、未知转义保留原文。
- 标识符的 Unicode 范围：旧词法用 gplex 中的 `IsLetterOrUnicodeSchemeIdentifier`（随 BuildTools 删除，无法查证），新实现按 R6RS 定义（首字符 Lu Ll Lt Lm Lo Mn Nl No Pd Pc Po Sc Sm Sk So Co，后续再加 Nd Mc Me）。

### 与旧实现的差别

| 项 | 旧 | 新 |
|---|---|---|
| 读取方式 | 首次读取时 `ReadToEnd` 读完整个端口、解析全部数据并缓存 | 逐个数据读取，读完一个数据不多读字符；`read` 与 `read-char` 可交替使用 |
| `string->number` 失败处理 | 借 Scheme 的 `with-exception-handler` + 续延把错误转成 `#f` | 解析失败直接返回 `#f` |
| `#e`/`#i` | 经 Glue 调 Scheme 的 `exact`/`inexact` | C# 直接转换（reader 在 boot 加载前也可用） |
| 超大指数（`0e9999999999999999999999`） | 由自写 RealParser 处理 | 指数截断到 ±100000 后交给 `double.Parse`（.NET Core 3.0 起正确舍入）；`#e` 时视为无法解析 |
| 字符串中的 `\x41`（缺 `;`） | 保留原文 | 报错（R6RS 要求 `;`） |

### 验收

1. **全量对照**：`spikes/iron-010-reader-compare/`。旧系统（`legacy-stage0`）用 `dump.sps` 读出 `build/`、`psyntax/`、`lib/`（含 srfi、pfds、nanopass 子模块）、`tests/` 下全部 639 个源文件并逐个 `write`；新 reader 分别读原文件与旧系统的输出，逐个结构比较。

   | 结果 | 文件数 | 说明 |
   |---|---|---|
   | 完全一致 | 632 | |
   | 两者都读不了 | 3 | nanopass 中给 Chez / Ikarus / Vicare 的适配文件，用了 Chez 的 `#{…}` 语法，IronScheme 不加载 |
   | 旧输出无法读回 | 1 | `lib/srfi/%3a115/regexp-impl.scm`：源码 `\x7C;`（符号 `|`）两边都读对了，旧打印器把它写成裸 `|` |
   | 不一致 | 3 | `-0.0`：两边都读对了，旧打印器把 `-0.0` 写成 `0.0` |

   全部差异都不是新 reader 的问题；比对过程中发现并修正了新 reader 的两处缺陷（标识符 `\x…;` 中的 `;` 被当作注释、超大指数）。
2. **注解位置**：`build/predicates.sls` 第一个顶层表单及其子表单的位置与旧系统逐字一致（如 `(7,1) - (113,28)`、`(7,2) - (7,9)`）。
3. **单元测试**：`ReaderTests`（13 项）、`NumberParserTests`（8 项），全部 126 项通过。

### 留给后续任务

- nanopass 适配文件按名字调用 `IronScheme.Runtime.Builtins.SourceLocation`；新运行时的方法在 `IronScheme.Core.Builtins`：iron-013 / iron-017 中用覆盖适配文件或兼容别名解决。
- `eqv?` 与 `-0.0`、旧打印器的两处问题：已转 iron-031。

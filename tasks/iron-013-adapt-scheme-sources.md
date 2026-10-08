# iron-013 Scheme 源码适配新运行时

- 里程碑：M2　依赖：iron-008、iron-009、iron-010、iron-011、iron-007　状态：完成
- 设计依据：[01 §5](../designs/01-current-state.md)、[02](../designs/02-runtime.md)、[05 §5](../designs/05-bootstrap.md)

## 目标
修改 `build/`、`psyntax/` 中引用旧运行时与 DLR 类型的代码，使其面向 IronScheme.Core。这是生成文本种子（iron-015）的前提。

## 工作内容
1. 逐文件替换 `clr-using`、`clr-is`、`clr-static-call` 等引用的类型名（约 360 处，集中在 `io/ports.sls`、`bytevectors.sls`、`numbers.sls`、`base.sls`、`hashtables.sls`、`predicates.sls`）。
2. `SymbolId` → `Symbol`，`Microsoft.Scripting.Math.Complex64` → Core 中的新位置，记录相关代码改为统一表示。
3. 在 boot 初始化处登记运行时钩子（iron-007 的清单）。
4. 修改仅限于这两个目录；修改后旧系统仍能**展开**它们（展开不执行，旧系统不需要认识新类型）。

## 验收标准
- 旧系统能完整展开修改后的 36 个 boot 源文件，无展开错误。
- 源码中不再出现旧运行时与 DLR 的类型名（逐项清单记录在本任务文件末尾）。

## 从 iron-008 转来

- `set-symbol-value!` 已是 C# 原语，`build/misc.sls` 中另有定义；`symbol->string` 在 `build/pretty-print.sls` 中出现：决定保留哪一边。
- `Callable` 的 `Arity`、`Form`、`AllowConstantFold` 在 Scheme 中被直接访问（`clr-prop-get`），新 `Procedure` 没有这些成员：改写调用处或为 `Procedure` 增加对应成员。
- `time-it` 只支持无参 thunk（现有用法都是无参）。

## 从 iron-009 转来

- `build/records/procedural.sls`、`inspection.sls`、`conditions.sls` 等中的 `(clr-using IronScheme.Runtime.R6RS)` 改为 `IronScheme.Core`；类型名 `RecordTypeDescriptor`、`RecordConstructorDescriptor`、`FieldDescriptor`、`Condition` 不变。

## 结论（2026-10-08）

完成。`build/`、`psyntax/` 中的 CLR 引用全部面向 IronScheme.Core 与 BCL；旧系统能完整展开全部 37 个 boot 源文件（`scheme-library-files` 实为 37 项，设计中的"36"为旧统计）。

### 检查工具

`spikes/iron-013-clr-check/`（ClrCheck）：用新 reader 读源码，按库收集 `clr-using`，对每个 `clr-*` 形式用 `TypeResolver` 解析类型，并按名字与参数个数在反射中核对成员。用法：`dotnet spikes/iron-013-clr-check/bin/Release/net10.0/ClrCheck.dll <根目录> <相对路径…>`。iron-031 处理 `lib/` 时可复用。

结果：改动前 496 处中 163 处无法解析；改动后 494 处中只剩 7 处误报：`numbers.sls` 宏参数 `clr-name`（2 处）、`vectors.sls` 宏参数 `type`/`type[]`（3 处，含重复）、`psyntax/compat.sls` 的 `(clr-prop-get #f ManagedThreadId …)`（类型 `#f` 表示按运行时类型查找）。

### 改动清单

| 文件 | 改动 |
|---|---|
| 14 个文件 | `(clr-using IronScheme.Runtime / IronScheme.Runtime.R6RS / IronScheme.Runtime.psyntax / Microsoft.Scripting / Microsoft.Scripting.Math / IronScheme.Scripting / IronScheme.Scripting.Math)` → 每库一个 `(clr-using IronScheme.Core)`；`Oyster.Math` 与 `System.*` 保留 |
| `exceptions.sls`、`generic-writer.sls`、`lists.sls`、`io/ports.sls`、`predicates.sls`、`psyntax/compat.sls`、`psyntax/main.sls` | 全名 `IronScheme.Runtime.X`、`IronScheme.Runtime.R6RS.X` → `IronScheme.Core.X`（SchemeException、Exceptions、MultipleValues、Cons、StringWriter、Condition、Builtins、ProgramFailedException） |
| `base.sls` | `symbol->string`：`(clr-field-get Symbol Name sym)`；`string->symbol`：`(clr-static-call Symbol Intern …)`；typed-lambda 注解 `Callable` → `Procedure`（3 处） |
| `predicates.sls` | `symbol?`：`(clr-is Symbol obj)`；`procedure?`：`(clr-is Procedure obj)` |
| `misc.sls` | `procedure-arity`/`procedure-form`：`Callable` → `Procedure`（Core 的 `Procedure` 新增虚属性 `Arity`、`Form`，默认 unspecified） |
| `constant-fold.sls` | `set-allow-constant-fold!` 不再写 `AllowConstantFold`，直接返回过程：可折叠信息只来自 `compiler/primitives.ss`（D 原则：编译器不读运行时状态） |
| `trace.sls` | C# 的 `TraceClosure` 改为 Scheme 实现 `traced-procedure`（经 `trace-printer` 打印到当前错误端口，深度前缀 `|`，支持多值） |
| `exceptions.sls` 末尾 | 登记 13 个运行时钩子：`($set-runtime-hook! 'raise raise)` 等 |
| `numbers.sls` 末尾 | 登记 `exact`、`inexact` 钩子（`exceptions` 在启动顺序中先于 `numbers`） |

Core 侧配套：`Procedure.Arity`/`Procedure.Form`、`ProgramFailedException`（`SchemeException.cs`）。142 项测试通过，原语表未变。

### 种子构建脚本（雏形）

新增 `IronScheme/IronScheme.Console/seed-buildscript.sps`，由 `ironscheme-buildscript.sps` 改写：
- 库图例增加 `$set-runtime-hook!`、`$runtime-hooks-missing`（`(ironscheme unsafe)`）。
- 生成的 `(psyntax primlocs)` 库改为纯 Scheme 建表（原为 `clr-static-call IronScheme.Runtime.Builtins MakePrimlocHashtable`）。
- 不调用 `compile-bootfile`，只展开；源码根目录由命令行第一个参数给出。
- **运行方式**：旧系统会从当前目录**和脚本所在目录**加载 `psyntax/*.sls` 源码并优先于其 boot 镜像（这会让旧进程编译新源码，遇到 `IronScheme.Core` 类型时报 `ExtractTypeInfo: type not found`）。所以脚本须复制到别处、在 `legacy-stage0/` 下运行：
  `cp seed-buildscript.sps <临时目录>/ && cd legacy-stage0 && DOTNET_ROLL_FORWARD=Major dotnet IronScheme.ConsoleCore.dll <临时目录>/seed-buildscript.sps <仓库>/IronScheme/IronScheme.Console/ < /dev/null`
- 展开耗时约 2.4 s，得到 38 个核心形式（37 个库 + primlocs 库）。

### 无 Scheme 定义的 core-prim

图例中 154 个名字没有 Scheme 定义，其中 118 个在原语表中（123 个原语 + 10 个特殊条目覆盖）。其余 36 个：

| 类别 | 名字 | 处理 |
|---|---|---|
| 核心形式 | `clr-*-internal`（12 个）、`define-clr-class-internal`、`ffi-callout-internal`、`ffi-callback-internal`、`pinvoke-call-internal`、`library-letrec*` | stage0 / 编译器作为特殊形式处理 |
| 编译驱动 | `compile-core`、`compile-library`、`compile-bootfile`、`load-library-dll`、`serialize-library`、`load-serialized-library`、`optimize`、`convert->cps`、`disassemble` | `compile-core`（eval）由 stage0 提供；其余属 03 §8 编译驱动（M4/M5） |
| 序列化 | `serialize-port`、`deserialize-port` | 只在 fasl 路径上被调用（`psyntax/internal.sls`、`main.sls` 导入），不实现 |
| 调试 | `lw-debugger*`（5 个） | 不实现 |
| 其他 | `$try`、`$try/overflow`、`$try/io`、`char-ready?`、`string-normalize` | boot 源码未使用（`string-normalize` 是 `unicode.sls` 的局部宏） |

### 未改动、保留的重复

- `set-symbol-value!`：`misc.sls` 的 Scheme 定义（调 `Builtins.SetSymbolValueFast`）与 C# 原语并存。`rewrite` 对 boot 中有定义的名字使用其位置，所以 Scheme 定义生效，行为一致。
- `symbol->string`、`string->symbol`：`base.sls` 有带契约检查的 Scheme 定义，同上。`pretty-print.sls` 中的 `symbol->string` 只是局部包装，不冲突。

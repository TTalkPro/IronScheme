# iron-012 原语表生成工具 PrimGen

- 里程碑：M1　依赖：iron-008（以及 iron-009 ~ iron-011 完成后再生成完整版）　状态：完成
- 设计依据：[02 §5](../designs/02-runtime.md)、[03 §6](../designs/03-compiler.md)

## 目标
从 IronScheme.Core 反射出全部原语，生成编译器使用的数据文件。

## 工作内容
1. 控制台工具 `IronScheme/IronScheme.PrimGen`：加载 `IronScheme.Core.dll`，输出 `IronScheme.Console/compiler/primitives.ss`。
2. 每项：名字、类型全名、方法名、参数个数（含剩余参数标记）、标志（`pure`、`unsafe`、`allow-tail-call`）、内联模板名（若有）。
3. 特殊原语（`$try/finally`、`$throw`、`$break`、`$and?`、`$or?`、`call/cc`、`values`、`call-with-values`、`apply`）以手写条目合并进来。
4. 输出排序稳定，便于 diff。

## 验收标准
- 生成文件可被 Scheme `read` 读入；与 iron-008 的原语对照表一致。

## 结论（2026-10-08）

### 实现

| 位置 | 内容 |
|---|---|
| `IronScheme/IronScheme.PrimGen/` | 控制台工具（已加入 `IronSchemeNext.slnx`）：`IronScheme.PrimGen <输出文件>` 生成；`IronScheme.PrimGen --check <已有文件>` 检查是否过期（过期返回 1） |
| `IronScheme/IronScheme.Console/compiler/primitives.ss` | 生成结果：**123 个原语、10 个特殊条目** |
| `IronScheme/IronScheme.Core/Runtime/Unsafe.cs` | 新增 38 个 `$` 原语的 C# 实现（见下） |

格式见 `designs/03-compiler.md` §6（已按实际格式更新）。原语按名字排序，重载按（固定参数个数、剩余参数、类型、方法）排序，输出稳定。

### 补上的 `$` 原语

旧系统中 `$car`、`$fx+`、`$fl/` 等 43 个 `$` 原语只有内联发射器、没有可调用的实现；iron-008 删除内联发射器后它们在 Core 中缺失，而 Scheme 源码大量使用（`build/arithmetic/fixnums.sls` 157 处）。本任务补上：

- **38 个普通 `$` 原语**（`Runtime/Unsafe.cs`）：参数先求值，C# 实现供 stage0 与非内联调用使用，`Inline` 模板名为原语名本身，标志 `unsafe`（只读者另加 `pure`）。类型不符直接抛 `InvalidCastException`（与内联后行为一致）。
- **5 个作用于未求值表达式的**（`$and?` `$or?` `$break` `$throw` `$try/finally`）：不是过程，作为 `special` 条目由编译器与 stage0 专门处理。

与旧内联发射器的差别：`$fxeven?` / `$fxodd?` 旧实现为 `(x + 1) == 0` / `(x + 1) == 1`（不是奇偶判断），Scheme 源码未使用，新实现按正确语义。`$fxdiv`/`$fxmod`（含 `0` 后缀版本）保持旧语义：截断除法、余数符号随被除数（不是 R6RS 的 `div`/`mod`），`build/bytevectors.sls`、`fixnums.sls` 使用。

同时为旧系统中有内联发射器的安全原语标上内联模板与标志：`not`、`eq?`、`eqv?`、`null?`、`pair?`、`void`（`pure`）以及 `cons`、`car`、`cdr`、`vector`。

### 验收

1. 生成文件可被 Scheme `read` 读入：新 reader（工具内回读校验名字）与旧系统（`legacy-stage0` 读出 `primitive-table 1`、123 个原语、10 个特殊条目）都能读。
2. 与 iron-008 以来的原语清单一致：123 = iron-008 的 69 + 记录 8（iron-009）+ 条件 4（iron-009）+ reader 3（`read-annotated`、`make-annotation`、`string->number`，iron-010）+ `get-clr-type` 1（iron-011）+ `$` 原语 38（本任务）。名字逐项由 `PrimitiveRegistry` 生成，无手工增删。
3. 两次生成逐字节相同；`--check` 对最新文件返回 0、对改动过的文件返回 1。
4. 单元测试 `PrimitiveTableTests`（检入的原语表与当前 Core 一致，否则失败）与 `UnsafePrimitivesTests`（3 项），全部 142 项通过。

### 留给后续任务

- 每次增删改 `[Primitive]` 后需重新运行 PrimGen；`PrimitiveTableTests` 会在原语表过期时失败。
- stage0（iron-016）与编译器（iron-025）都要按 `special` 条目处理 `$and?` `$or?` `$break` `$throw` `$try/finally`。

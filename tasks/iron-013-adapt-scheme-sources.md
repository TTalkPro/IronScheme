# iron-013 Scheme 源码适配新运行时

- 里程碑：M2　依赖：iron-008、iron-009、iron-010、iron-011、iron-007　状态：未开始
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

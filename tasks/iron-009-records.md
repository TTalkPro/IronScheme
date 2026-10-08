# iron-009 记录的统一表示

- 里程碑：M1　依赖：iron-005　状态：完成
- 设计依据：[02 §7](../designs/02-runtime.md)

## 目标
所有记录统一为 `Record`（RTD + 字段数组），不再运行时生成 CLR 类型。

## 工作内容
1. `RecordTypeDescriptor`、`RecordConstructorDescriptor`、`Record`；继承、sealed、opaque、非生成性 uid 登记表。
2. R6RS 过程层原语：`make-record-type-descriptor`、`record-constructor`、`record-predicate`、`record-accessor`、`record-mutator` 及检视层原语。
3. 条件对象基于记录实现，与 `build/conditions.sls` 的接口对齐；同时移植 `IronScheme/Runtime/R6RS/Conditions.cs`（4 个原语，iron-008 中因依赖 `RecordTypeDescriptor` 转到这里）。
4. 检查 psyntax 中语法对象等记录类型是否为非生成性，结论供 iron-020 使用。

## 验收标准
- 单元测试覆盖继承、字段可变性、opaque、按 uid 取回同一 RTD。
- 结论记录在本任务文件末尾。

## 结论（2026-10-08）

### 实现（`IronScheme/IronScheme.Core/R6RS/`）

| 文件 | 内容 |
|---|---|
| `Records.cs` | `Record`（`Rtd` + `Fields`，父类型字段在前）、`RecordTypeDescriptor`、`FieldDescriptor`、`RecordConstructorDescriptor`、`Records`（9 个原语，含带字段类型的 `make-record-type-descriptor` 重载，统一表示下忽略类型） |
| `Conditions.cs` | `Condition : Record`、`CompoundCondition : Condition`、`Conditions`（`condition`、`simple-conditions`、`condition-predicate`、`condition-accessor`） |

**不再运行时生成 CLR 类型**：谓词、访问器、修改器、构造器都是普通 `Procedure` 子类。

### 设计要点

- **类型层次**：`Record` → `Condition`（RTD 祖先链中有 `&condition` 的记录）→ `CompoundCondition`（`Rtd` 为空）。Scheme 的 `(clr-is Condition obj)` 对简单与复合条件都成立；`record?` 对复合条件为假（与旧系统一致）。
- **条件类型判定**：名字为 `&condition` 或父类型是条件类型（与旧系统相同）。条件类型创建时登记 `<名字>-rtd`，构造描述符创建时登记 `<名字>-rcd`（`build/conditions.sls` 导出这些名字，与旧系统相同）。
- **子类型判断 O(1)**：每个 RTD 保存祖先数组，按深度取元素比较。
- **构造器**：整条构造描述符链都没有 protocol 时，参数为全部字段（父在前），个数不符报错（错误信息沿用旧格式 "Incorrect number of arguments, expected N got M"）；否则按 R6RS 算法：创建空实例，各层 "new" 过程填写本层字段，有父层时先调用父层链；protocol 为 `#f` 的层用 R6RS 默认 protocol（前若干参数交给父层）。
- **非生成性**：按"名字 + uid"登记，重复定义返回同一 RTD；`Records.LookupNongenerative` 供 fasl 常量重建使用。
- **R6RS 检查**：父类型 sealed 时报错；父类型 opaque 时子类型也 opaque；字段说明必须是 `(mutable 名)` / `(immutable 名)`。
- `RecordTypeDescriptor`、`FieldDescriptor` 的成员名与旧系统一致（`Name`、`uid`、`Parent`、`Fields`、`Sealed`、`Opaque`、`Generative`、`Mutable`、`Accessor`、`Mutator`、`Type`），`build/records/inspection.sls` 只需改命名空间。

### 与旧实现（及 R6RS）的差异

| 项 | 行为 | 说明 |
|---|---|---|
| 不可变字段的 `record-mutator` | 返回 `#f` | 沿用旧系统；R6RS 要求报 `&assertion`。如需严格符合可在 iron-031 中调整 |
| 构造器返回值 | 总是返回新实例 | 沿用旧系统；R6RS 中是 protocol 返回的过程的结果（正常写法下二者相同） |
| 非生成性重复定义但字段不同 | 返回已有 RTD，不报错 | 沿用旧系统 |
| 记录作为 CLR 类型 | 不支持 | 设计决定（02 §7） |

### psyntax 的记录类型（第 4 项检查）

- psyntax 用 `define-record`（`psyntax/compat.sls:169-201`）定义 `stx`、`rib`、`library`、`module-interface` 等，展开为 `(define-record-type name (sealed #t) (opaque #t) (nongenerative) …)`。
- `(nongenerative)` 省略 uid 时，uid 是**展开时**生成的 gensym，以字面量常量写入展开结果（`psyntax/expander.sls:1981-1985`）。
- 结论：
  1. 编译产物中 uid 是固定符号常量；fasl 按名字重建符号后，用 `LookupNongenerative` 按"名字 + uid"取回同一 RTD，方案成立（iron-020）。
  2. 这些 uid 带时间戳后缀，受 iron-014（确定性 gensym）影响。
  3. 这些记录都是 opaque 的，`record?` 为假，符合预期。

### 测试

`IronScheme.Core.Tests/RecordsTests.cs`：记录 9 项、条件 5 项，全部 105 项通过。覆盖基本记录、构造器参数个数、继承与谓词、各层 protocol、父有 protocol 子用默认、非生成性、opaque 与 sealed、非法字段说明、检视成员、条件类型全局登记、简单与复合条件、条件谓词与访问器、单参数 `condition`、非条件 RTD 的拒绝。

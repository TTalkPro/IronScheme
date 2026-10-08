# iron-009 记录的统一表示

- 里程碑：M1　依赖：iron-005　状态：未开始
- 设计依据：[02 §7](../designs/02-runtime.md)

## 目标
所有记录统一为 `Record`（RTD + 字段数组），不再运行时生成 CLR 类型。

## 工作内容
1. `RecordTypeDescriptor`、`RecordConstructorDescriptor`、`Record`；继承、sealed、opaque、非生成性 uid 登记表。
2. R6RS 过程层原语：`make-record-type-descriptor`、`record-constructor`、`record-predicate`、`record-accessor`、`record-mutator` 及检视层原语。
3. 条件对象基于记录实现，与 `build/conditions.sls` 的接口对齐。
4. 检查 psyntax 中语法对象等记录类型是否为非生成性，结论供 iron-020 使用。

## 验收标准
- 单元测试覆盖继承、字段可变性、opaque、按 uid 取回同一 RTD。
- 结论记录在本任务文件末尾。

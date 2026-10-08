# iron-018 Lcil 规格与文本读取器

- 里程碑：M3　依赖：iron-003　状态：完成
- 设计依据：[04 §2](../designs/04-lcil-and-emitter.md)

## 目标
冻结 Lcil 第 1 版的文本格式，并实现发射器内部的 S 表达式读取器与结构化模型。

## 工作内容
1. 把 04 §2 的草案整理成完整规格：顶层结构、类型/字段/方法声明、全部指令、结构化 try、互操作指令、源位置。规格写入 `designs/04-lcil-and-emitter.md`（或拆为附录）。
2. 极简 S 表达式读取器（字符串、整数、浮点、符号、列表），不依赖 Scheme reader。
3. Lcil 对象模型（`LcilAssembly`、`LcilType`、`LcilMethod`、指令记录）与格式校验（未知指令、标签未定义、局部变量越界报错）。

## 验收标准
- 手写的若干 Lcil 样例能解析成对象模型，错误样例给出带位置的错误信息。

## 结论（2026-10-08）

完成。

- **规格**：`designs/04-lcil-and-emitter.md` §2 改写为第 1 版完整规格（词法、顶层结构、类型 / 字段 / 方法声明、类型与成员引用、指令、伪指令、互操作指令、校验规则）。要点：
  - 普通 CIL 指令直接用 `OpCodes` 中的名字书写，操作数格式由指令的操作数类型决定，短格式由发射器自动选择。这样指令表不用手工维护。
  - 伪指令：`label`、`ldconst`、`(tail)` 前缀、结构化 `try`（块末尾的 `leave`/`endfinally` 由发射器加入）、`line`。
  - 互操作指令：`clr-call`（成员可带显式参数类型 `("名字" ("P"…))`，类型可为 `#f` 表示运行时类型）、`clr-field-get/set`、`clr-new`、`clr-new-array`、`clr-cast`、`clr-is`、`clr-type`；方法级 `clr-namespaces`。草案中的方法级 `clr-references` 并入程序集级 `references`。
  - 方法属性 `ctor` / `cctor` 表示构造函数与类型初始化器；`maxstack` 接受但忽略（ILGenerator 自动计算）。
- **实现**（`IronScheme/IronScheme.Emit/`）：`SExpr.cs`（读取器，节点带行列）、`Model.cs`（`LcilAssembly`/`LcilType`/`LcilField`/`LcilMethod`/`Instr`/`MethodRef`/`FieldRef` 与 `LcilParser`，解析时完成校验）。
- **样例**：`IronScheme.Emit/samples/` 下 5 个手写 Lcil（阶乘、闭包计数器、try/finally 与 catch、相互尾递归、互操作），供 iron-019 发射验收共用。
- **测试** `LcilParserTests`（18 项）：5 个样例都能解析；模型细节；读取器各类数据与位置；10 类错误（未知指令、未定义 / 重复标签、参数 / 局部变量 / 常量下标越界、操作数个数、`tail` 后不是调用、操作数类型、`#t/#f`）报 `文件:行:列: 消息`；版本、缺少 assembly、常量下标、未闭合列表。全部 171 项测试通过。

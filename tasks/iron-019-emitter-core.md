# iron-019 发射器：类型、方法、指令与异常块

- 里程碑：M3　依赖：iron-018　状态：完成
- 设计依据：[04 §4、§5](../designs/04-lcil-and-emitter.md)

## 目标
把 Lcil 对象模型发射成程序集，支持持久化与内存两种模式。

## 工作内容
1. 类型与成员名字解析（按全名、命名空间列表、引用程序集），按名字加载 `IronScheme.Core.dll`。
2. 类型、字段、方法（静态 / 实例 / 重写）定义；方法体指令发射；标签；`tail.` 前缀。
3. 结构化 `try/finally`、`try/catch`。
4. 互操作指令决议（04 §5）：唯一时静态调用 + 转换，否则调用 `Interop.*`。
5. 持久化模式（`PersistedAssemblyBuilder.Save`）与内存模式（`RunAndCollect`）。
6. 命令行 `iron-emit in.lcil -o out.dll`。
7. 可选：ILVerify 校验开关。

## 验收标准
- 手写 Lcil：阶乘（循环与递归）、闭包计数器、try/finally、相互尾递归一百万层、调用 `System.String::ToUpper` 与 `Interop.Call`，都能生成 dll 并正确运行。
- ILVerify 无错误。

## 从 iron-011 转来

- 互操作指令静态决议时与运行时保持同一套规则（打分方式、索引器映射、转换规则）；参数转换调用 `Interop.Convert<T>`，返回值调用 `Interop.ConvertFrom`；决议不了时生成对 `Interop.Call` 等方法的调用。类型名解析用 `TypeResolver`。

## 从 iron-017 转来

- 解析 Lcil 中的类型名时复用 `IronScheme.Core.TypeResolver` 的规则与别名表，其中包括旧类型名映射 `IronScheme.Runtime.Builtins` → `IronScheme.Core.Builtins`（nanopass 适配文件需要）。
- 运行时互操作的转换规则以 `Interop` 为准：`clr-cast` 在整数类型（含 `char`）之间不检查溢出；params 数组参数可整体传入可转换的向量；字符与整数之间按数值转换。静态生成调用时要与这些规则一致。

## 结论（2026-10-08）

完成（常量 `ldconst` 的实现见 iron-020）。

### 实现（`IronScheme/IronScheme.Emit/`）

| 文件 | 内容 |
|---|---|
| `Emitter.cs` | `LcilEmitter.EmitInMemory`（`AssemblyBuilder` + `RunAndCollect`）与 `LcilEmitter.Save`（`PersistedAssemblyBuilder.GenerateMetadata` + `ManagedPEBuilder`，可选 Portable PDB）。类型引用解析（本程序集类型 → 全名在 references 与已加载程序集中查找，`[]`/`&` 后缀）；按基类依赖顺序定义类型；字段、方法、构造函数、类型初始化器；方法体（短格式自动选择、分支一律长格式、`tail.`、标签、`switch`）；结构化 try（`BeginExceptionBlock`，块末尾的 `leave`/`endfinally` 自动生成）；`line` 序列点（只在生成 PDB 时）；保存后回填 MVID 与时间戳 |
| `EmitInterop.cs` | 互操作指令（04 §5）。经反射调用 Core 的 `TypeResolver.Resolve`（同一套别名与命名空间规则）。可静态决议时直接 `call`/`callvirt`/`newobj`/`ldfld`/`stfld`，参数经 `Interop.Convert<T>`、返回值经 `Interop.ConvertFrom`、`void` 得 unspecified、`const` 字段内联值；否则生成对 `Interop.Call`/`GetField`/`SetField`/`New` 的调用。`clr-new-array`/`clr-cast`/`clr-is` 总是调用运行时 `Interop`，`clr-type` 为 `ldtoken` |
| `Program.cs` | 命令行 `iron-emit <in.lcil> [-o out.dll] [--pdb] [-r 目录]…` |

发射器不引用 Core 项目：`references "IronScheme.Core"` 按名字加载（已加载的程序集、`AssemblyLoadContext` 解析、`-r` 目录与发射器所在目录）。

**静态决议的条件**（保证与运行时决议结果一致）：显式参数类型时按类型精确匹配；否则该名字只有一个重载、参数个数相符、没有 `ref`/`out`/params 数组；实例成员的类型不是值类型；不是 `get_Item`/`set_Item`；构造函数只有一个。其余一律交给运行时，避免静态与运行时选出不同重载。

### 验收

1. 测试 `EmitterTests`（13 项）：5 个样例在内存与持久化两种模式下都生成并正确运行——阶乘（循环与递归）、闭包计数器（未重写的个数报参数个数错误）、try/finally（正常与异常路径都执行 finally）与 try/catch、**相互尾递归一百万层**（虚调用 + `tail.`）、`System.String::ToUpper`、显式 `Interop.Call`，以及全部互操作指令（静态决议、运行时决议、推断类型、const 字段、构造、数组、cast 不检查溢出、转换失败报 assertion-violation）。另测：静态决议的方法确实直接调用目标、决议不了的走 `Interop.Call`；持久化输出两次逐字节相同；类型 / 方法找不到时报错。全部 184 项测试通过。
2. ILVerify：`tools/ilverify.sh`（需 `dotnet tool install -g dotnet-ilverify`，已安装 10.0.12）。5 个样例经命令行发射（含 PDB）后全部 "All Classes and Methods … Verified"。

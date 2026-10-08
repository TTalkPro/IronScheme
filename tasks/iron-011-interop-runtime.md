# iron-011 CLR 互操作运行时

- 里程碑：M1　依赖：iron-006　状态：未开始
- 设计依据：[02 §9](../designs/02-runtime.md)、[04 §5](../designs/04-lcil-and-emitter.md)

## 目标
提供编译期决议不了的 CLR 成员访问的运行时实现，取代 DLR 的 MethodBinder。

## 工作内容
1. `Interop.Call`、`Interop.GetField`/`SetField`、`Interop.New`、`Interop.NewArray`、`Interop.Cast`、`Interop.Is`。
2. 按实际参数类型选重载，按（类型、名字、参数类型序列）缓存。
3. 参数转换：数值拓宽、`Procedure` → 委托（`System.Linq.Expressions` 生成适配并缓存）、符号 → 枚举、列表 → 数组；返回值：`void` → 未指定值，枚举 → 符号。
4. 转换规则以旧 `ClrGenerators.cs` 为准，差异记录在本任务文件中。
5. `Interop.Convert<T>` 供发射器在静态决议时复用。

## 验收标准
- 单元测试覆盖实例/静态方法、属性、字段、构造器、重载选择、委托参数、枚举。

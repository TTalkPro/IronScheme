# iron-011 CLR 互操作运行时

- 里程碑：M1　依赖：iron-006　状态：完成
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

## 从 iron-008 转来

- 原语 `get-clr-type`（两个重载）。
- 旧 `Helpers` 中的 `GetTypeFast`、`ConvertToDelegate`、`FFIConvertTo`/`FFIConvertFrom`、`FFIDelegate`、`FFIFunctionPointer`、`EnumToSymbol`、`SymbolToEnum`、`RequiresArray`、`UnsafeConvert`。

## 结论（2026-10-08）

### 实现（`IronScheme/IronScheme.Core/Interop/`）

| 文件 | 内容 |
|---|---|
| `TypeResolver.cs` | 类型说明（符号、字符串、`(泛型名 类型参数 …)`）→ `Type`：别名表（与旧系统相同，`cons`/`list`/`procedure` 指向新运行时类型）、按全名查找已加载程序集中的公开类型（含数组名 `Int32[]`）、默认尝试 `System.` 前缀、再按命名空间列表逐个尝试；编译期类型登记（旧 `AddCompileTimeType`）；结果缓存 |
| `Interop.cs` | `Call`（含显式签名与泛型方法类型参数）、`GetField`/`SetField`、`New`、`NewArray`、`Cast`、`Is`；重载决议与缓存；`ConvertTo`/`ConvertFrom`/`Convert<T>`；`SymbolToEnum`/`EnumToSymbol`；`ToDelegate` |
| `ClrHelpers.cs` | 原语 `get-clr-type`（两个重载）；`Helpers` 部分类：`GetTypeFast`、`ConvertToDelegate<T>`、`EnumToSymbol<T>`、`SymbolToEnum<T>`、`RequiresArray<T>`、`UnsafeConvert<T>`、`FFIConvertTo<T>`、`FFIConvertFrom<T>`、`FFIDelegate<T>`、`FFIFunctionPointer` |

### 规则

- **重载决议**：按运行时实参类型逐个打分（类型完全相同 3、可赋值 2、可转换 1、不可转换淘汰），取总分最高者；支持 `params` 数组（含直接传入数组的情形）；显式签名时按参数类型精确匹配。结果按（类型、成员、静态/实例、实参类型序列、显式签名、泛型参数）缓存。
- **索引器**：`get_Item`/`set_Item` 按 `DefaultMemberAttribute` 映射；数组直接下标访问（与旧系统相同）。
- **参数转换**：`object` 原样；`null` 只能给引用类型或可空类型；过程 → 委托；符号或符号列表 → 枚举（`[Flags]` 按位或）、数值 → 枚举；可变字符串 → `string`；任意值 → `bool`（按真值，与旧系统相同）；`SchemeChar` → `char`；数值之间按 `Convert` 规则（含 bignum、分数）；`object[]`、列表、其他数组 → 指定元素类型的数组（逐个转换）。
- **返回值转换**：`void` → 未指定值；枚举 → 符号；`bool` → `#t`/`#f` 单例；`int` → 小整数缓存装箱；其他原样。
- **过程 → 委托**：用 `System.Linq.Expressions` 生成"参数经 `ConvertFrom` 转为 Scheme 值 → `InvokeN` → 结果经 `ConvertTo` 转为返回类型"的适配委托，按委托类型缓存工厂。
- **异常**：被调方法抛出的异常原样传出（解开 `TargetInvocationException`）。

### 与旧实现的差别

| 项 | 旧 | 新 |
|---|---|---|
| 重载决议 | 编译期，用 DLR `MethodBinder` 按静态类型（多为 `object`）决议，失败后改按全 `object` 再试 | 运行时按实参类型打分决议；发射器静态决议见 iron-019 |
| `bool` 返回值 | 每次装箱新对象（`eq? #t` 失败） | 归一为 `#t`/`#f` 单例 |
| 列表 → 数组参数 | 只接受向量（`object[]`） | 也接受列表 |
| `clr-cast` 数值 | `unbox`（类型须完全一致） | 按 `Convert` 规则转换（如 fixnum → `Int64`） |
| 委托适配 | `MakeTypedCallable` 生成 `TypedClosure` | 表达式树生成的适配委托 |
| ref/out 参数 | （DLR 绑定器部分支持） | 不支持，重载候选中排除 |
| `FFIFunctionPointer` | 需要 DLR 的 `CodeContext`，把委托重新绑定 | 直接取函数指针，并保持委托存活（防止被回收） |

### 测试

`IronScheme.Core.Tests/InteropTests.cs`：类型解析 2 项、调用与转换 10 项，全部 138 项通过。覆盖别名、数组名、命名空间、泛型构造、`get-clr-type`、静态与实例重载选择（int/double/string/object）、显式签名、可变字符串参数、布尔单例、`void` 返回、`params`、枚举入参与返回、`[Flags]`、`List`/`Hashtable` 索引器、数组下标、构造器（含值类型无参）、字段读写、`Cast`、`Is`、`NewArray`、列表 → 数组、bignum → `Int64`、过程作为 `Func`/`Converter`/`Comparison`/`Action` 委托、成员找不到、异常原样传出、FFI 辅助方法。

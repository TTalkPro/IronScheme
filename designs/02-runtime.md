# 02 新运行时 IronScheme.Core

## 1. 项目

| 项 | 决定 |
|---|---|
| 程序集 / 根命名空间 | `IronScheme.Core` |
| 目标框架 | net10.0 |
| 依赖 | 只有 BCL 与 `Oyster.IntX`（大整数，源码已在仓库；已改为 `net20;net10.0` 多目标） |
| 位置 | `src/IronScheme.Core/` |
| 与旧运行时的关系 | **并存**直到 M7。命名空间不同（旧为 `IronScheme.Runtime`、`Microsoft.Scripting`），两者互不引用；旧系统只用于一次性生成文本种子（05 §5）。旧代码按需**复制后改写**，不在原文件上改，直到 M6 删除旧项目 |

## 2. 值表示

| Scheme 值 | 表示 | 相对现状 |
|---|---|---|
| `'()` | `null` | 不变 |
| `#t` / `#f` | `RT.True` / `RT.False`（装箱 `bool` 单例） | 从 DLR 的 `RuntimeHelpers` 移入 |
| 未指定值 | `Unspecified.Instance` | 不变 |
| 未初始化 | `Uninitialized.Instance` | 从 DLR 移入 |
| 序对 | `Cons`（`car`/`cdr` 公有字段） | 不变 |
| 向量 / 字节向量 | `object[]` / `byte[]` | 不变 |
| **符号** | `Symbol` 类（见 §3） | **替换** `SymbolId` 结构体 |
| fixnum | `int`（32 位） | 不变。`boot/arithmetic/fixnums.sls` 依赖 32 位宽度，改成 64 位留作以后 |
| flonum / bignum / 有理数 | `double` / `IntX` / `Fraction` | 不变 |
| 复数 | `ComplexFraction`、`Complex64` | `Complex64` 从 DLR 移入 |
| 字符 | BMP 内为 `System.Char`，之外为 `SchemeChar` | 不变（iron-010 核对旧 reader 后更正：旧系统就是这样的双表示，`boot/base.sls` 两种都处理） |
| 字符串 | `string`（不可变）或 `StringBuilder`（可变） | 不变。`boot/base.sls` 依赖这种二元表示 |
| 记录 | `Record`（见 §7） | **替换**运行时生成的 CLR 类型 |
| 多值 | `MultipleValues`（包装 `object[]`） | 不变 |
| 过程 | `Procedure` 子类（见 §4） | **替换** `Callable`/`Closure` |

## 3. 符号与全局

```csharp
public sealed class Symbol {
    public readonly string Name;
    public object Value = Unbound.Instance;   // 值槽：全局变量与库绑定
    // 驻留：ConcurrentDictionary<string, Symbol>
    public static Symbol Intern(string name);
}
```

- **驻留**：普通符号与 gensym 都按名字驻留。gensym 的名字格式沿用 `g$name$N$TICKS`，`ungensym` 取两个 `$` 之间的部分。按名字驻留保证从 dll 重新加载时得到同一个对象，`eq?` 按引用比较。
- **全局与库绑定**：展开器给每个导出变量分配一个位置 gensym（loc）。**该绑定的值就存在 loc 符号的 `Value` 字段里**。
  - `symbol-value` / `set-symbol-value!` / `symbol-bound?` 直接读写字段。
  - 编译后的代码：从常量表取出符号对象（每个模块一次），读写 `.Value`。一次间接访问，没有字典。
  - 未绑定时 `Value` 为 `Unbound.Instance`，读取时检查并调用钩子报 `undefined-error`。
- **C# 原语的登记**：启动时把每个原语的名字符号的 `Value` 设成对应的 `Procedure` 对象（见 §5）。

## 4. 过程模型

```csharp
public abstract class Procedure {
    public virtual object Invoke0()                              => ArityError(0);
    public virtual object Invoke1(object a)                      => ArityError(1);
    public virtual object Invoke2(object a, object b)            => ArityError(2);
    public virtual object Invoke3(object a, object b, object c)  => ArityError(3);
    public virtual object Invoke4(object a, object b, object c, object d) => ArityError(4);
    public virtual object InvokeN(object[] args);   // 默认按长度分派到 InvokeK，>4 时报错
    public virtual string Name { get; }
}
public sealed class Box { public object Value; }   // 被赋值且被捕获的变量
```

**两个基类**（iron-006 实现时确定）：

| 基类 | 用于 | 约定 |
|---|---|---|
| `Procedure` | 固定参数个数的过程，含没有剩余参数子句的 case-lambda | 只重写对应个数的 `InvokeK`；默认 `InvokeN` 按长度分派到 `InvokeK`，未重写的 `InvokeK` 报参数个数错误 |
| `VariadicProcedure` | 有剩余参数的过程（含带剩余参数子句的 case-lambda） | 主体写在 `InvokeN`（用 `RestList` 打包剩余参数）；`InvokeK` 默认转发到 `InvokeN`，常见个数可另行重写以免分配数组 |

两类都满足"`InvokeN` 是统一入口"。若只用一个基类、两个方向都默认转发，参数个数错误时会无限递归。

- **编译器为每个 lambda 生成一个 `Procedure` 子类**：
  - 自由变量是实例字段（扁平闭包）。
  - 按 `case-lambda` 各子句的参数个数重写对应的 `InvokeK`；有剩余参数的子句重写 `InvokeN` 以及所有 ≥ 必需参数个数的 `InvokeK`，在里面打包剩余参数为列表。
  - 参数超过 4 个的调用一律走 `InvokeN(object[])`。固定参数上限 4 是初值，以后按实测调整。
- **没有自由变量的过程**（库顶层过程、大部分原语）：方法体生成为**静态方法**，过程类只做转发，实例是单例。已知调用（库内对未被 `set!` 的顶层过程的调用）直接 `call` 静态方法。R6RS 保证导入的绑定不可变，库内未被赋值的定义也不可变，这一优化是安全的。
- **`apply`**：`(apply f a … lst)` 展开参数后调用 `InvokeK` 或 `InvokeN`。
- **参数个数错误**：`ArityError` 通过钩子调用 Scheme 的 `assertion-violation`。
- **`Arity` 属性**：编译器为每个过程类生成 `get_Arity` 重写：固定 n 个参数为 n，带剩余参数为 n.0，多子句为各子句的表（`procedure-arity` 等使用，iron-031）。

## 5. 原语

- C# 原语用 `[Primitive("name", …)]` 属性标注静态方法，参数和返回值都是 `object`（有特殊类型时由编译器负责转换）。属性带元数据：`Pure`（可常量折叠）、`AllowTailCall`、`Inline`（编译器有内联 IL 模板）。
- 启动时 `PrimitiveRegistry` 用反射找到所有原语，为每个原语创建一个包装 `Procedure`（用 `Delegate.CreateDelegate` 得到 `Func<…>`，不在运行时生成 IL），写进名字符号的值槽。
- **原语表数据文件**：构建 `IronScheme.Core` 时，一个小工具 `IronScheme.PrimGen`（.NET 控制台程序）反射出全部原语，生成 `src/scheme/boot/primitives.ss`：每项包括名字、所在类型、方法名、参数个数、标志。编译器只读这个文件，不访问运行时（见 03 §4）。
- 现有 `[Builtin]`（约 82 个）迁移为 `[Primitive]`；现有 56 个 `[InlineEmitter]` 改由编译器的内联 IL 模板实现（03 §6），C# 侧只保留对应的普通方法作为非内联时的后备。

## 6. 异常、逃逸续延与钩子

| 机制 | 设计 |
|---|---|
| Scheme 条件 | `SchemeException : Exception`，携带条件对象。沿用现状 |
| `raise` / `with-exception-handler` / `guard` | 保持在 Scheme 实现（`boot/exceptions.sls`、展开器的 `guard`）。不改语义。处理器栈本身（栈顶在前的过程列表）自 iron-050 起放在 C# 的 `AsyncLocal` 里（`ExceptionHandlers`，原语 `$current-handlers` / `$set-current-handlers!`），随 `ExecutionContext` 流入子任务与 await 之后的续接；参数对象（`make-parameter`）同样改为每个参数一个 `AsyncLocal`（`ParamSlot`，原语 `$make-param-slot` / `$param-ref` / `$param-set!`），见 10 §2 D7 |
| **call/cc** | 只支持逃逸续延。`call/cc` 创建 `EscapeContinuation : Procedure`，带唯一标记；调用时抛 `ContinuationException(标记, 值)`；`call/cc` 所在帧按标记捕获并返回值。帧退出后（finally 中置失效标志）再调用该续延，报"续延已失效"的条件，而不是现在的模糊错误 |
| `dynamic-wind` | 沿用 Scheme 定义 `(in) ($try/finally (proc) (out))`，`$try/finally` 是编译器核心形式 |
| **运行时钩子**（取代 `IronScheme.Glue.il`） | `RuntimeHooks` 静态类持有若干 `Procedure` 字段：`Raise`、`RaiseContinuable`、`WithExceptionHandler`、`AssertionViolation`、`Exact`、`Inexact`、`SyntaxError`、`LexicalError`、`UndefinedError`、I/O 与文件条件构造器等（与现有 15 个胶水方法一一对应）。boot 镜像初始化时由 Scheme 调用原语 `($set-runtime-hook! 'raise raise)` 登记。C# 代码通过钩子调用，不再依赖 boot dll 的方法名 |

## 7. 记录

```csharp
public sealed class RecordTypeDescriptor { string Name; Symbol Uid; RecordTypeDescriptor Parent;
    bool Sealed, Opaque; FieldSpec[] Fields; … }
public sealed class Record { public readonly RecordTypeDescriptor Rtd; public readonly object[] Fields; }
```

- 所有记录（包括条件、展开器的语法对象等）都是 `Record`，字段在数组里。**不再运行时生成 CLR 类型**。
- 访问器、谓词、修改器是普通原语，编译器可以为已知 RTD 的访问器内联"类型检查 + 取数组元素"。
- 非生成性记录（`nongenerative`）按 `Uid` 在全局表登记，保证常量重建时得到同一个 RTD（见 04 §3）。
- 放弃的能力：记录作为真实 CLR 类型供 C# 强类型使用。以后如有需要，再做一个"可选生成 CLR 类型"的扩展。

## 8. Reader

- 手写递归下降，取代 gplex/gppg 生成的分析器与 `RealParser`。覆盖 R6RS 第 4 章数据语法：注释（`;`、`#|…|#`、`#;`）、`#!r6rs` 等指令、所有字面量、数字语法（含精度前缀、基数、有理数、复数、`+inf.0`/`+nan.0`）、字符名、字符串转义、字节向量、`'`/`` ` ``/`,`/`,@`/`#'`/`` #` ``/`#,`/`#,@` 缩写。
- `read-annotated`：为展开器生成带源位置的注解对象。源位置类型 `SourceSpan` 在 Core 里自定义（文件、起止行列）。
- 错误报告通过钩子 `LexicalError`。

## 9. CLR 互操作运行时

- 编译期能决议的成员调用由发射器直接生成 `call`/`callvirt`（04 §5）。
- 决议不了的（参数类型只有运行时才知道、重载歧义）发射为对 `Interop.Call(type, name, instance, args)` 等运行时方法的调用：
  - 用反射按实际参数类型选重载，结果按（类型、名字、参数类型序列）缓存。
  - 参数转换：数值拓宽、`Procedure` 转委托（用 `System.Linq.Expressions` 生成适配委托并缓存；这是 .NET 自带的能力）、符号转枚举、列表转数组。
  - 返回值转换：`void` → 未指定值，枚举 → 符号；Scheme 不直接使用的 CLR 数值类型（long、short、byte、sbyte、ushort、uint、ulong、float）转为 Scheme 数（fixnum、bignum 或 flonum）。声明类型为 `object` 的返回值与字段值按运行时类型同样转换（iron-039）。
  - `clr-cast` 在整数类型（含 `char`）之间按 IL `conv` 转换：不检查溢出，截断取低位（与旧编译器一致）；params 数组参数可整体传入可转换的向量。
  - 类型名决议找不到类型时，按惯例加载与类型全名或其命名空间同名的程序集再找（如 `Microsoft.Win32.Registry`；.NET 10 不会预先加载它们，iron-031）。
  - 类型名别名（`fixnum`、`list` 等）之外，另把第三方代码写死的旧类型名 `IronScheme.Runtime.Builtins` 映射到 `IronScheme.Core.Builtins`（nanopass 适配文件）。
- 取代 DLR 的 `MethodBinder` 一族。规则以现有 `ClrGenerators.cs` 的行为为准，做必要简化。
- 索引器（`get_Item`/`set_Item`）：运行时按类型的 `DefaultMember` 映射到实际名字，映射结果按类型缓存（iron-033；`hashtable-ref` 等热点原先每次都查特性）。发射器对非数组类型也做同样映射后静态决议（04 §5）。
- **FFI**（iron-032）：`ffi-callout-internal`、`ffi-callback-internal`、`pinvoke-call-internal` 是运行时原语（`IronScheme.Core.Ffi`），参数为类型名（符号或字符串：`int8`…`uint64`、`intptr`/`void*`、`float`/`double`、`string`/`char*`、`void`）。每种签名在一个动态程序集中生成一个委托类型（带 `UnmanagedFunctionPointer`，callout/callback 为 cdecl，pinvoke 为 Winapi），原生调用经 `Marshal.GetDelegateForFunctionPointer`，字符串按委托封送规则转换；实参与返回值的转换用 `Helpers.FFIConvertTo/FFIConvertFrom`，适配代码用表达式树生成并按签名缓存。callback 的委托保持存活（`Helpers.FFIFunctionPointer`）。`pinvoke-call` 在首次调用时才经 `NativeLibrary.TryLoad`（带平台命名探测）加载库、查找入口。编译器与 stage0 把它们当普通原语调用，不再是特殊形式。

## 10. 迁移清单

从 `IS/Runtime/` 复制改写到 `IronScheme.Core`：数值（`Numbers`、`BigFraction`、`ComplexFraction`、`Complex64`）、列表、向量、字节向量、字符串与 Unicode、哈希表、相等性、条件、I/O 与端口、环境（`symbol-value` 等）、控制（`apply`、`values`、`call-with-values`、逃逸续延）、序列化（改为新 fasl，见 04）。

去除：所有 `[InlineEmitter]`、DLR 类型引用、`ScriptDomainManager` 依赖、调试钩子（以后另做）、BinaryFormatter。

## 11. 宿主

- 新控制台程序 `IronScheme.Host`（net10.0）：
  1. 初始化运行时（登记原语）；
  2. 加载 `ironscheme.boot.dll`（新格式，见 04 §6）；
  3. 有脚本参数时以 R6RS 顶层程序运行；否则进入简单 REPL（逐行读入、`eval-r6rs`、打印）。
- 嵌入 API（`"expr".Eval()` 之类）和 SuperConsole 不在首批范围内。

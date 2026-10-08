# 02 新运行时 IronScheme.Core

## 1. 项目

| 项 | 决定 |
|---|---|
| 程序集 / 根命名空间 | `IronScheme.Core` |
| 目标框架 | net10.0 |
| 依赖 | 只有 BCL 与 `Oyster.IntX`（大整数，源码已在仓库；已改为 `net20;net10.0` 多目标） |
| 位置 | `IronScheme/IronScheme.Core/` |
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
| fixnum | `int`（32 位） | 不变。`build/arithmetic/fixnums.sls` 依赖 32 位宽度，改成 64 位留作以后 |
| flonum / bignum / 有理数 | `double` / `IntX` / `Fraction` | 不变 |
| 复数 | `ComplexFraction`、`Complex64` | `Complex64` 从 DLR 移入 |
| 字符 | `SchemeChar` | 不变 |
| 字符串 | `string`（不可变）或 `StringBuilder`（可变） | 不变。`build/base.sls` 依赖这种二元表示 |
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
- **全局与库绑定**：psyntax 给每个导出变量分配一个位置 gensym（loc）。**该绑定的值就存在 loc 符号的 `Value` 字段里**。
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

- **编译器为每个 lambda 生成一个 `Procedure` 子类**：
  - 自由变量是实例字段（扁平闭包）。
  - 按 `case-lambda` 各子句的参数个数重写对应的 `InvokeK`；有剩余参数的子句重写 `InvokeN` 以及所有 ≥ 必需参数个数的 `InvokeK`，在里面打包剩余参数为列表。
  - 参数超过 4 个的调用一律走 `InvokeN(object[])`。固定参数上限 4 是初值，以后按实测调整。
- **没有自由变量的过程**（库顶层过程、大部分原语）：方法体生成为**静态方法**，过程类只做转发，实例是单例。已知调用（库内对未被 `set!` 的顶层过程的调用）直接 `call` 静态方法。R6RS 保证导入的绑定不可变，库内未被赋值的定义也不可变，这一优化是安全的。
- **`apply`**：`(apply f a … lst)` 展开参数后调用 `InvokeK` 或 `InvokeN`。
- **参数个数错误**：`ArityError` 通过钩子调用 Scheme 的 `assertion-violation`。

## 5. 原语

- C# 原语用 `[Primitive("name", …)]` 属性标注静态方法，参数和返回值都是 `object`（有特殊类型时由编译器负责转换）。属性带元数据：`Pure`（可常量折叠）、`AllowTailCall`、`Inline`（编译器有内联 IL 模板）。
- 启动时 `PrimitiveRegistry` 用反射找到所有原语，为每个原语创建一个包装 `Procedure`（用 `Delegate.CreateDelegate` 得到 `Func<…>`，不在运行时生成 IL），写进名字符号的值槽。
- **原语表数据文件**：构建 `IronScheme.Core` 时，一个小工具 `IronScheme.PrimGen`（.NET 控制台程序）反射出全部原语，生成 `Console/compiler/primitives.ss`：每项包括名字、所在类型、方法名、参数个数、标志。编译器只读这个文件，不访问运行时（见 03 §4）。
- 现有 `[Builtin]`（约 82 个）迁移为 `[Primitive]`；现有 56 个 `[InlineEmitter]` 改由编译器的内联 IL 模板实现（03 §6），C# 侧只保留对应的普通方法作为非内联时的后备。

## 6. 异常、逃逸续延与钩子

| 机制 | 设计 |
|---|---|
| Scheme 条件 | `SchemeException : Exception`，携带条件对象。沿用现状 |
| `raise` / `with-exception-handler` / `guard` | 保持在 Scheme 实现（`build/exceptions.sls`、psyntax 的 `guard`）。不改语义 |
| **call/cc** | 只支持逃逸续延。`call/cc` 创建 `EscapeContinuation : Procedure`，带唯一标记；调用时抛 `ContinuationException(标记, 值)`；`call/cc` 所在帧按标记捕获并返回值。帧退出后（finally 中置失效标志）再调用该续延，报"续延已失效"的条件，而不是现在的模糊错误 |
| `dynamic-wind` | 沿用 Scheme 定义 `(in) ($try/finally (proc) (out))`，`$try/finally` 是编译器核心形式 |
| **运行时钩子**（取代 `IronScheme.Glue.il`） | `RuntimeHooks` 静态类持有若干 `Procedure` 字段：`Raise`、`RaiseContinuable`、`WithExceptionHandler`、`AssertionViolation`、`Exact`、`Inexact`、`SyntaxError`、`LexicalError`、`UndefinedError`、I/O 与文件条件构造器等（与现有 15 个胶水方法一一对应）。boot 镜像初始化时由 Scheme 调用原语 `($set-runtime-hook! 'raise raise)` 登记。C# 代码通过钩子调用，不再依赖 boot dll 的方法名 |

## 7. 记录

```csharp
public sealed class RecordTypeDescriptor { string Name; Symbol Uid; RecordTypeDescriptor Parent;
    bool Sealed, Opaque; FieldSpec[] Fields; … }
public sealed class Record { public readonly RecordTypeDescriptor Rtd; public readonly object[] Fields; }
```

- 所有记录（包括条件、psyntax 的语法对象等）都是 `Record`，字段在数组里。**不再运行时生成 CLR 类型**。
- 访问器、谓词、修改器是普通原语，编译器可以为已知 RTD 的访问器内联"类型检查 + 取数组元素"。
- 非生成性记录（`nongenerative`）按 `Uid` 在全局表登记，保证常量重建时得到同一个 RTD（见 04 §3）。
- 放弃的能力：记录作为真实 CLR 类型供 C# 强类型使用。以后如有需要，再做一个"可选生成 CLR 类型"的扩展。

## 8. Reader

- 手写递归下降，取代 gplex/gppg 生成的分析器与 `RealParser`。覆盖 R6RS 第 4 章数据语法：注释（`;`、`#|…|#`、`#;`）、`#!r6rs` 等指令、所有字面量、数字语法（含精度前缀、基数、有理数、复数、`+inf.0`/`+nan.0`）、字符名、字符串转义、字节向量、`'`/`` ` ``/`,`/`,@`/`#'`/`` #` ``/`#,`/`#,@` 缩写。
- `read-annotated`：为 psyntax 生成带源位置的注解对象。源位置类型 `SourceSpan` 在 Core 里自定义（文件、起止行列）。
- 错误报告通过钩子 `LexicalError`。

## 9. CLR 互操作运行时

- 编译期能决议的成员调用由发射器直接生成 `call`/`callvirt`（04 §5）。
- 决议不了的（参数类型只有运行时才知道、重载歧义）发射为对 `Interop.Call(type, name, instance, args)` 等运行时方法的调用：
  - 用反射按实际参数类型选重载，结果按（类型、名字、参数类型序列）缓存。
  - 参数转换：数值拓宽、`Procedure` 转委托（用 `System.Linq.Expressions` 生成适配委托并缓存；这是 .NET 自带的能力）、符号转枚举、列表转数组。
  - 返回值转换：`void` → 未指定值，枚举 → 符号。
- 取代 DLR 的 `MethodBinder` 一族。规则以现有 `ClrGenerators.cs` 的行为为准，做必要简化。

## 10. 迁移清单

从 `IS/Runtime/` 复制改写到 `IronScheme.Core`：数值（`Numbers`、`BigFraction`、`ComplexFraction`、`Complex64`）、列表、向量、字节向量、字符串与 Unicode、哈希表、相等性、条件、I/O 与端口、环境（`symbol-value` 等）、控制（`apply`、`values`、`call-with-values`、逃逸续延）、序列化（改为新 fasl，见 04）。

去除：所有 `[InlineEmitter]`、DLR 类型引用、`ScriptDomainManager` 依赖、调试钩子（以后另做）、BinaryFormatter。

## 11. 宿主

- 新控制台程序 `IronScheme.Host`（net10.0）：
  1. 初始化运行时（登记原语）；
  2. 加载 `ironscheme.boot.dll`（新格式，见 04 §6）；
  3. 有脚本参数时以 R6RS 顶层程序运行；否则进入简单 REPL（逐行读入、`eval-r6rs`、打印）。
- 嵌入 API（`"expr".Eval()` 之类）和 SuperConsole 不在首批范围内。

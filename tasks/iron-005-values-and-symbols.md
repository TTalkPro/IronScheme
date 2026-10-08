# iron-005 值表示与符号值槽

- 里程碑：M1　依赖：iron-004　状态：完成
- 设计依据：[02 §2、§3](../designs/02-runtime.md)

## 目标
实现基础值类型与带值槽的符号。

## 工作内容
1. `Cons`、`RT.True/False`、`Unspecified`、`Uninitialized`、`Unbound`、`MultipleValues`、`SchemeChar`。
2. `Symbol`：名字、`Value` 值槽、按名字驻留（线程安全）、gensym 生成与 `ungensym`。
3. 原语：`symbol-value`、`set-symbol-value!`、`symbol-bound?`、`remove-location`、`string->symbol`、`symbol->string`、`gensym`。
4. 小整数装箱缓存。

## 验收标准
- 单元测试：驻留同一对象、gensym 唯一且可按名字重新驻留、值槽读写、未绑定检测。

## 结论（2026-10-08）

### 实现（`IronScheme/IronScheme.Core/`）

| 文件 | 内容 |
|---|---|
| `Values.cs` | `RT`（`True`/`False` 单例、`IsTrue`、`Bool`、小整数装箱缓存 `Box`，范围 -1024 ~ 1023）、`Unspecified`、`Uninitialized`、`Unbound`、`MultipleValues`（`ToArray(expects)` 做个数检查）、`SchemeChar`（与旧运行时同形的只读结构体，`Value` 字段） |
| `Cons.cs` | `car`/`cdr` 公有字段（与旧运行时、编译器内联模板一致）、`FromList`、`FromArray`、枚举 |
| `Symbol.cs` | `Name`、`Value` 值槽、`ConcurrentDictionary` 按名字驻留（gensym 同样驻留）、`Gensym()` / `Gensym(name)`、`UngensymName`、`Ungensym` |
| `Primitive.cs` | `[Primitive(name, Flags, Inline)]` 属性与 `PrimitiveFlags`（`Pure`、`Unsafe`、`AllowTailCall`） |
| `SymbolPrimitives.cs` | `symbol-value`、`set-symbol-value!`、`symbol-bound?`、`remove-location`、`string->symbol`（接受可变字符串 `StringBuilder`）、`symbol->string`、`gensym`（0/1 参，参数可为字符串或符号）、`ungensym` |
| `Errors.cs` | 报错统一入口 `AssertionViolation`、`UndefinedError`、`RequiresType`。**临时实现**：抛 `SchemeRuntimeError`；iron-007 改为经运行时钩子调用 Scheme 的条件过程 |

### 与旧运行时的兼容

- gensym 名字格式沿用：`g$<名字>$<计数>$<TICKS>`，匿名 `g$gen<计数>$<TICKS>`；TICKS 为进程启动时间派生的 64 进制串（`Symbol.TickString`）。这是 iron-014 要处理的不确定性来源。
- `ungensym` 规则沿用：取第一个与第二个 `$` 之间的部分。
- `gensym` 以 gensym 为参数时用其去装饰后的名字（与旧 `GenSym(object)` 一致）。
- `symbol-value` 对未绑定符号报 `undefined-error`，`who` 为去装饰后的名字。

### 测试

`IronScheme.Core.Tests/ValueAndSymbolTests.cs`，17 项（连同冒烟测试共 19 项），全部通过：驻留同一对象与并发驻留、gensym 唯一且可按名字重新驻留、匿名格式、`ungensym` 规则、值槽读写与解除绑定、未绑定报 `undefined-error`、类型错误报 `assertion-violation`、可变字符串转符号、布尔真值规则、小整数缓存、`Cons` 构造与枚举、多值个数检查、原语标注完整。

### 留给后续任务

- `build/predicates.sls` 中 `(clr-is SymbolId obj)` 等改为 `Symbol`：iron-013。
- `Errors` 改走运行时钩子：iron-007。
- 编译器为 fixnum 装箱时调用 `RT.Box`：iron-025。

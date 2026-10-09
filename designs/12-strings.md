# 12 字符串表示（iron-055）

状态：已实施（iron-055）。用户选定"自有字符串类型（窄/宽）"（iron-054 的 B 项）。

## 1. 问题

字符是 Unicode 标量值（BMP 内为 `System.Char`，之外为 `SchemeChar`），字符串却是 .NET 的 UTF-16：不可变串为 `System.String`，可变串为 `StringBuilder`。BMP 之外的字符在字符串中占两个码元，`string-length` 多算，`string-ref` 取到半个代理对，`string-set!` 写入这类字符会让后面的下标错位，`string<?` 按 UTF-16 码元而不是码点比较。R6RS 要求字符串是字符（标量值）的序列。

## 2. 表示

仿 Python 的 PEP 393（窄/宽两种存储）：

| 类型 | 用于 | 存储 |
|---|---|---|
| `System.String` | 不可变、且**不含代理码元**的串（字面量、CLR 互操作的结果等，绝大多数情况） | UTF-16，下标即码点下标 |
| `IronScheme.Core.SchemeString` | 可变串（取代 `StringBuilder`）；以及含 BMP 之外字符的不可变串 | 窄：`char[]`（全部在 BMP 内）；宽：`int[]`（码点）。可变串写入 BMP 之外的字符时就地变宽 |

**不变式**：Scheme 可见的 `System.String` 不含代理码元。因此对 `System.String` 的 `string-length`/`string-ref` 仍是 O(1)，纯 BMP 程序的性能不变。

## 3. 入口的规范化

凡是从 .NET 进入 Scheme 的 `System.String`，经 `SchemeString.Normalize`：不含代理码元时原样返回（只扫描、不分配）；否则转为不可变的宽 `SchemeString`（成对的代理组合为码点，孤立的代理换成 U+FFFD）。入口：
- CLR 互操作的返回值、字段值：`Interop.ConvertFrom`（反射路径）与 Emit 静态生成的调用（返回类型为 `String` 时插入规范化）；
- 读入器的字符串字面量、`symbol->string`、Fasl 常量中的字符串；
- C# 原语中返回字符串的（端口读取等）。

出口：传给 CLR 的 `String` 参数时，`SchemeString` 转为 UTF-16（`ToString()`），`Interop.ConvertTo`/`Convert<T>` 负责。

## 4. 操作

字符串的基本操作在 C#（`SchemeString` 与 `Builtins` 中的静态方法），boot 源码调用它们：`string?`、`string-length`、`string-ref`、`string-set!`、`substring`、`string-append`、`string->list`、`list->string`、`make-string`、`string`、`string-copy`、`string-fill!`，以及按码点的比较。其余操作（大小写转换、规范化、查找等）先 `->string` 得到 UTF-16 交给 .NET，结果再经入口规范化——这些操作不涉及下标，结果正确。

`equal?`、`string-hash` 按内容：`System.String` 与 `SchemeString` 内容相同即相等，散列取其 UTF-16 形式。

## 5. 自举过渡

新 Core 必须仍能运行旧种子（旧 boot 源码直接使用 `StringBuilder`）：过渡期 Core 同时接受 `StringBuilder`（`string?` 等 C# 侧判断两者都认），新 boot 源码只产生 `SchemeString`。种子再生成后，旧种子不再需要，但 `StringBuilder` 的兼容判断保留（CLR 代码可能返回它）。

# iron-055 字符串表示：按码点的窄/宽字符串

- 里程碑：M9　依赖：iron-054　状态：完成
- 设计依据：[12](../designs/12-strings.md)

## 目标
字符串成为字符（Unicode 标量值）的序列：BMP 之外的字符在字符串中只占一个位置，`string-length`、`string-ref`、`string-set!`、`substring`、比较等都按码点。

## 工作内容
1. C# `SchemeString`（窄 `char[]` / 宽 `int[]`，可变或不可变）与入口规范化 `SchemeString.Normalize`。
2. 入口：Interop 的返回值与字段值（反射与 Emit 两条路径）、读入器、`symbol->string`、Fasl；出口：`Interop.ConvertTo`/`Convert<T>`。
3. boot 源码中可变串由 `StringBuilder` 改为 `SchemeString`，基本操作改调 C#；编译器常量（可变串、含 BMP 外字符的字面量）。
4. `equal?`、散列、打印、端口、符号等按内容处理两种表示。
5. 自举过渡：新 Core 先兼容旧种子；重建 boot、再生成种子、达到不动点。
6. 测试：BMP 之外字符的长度、下标、修改、比较、往返（端口、符号、互操作、常量）；char-sets 中因此改测 BMP 的项恢复原样。

## 验收标准
- 新增测试通过；全部原有测试通过；种子达到不动点；纯 BMP 字符串的基本操作没有明显变慢。

## 结论（2026-10-09）

完成，设计见 12。

**表示**：不可变且不含代理码元的串仍是 `System.String`（绝大多数情况，下标即码点）；新增 `IronScheme.Core.SchemeString`，用于可变串（取代 `StringBuilder`）与含 BMP 外字符的不可变串，存储为 `char[]`（窄）或 `int[]`（宽），可变串写入 BMP 外字符时就地变宽。

**入口规范化**（`SchemeString.Normalize`：不含代理码元时原样返回，否则转为不可变宽串）：
- CLR 互操作的返回值与字段值：反射路径 `Interop.ConvertFrom`、`clr-cast` 的结果，Emit 静态生成的调用（返回类型为 `String` 时插入）；
- 读入器的字符串字面量、`symbol->string`、Fasl 的 `Str` 常量（`MStr` 解码为可变 `SchemeString`）。

出口方向：`Interop.ConvertTo`/`Convert<T>`、`RequiresNotNull<string>` 接受 `SchemeString`（转为 UTF-16）。过渡期 C# 侧仍接受 `StringBuilder`。

**操作**
- `string-length`、`string-ref`、`string-set!`、`string-fill!`、`make-string`、`string`、`list->string`、`string->list`、`string-copy`、`substring`、`string-append`、按码点比较：改调 C#（`Runtime/Strings.cs`），可变性与原实现一致。
- 文本端口按码点读：`get-char`、`lookahead-char`、`get-string-n`、`get-line`、`get-string-all` 改调 `TextPorts`，代理对组合为一个字符。`lookahead-char` 遇到高代理时读出整个字符，记为该 reader 的待取字符。
- 写：`put-string` 的 start/count 按码点。
- 编译器：只有 `System.String` 用 `ldstr`，`SchemeString` 进常量表；`mutable-string?` 认可变 `SchemeString`。发射器的 `SchemeData` 按类型名识别 `SchemeString`。

**顺带修正的既有缺陷**
- `get-char` 读到代理码元时 `integer->char` 报错，原来读不了 BMP 外的字符；
- `char-upcase`/`char-downcase` 对 BMP 外字符原样返回，改用 `Rune` 的不变区域映射；
- `get-string-all` 在没有字符时按 R6RS 返回文件尾对象（原来返回空串）。

**自举过渡**：旧种子的展开器只认 `String`/`StringBuilder`，而新读入器把含 BMP 外字符的字面量读成 `SchemeString`。boot 源码中这样的字面量只有 unicode.sls 大小写折叠表的 40 处，改写为 `(string #\x…)`。另外 unicode.sls 补了 `(clr-using IronScheme.Core)`：编译路径能解析到 `Builtins`，但 stage0 解释种子时按库的 `clr-using` 查找类型。之后旧种子在新 Core 上构建新 boot，新系统再生成种子；`seed` 与 `seed --stage0` 逐字节相同，重建后再生成仍相同。

**测试**
- 新增 `tests/unicode-strings.sps`（45 项，C# Other 类别的 `UnicodeStrings`）：长度、下标、子串、修改（就地变宽）、按码点比较、大小写、符号与散列、端口读写、UTF-8 往返、.NET 互操作的两个方向，以及纯 BMP 字符串仍为 `System.String`。
- std char-sets 测试中曾因 UTF-16 改测 BMP 的一项恢复原样；Core.Tests 的 Fasl 测试按新表示更新期望。
- 完整测试 Core.Tests 229/229、IronScheme.Tests 81/81。

**性能**：拿不到改动前的镜像，未做前后对比。粗测中，可变串（新的 C# 路径）与 `System.String`（未变的路径）的同类操作耗时相当（200 万次 `string-ref` 约 1.6 s 对 1.7 s，主要是循环本身的开销）。

**已知限制**
- .NET 返回的、按 UTF-16 下标计算的结果（如直接调用 `String.IndexOf`）用在含 BMP 外字符的串上时，下标不一致；boot 中这样的用法已逐一改掉，库代码直接调用 .NET 时需自行注意。
- `lookahead-char` 记下的待取字符只对经由 `get-char` 等端口过程的读取生效，C# 读入器（`read`）不检查它。

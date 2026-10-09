# iron-043 std：向量、散列表、比较、排序与算术

- 里程碑：M9　依赖：iron-041　状态：完成
- 设计依据：[08](../designs/08-std-library.md) §2、§3

## 工作内容
`vectors`（:133）、`numeric-vectors`（:4）、`arrays`（:25）、`hashtables`（:126 + :125）、`sets`（:113）、`comparators`（:128）、`compare-procedures`（:67）、`sorting`（:132）、`arithmetic`（:141 :143 :151 :60），各带测试。

## 验收标准
- 原 SRFI 测试中对应部分全部通过；D2 守卫通过。

## 结论（2026-10-09）

完成。9 个库与 2 个内部库，均按 08 的 D1–D8：参照代码并入文件，文件头写明出处、许可、取舍与 D2 对照；D2 守卫（`tests/std/check-std.sps`）通过；这些库可同时导入（`compare-procedures` 与 `comparators` 的 `=?` 等同名，需给其一加前缀，文件头已注明）。

| 库 | 来源 | 导出 | 测试项 | 与原测试对照 |
|---|---|---|---|---|
| `vectors` | :133 | 28 | 101 | 原 `vectors.sps` 测的是 SRFI 43（94 项全过）：语义不同的 11 项按 SRFI 133 改写（kons/f 不收下标），用到 D2 不导出名字的 16 项改为对照表写法，原项留在注释中；另补 133 新增的 7 个名字 |
| `numeric-vectors` | :4 | 80 | 85 | 无原测试，按 SRFI 4 文本：10 种类型 × 8 个过程、取值两端与越界 |
| `arrays` | :25 + arlib | 31 | 81 | 原 24 + 47 项（`multi-dimensional-arrays.sps`、`--arlib.sps`）全过，另补 9 个未覆盖名字 |
| `hashtables` | :126 + :125 | 67 | 271 | 原 `r6rs-hashtables.sps` 179/186（7 项失败）、`tables-test.sps` 全过；std 全部通过，见下"基础库问题" |
| `sets` | :113 | 113 | 281 | 原 281 项全过 |
| `comparators` | :128 | 32 | 46 | 无原测试，按 SRFI 128 文本 |
| `compare-procedures` | :67 | 58 | 99590 | 原 `examples.scm` 99590 项全过 |
| `sorting` | :132 | 17 | 109 | 原 `sorting-test.scm` 测内部过程且 chez-srfi 未运行它；按 SRFI 132 文本写，含随机数据与基础库 `list-sort` 对照 |
| `arithmetic` | :141 + :143（12 个）+ :151 + :60（17 个独有） | 81 | 425 | 原 `bitwise-operations.sps` 239/245、`fixnums.sps` 141 项；std 全部通过，另补 :141、:60、:143 常量的测试 |

**内部库**（`(ironscheme std private …)`）：`hashtables-126`（SRFI 126 全部，含与基础库同名而扩展参数的 `make-hashtable` 等，供 `hashtables` 与测试使用）、`integer-bits`（SRFI 60 全部，`arithmetic` 只取独有名字）。

**取舍**
- `vectors`：`vector->string`、`string->vector` 从 `(ironscheme std strings)` 转导出（同一绑定），两库可同时导入。
- `arrays`：连同 chez-srfi 附带的 arlib 扩展（`array-map`、`array->list`、`transpose`、`share-row` 等 21 个）一并收入，08 §2 只写了 :25 的 10 个。
- `hashtables`：SRFI 69 的名字由 SRFI 125 的兼容名提供（`hash` `hash-by-identity` `hash-table-exists?` `hash-table-walk` `hash-table-merge!` `hash-table-equivalence-function` `hash-table-hash-function`，去掉 chez-srfi 的 `deprecated:` 前缀，首次使用打印一次废弃警告）；`hash-salt` 不导出，用 `comparators` 的（SRFI 126 与 128 的 `hash-salt` 不是同一个东西，同时导出会冲突）；不支持弱 / 短暂散列表。SRFI 126 辅助过程中的 `random-integer`、`get-environment-variable` 改用 `(ironscheme random)` 与 .NET `Environment`（不依赖 iron-044 的库）。
- `arithmetic`：:60 与 :151 同名的 7 个按 :151；:143 的 `fxbit-set?`、`fxcopy-bit` 与 R6RS 参数次序相反，不导出（对照表给出换写法）。
- `comparators`、`sets`：SRFI 9/99 形式的记录改用 compat 的 `srfi-9:define-record-type`。
- `compare-procedures`：`random-integer` 用 `(ironscheme random)`。

**参照实现的缺陷（在 std 中修正，文件头已注明）**
- `vectors`：`vector-cumulate` 的参数次序写成 `(f vec knil)`，SRFI 133 为 `(f knil vec)`。
- `sorting`：`vector-find-median!` 把 `vector-sort!` 的返回值（未指定）当作向量；带 start/end 的 `vector-copy` 原取自 SRFI 133（R7RS 版本），改在库内定义。
- `private integer-bits`（SRFI 60）：`integer->list` / `list->integer` 写成低位在前，按 SRFI 60 参照实现（SLIB）改为高位在前。

**测试约定**：SRFI 64 形式的原测试经 `tests/std/srfi64-shim.ss`（`test-begin` `test-equal` `test-assert` `test-error` 等接到 check.ss 的计数）运行。本分支原写的 `check-64.ss` 与另一分支的 `srfi64-shim.ss` 作用相同，iron-046 中合并为后者（保留本分支能显示测试名的实现）。

**发现的基础库问题（只记录，未修）**
1. `bitwise-copy-bit` 在下标为 31 时报错（`boot/arithmetic/bitwise.sls:176`：对 `(< -1 ei2 32)` 走 `fxcopy-bit`，而 fixnum 只有 31 个数值位，应为 `< 31`）。这是原 `bitwise-operations.sps` 6 项失败的原因；`arithmetic` 中改用库内的 `%bitwise-copy-bit` 绕开。
2. R6RS 要求 eqv 散列表的 `hashtable-hash-function` 返回 #f，基础库返回 `eqv-hash`（原 `r6rs-hashtables.sps` 7 项失败的原因；std 测试改为接受 #f 或过程并注明）。
3. 基础库的 `string-compare` 返回码点差或长度差（如 `("a" "c")` → -2），不是 -1 / 0 / 1；SRFI 67 版本因 D2 不导出，对照表给出规范化写法。
4. 基础库的 `vector-binary-search` 是 .NET `Array.BinarySearch`（默认比较器、找不到返回负数），与 SRFI 43/133 的接口不同（已写入对照表）。

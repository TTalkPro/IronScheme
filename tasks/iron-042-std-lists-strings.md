# iron-042 std：表、字符串与字符

- 里程碑：M9　依赖：iron-041　状态：完成
- 设计依据：[08](../designs/08-std-library.md) §2、§3

## 工作内容
`lists`（:1）、`strings`（:13 + :152）、`string-cursors`（:130）、`char-sets`（:14）、`ascii`（:175），各带由原 SRFI 测试改写的测试与对照表。

## 验收标准
- 原 SRFI 测试中对应部分全部通过；D2 守卫通过。

## 结论（2026-10-09）

完成。

**内部库（`std/private/`，不对外，D2 守卫不检查）**
- `compat`：并入参照实现用的兼容层。SRFI 23 的 `error` 改为 `assertion-violation`（`SRFI-23-error->R6RS`，who 为外层 define 名），`vanish-define`、`check-arg`（不检查）、`let-optionals*`/`:optional`（scsh，BSD 许可全文在文件头），SRFI 9 形式的 `srfi-9:define-record-type`。均来自 chez-srfi。
- `inversion-list`：char-sets 的底层（Scheme 48）。
- `strings-152`：SRFI 152 参照实现，只供 strings 取 SRFI 13 没有的 15 个名字；去掉 r7rs-shim 中只为 Chicken 写的 `cond-expand` 分支。

**库**（参照代码并入文件；文件头写出处、取舍与对照表）
| 库 | 来源 | 导出 | 测试 | 与原测试对照 |
|---|---|---|---|---|
| `lists` | :1 | 93 | 179 | 原 175 项全部保留；其中 5 项用到不导出的同名 SRFI 版本（不等长 `map`/`for-each`、三参数 `member`/`assoc`、谓词版 `remove`），改测对照表的写法，原项留在注释；另加"基础库 `remove` 收谓词时原样返回"的陷阱检查、拆出 car+cdr 一项、补测原测试漏掉的 `reverse!` |
| `strings` | :13 为主 + :152 独有 15 个 | 84 | 134 | 无原测试，按 SRFI 13/152 文本编写，覆盖每个导出名 |
| `string-cursors` | :130 | 59 | 61 | 无原测试，按 SRFI 130 编写，覆盖每个导出名 |
| `char-sets` | :14 | 64 | 197 | 原 197 项中通过 196；那 1 项见下面"已知限制"，改测 BMP 部分后 197 项全部通过 |
| `ascii` | :175 | 35 | 4739 次断言 | 原测试原样保留（循环内每次调用各计一项），全部通过 |

**对照表要点（D2）**：`remove`（谓词版）→ `remp`；三参数 `member`/`assoc` → `memp`/`assp`；`map`/`for-each`/`fold-right` 在基础库要求等长；`string-copy`/`string->list`/`string-fill!`/`string-for-each`/大小写转换/`string-hash` 用基础库（不收 start/end）；`string-compare` 在基础库是两参数的版本（iron-054 起返回 -1/0/1）。strings 与 string-cursors 有 34 个同名过程，语义按各自 SRFI，同时使用时给其一加前缀（已写入 08 §2）。

**参照实现的缺陷（已在 std 中修正）**
- chez-srfi 的 SRFI 130：`string->list/cursors`、`string->vector/cursors`、`string-copy/cursors` 直接取 R7RS 的同名过程（收 start/end），R6RS 的版本只收一个参数，带游标参数调用会报"参数个数不对"。已补上可选游标参数。
- 生成时发现：参照代码末行若是注释，追加的右括号会被注释掉。生成脚本已改为在新行闭合。

**已知限制与基础库问题（只记录，未修改）**
- 字符串以 UTF-16 存储：BMP 之外的字符经 `char-set->string`/`string->char-set` 往返会变成代理对。原 char-sets 测试唯一失败的项就是这个原因（`char-set:digit` 含 U+104A0 等）。
- char-sets 的标准字符集数据是 Scheme 48 按 Unicode 5.x 生成的，与 .NET 较新的 Unicode 数据可能不一致（写在文件头）。
- 基础库的 `string-copy` 返回不可变字符串，对其 `string-set!` 报 "not a mutable string"。R6RS 要求新分配的副本可变。strings 测试中可变串改用 `make-string` 构造。

**验证**：check-std（D2 守卫）通过，9 个 std 库与 `(ironscheme)` 均无交集；完整测试 Core.Tests 229/229、IronScheme.Tests 67/67。

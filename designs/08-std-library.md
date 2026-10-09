# 08 `(ironscheme std …)`：把 SRFI 与 pfds 改写为按用途命名的标准库

> 参考 keel 的 `designs/std-from-srfi.md`（`~/workspace/keel`）：以 SRFI 为**词源**，不以 SRFI 为**库名**。
> 与 keel 不同的一点由用户决定：**全部保留功能**（keel 按证据只挑了 3 个库），并且**彻底删除** `(srfi …)` 与 `(pfds …)` 库名。
> 决定按 **D<n>** 编号，std 库文件头直接引用。

## §0 事实（新宿主实测，2026-10-09）

- `src/scheme/lib/srfi` 有 **70** 个编号的 SRFI（chez-srfi，多数带 Chez/Ikarus/Larceny/Ypsilon/IronScheme 等多份实现变体）；`lib/pfds` 有 **10** 个库。
- IronScheme 自己的代码几乎不用它们：`lib/diff.sls`、`lib/wak/*`（foof-loop、fmt、riastreams、trc-testing）、示例 WordCount（`playground/` 已在 iron-047 删除），用到 `:1 :6 :8 :9 :13 :25 :39 :45 :69`。
- 逐个导出名与 `(ironscheme)`（含 `(rnrs)`）比较，分三类：**新增**（`(ironscheme)` 没有）、**相同**（同一个绑定的转导出）、**冲突**（同名不同绑定 —— 同时导入即报 "two imports with different bindings"，如示例 WordCount 撞上的 `remove`）。全部数字见 §3 的表。
- 加载失败的 4 个：`:134 ideques`、`:146 mappings`、`:158 generators` 只有 Chez 实现（`import (chezscheme)`）；`:17` 只有辅助文件，没有主库。

## §1 规则

**D1 命名空间与命名**：`(ironscheme std <用途>)`，文件在 `src/scheme/lib/ironscheme/std/`。按**用途**命名（lists、strings、hashtables…），出处（SRFI 号、pfds、作者、许可）写在**文件头**，不进库名。内部辅助库为 `(ironscheme std private …)`：`compat`（并入参照实现用的兼容层：SRFI 23 的 `error`、`vanish-define`、`check-arg`、`let-optionals*`、SRFI 9 形式的记录定义）、`inversion-list`（`char-sets` 的底层）、`strings-152`（`strings` 取 SRFI 152 独有名字的来源）、`hashtables-126`（`hashtables` 的 SRFI 126 部分）、`integer-bits`（`arithmetic` 的 SRFI 60 部分）、`pfds`（pfds 的惰性表、向量、关联表、位操作辅助库合并而成）。持久（纯函数式）数据结构单独一组 `(ironscheme std persistent <结构>)`：它们与同用途的可变结构名字相近而语义不同（如 `set-union` 返回新集合 vs 线性更新），分组让导入一行就看得出是哪一种。

**D2 不与 `(ironscheme)` 冲突，也不转导出**：std 库的每个导出都是 `(ironscheme)` 里**没有**的名字。⇒ `(import (ironscheme) (ironscheme std x))` 永远不需要 `except`。SRFI 中与基础库**同名不同义**的名字一律不导出（`remove`、`string-copy`、`vector-map`、`format`、`define-record-type` …），在文件头的**对照表**里写明"你要的在 IronScheme 里叫什么"（keel D8 的做法）——尤其是静默给出错答案的那几个（`remove` 收谓词时返回原表）。名字与基础库**相同且是同一绑定**的也不再导出（它们本来就在基础库里）。

**D3 同一用途有多个 SRFI 时选一个为准**：较新的、较完整的那个为主（`:133` 优先于 `:43`，`:125` 优先于 `:69`，`:151` 优先于 `:60`，`:13` 与 `:152` 合并以 `:13` 为主）；其他 SRFI 中**同名而语义不同**的不收（如 `:43` 的 `vector-fold` 把下标作为第一个参数），**独有且语义清楚**的收进来。每个库的文件头列出收了哪些 SRFI、各取了什么、舍了什么。

**D4 实现**：以现有可移植实现（chez-srfi 的参照实现、pfds）为基础**改写**为单一的 IronScheme 版本：一个用途一个文件；`include` 进来的参照代码并入文件；去掉其他实现的兼容层与 `cond-expand` 分支；只用 `(rnrs)`、`(ironscheme …)` 与其他 std 库。语义以 SRFI 文本为准，与之不同的取舍逐条写进文件头。原作者与许可证保留在文件头，许可证全文在 `src/scheme/lib/ironscheme/std/LICENSES/`。

**D5 删除旧库名**：`(srfi …)` 与 `(pfds …)` 全部删除（含数字别名 `(srfi :1)`），`lib/srfi`、`lib/pfds` 目录删除；依赖方（wak、`lib/diff.sls`、示例、测试、`system-libraries.ss`）改用 std 名字。§3 的表就是迁移对照表，README 给出入口。

**D6 只有 Chez 实现的 SRFI**：`:158 generators` 无替代，移植到 R6RS；`:134 ideques` 与 `:146 mappings` 与 persistent 组（deques、sorted-maps、hash-maps）功能重叠，不移植（§3 写明替代）。

**D7 基础库改进**：`:45 lazy` 的 `delay`/`force` 与基础库冲突，但 riastreams 依赖其空间安全的语义 ⇒ 把基础库的 `delay`/`force` 改为 SRFI-45 / R7RS 的迭代强制（R6RS 未规定实现方式，结果对已有代码不变），std 只再提供 `lazy`、`eager`、`delay-force`。

**D8 测试**：每个 std 库一个测试脚本 `src/scheme/tests/std/<库>.sps`，由原 SRFI 测试（`lib/srfi/tests/*.sps`）与 pfds 的 `tests.scm` 改写而来；测试类别 `SRFI` 改名为 `Std`。原有的通过数是下限。公共部分：`tests/std/check.ss`（计数与报告）；`srfi64-shim.ss`（把以 SRFI 64 写成的原测试接到 check.ss，不依赖被测的 testing 库）；`trc-check.ss`（同样接入 pfds 测试所用的 trc-testing 接口）。

## §2 库的划分

| std 库 | 来源 | 说明 |
|---|---|---|
| `lists` | `:1` | 93 个新名字；冲突的 11 个（`remove` `map` `for-each` `member` `assoc` …）不导出，对照表：谓词版 `remove` → `remp`，`any`/`every` → `exists`/`for-all` |
| `strings` | `:13` 为主 + `:152` 独有 | `:152` 的 `string-split` `string-segment` `string-search-*` 等；两者重叠的 35 个按 `:13`；与基础库冲突的 `string-copy` `string-hash` … 不导出 |
| `string-cursors` | `:130` | 游标即下标；与 `strings` 有 34 个同名过程，语义按 SRFI 130（如 `string-index` 找不到时返回末端游标），同时使用时给其一加前缀 |
| `char-sets` | `:14` | |
| `ascii` | `:175` | |
| `vectors` | `:133` | `:43` 的 21 个名字全被 `:133` 覆盖（`vector-fold` 等语义不同，按 `:133`）；`vector->string`/`string->vector` 即 `strings` 的同一绑定，两库可同时导入 |
| `numeric-vectors` | `:4` | `u8vector` … `f64vector` |
| `arrays` | `:25` + arlib 扩展 | 一并收入 chez-srfi 的 arlib 扩展 21 个过程（`array-map` `array->list` `transpose` …），共 31 个 |
| `hashtables` | `:126`（`hashtable-*`）+ `:125`（`hash-table-*`） | 两族都作用于 R6RS 散列表；`:69` 的名字由 `:125` 的兼容名提供（去掉 `deprecated:` 前缀，首次使用时打印一次废弃警告）；`hash-salt` 用 `comparators` 的（`:126` 与 `:128` 的不是一回事）；不支持弱散列表与短暂散列表 |
| `sets` | `:113` | 基于比较器的集合与多重集 |
| `comparators` | `:128` | |
| `compare-procedures` | `:67` | 返回 -1/0/1 的比较过程；与 `:128` 有 5 个同名不同义（`<?` …），所以分开 |
| `sorting` | `:132` | 17 个新名字；`list-sort` `vector-sort` `vector-sort!` 用基础库的 |
| `arithmetic` | `:141` + `:143` + `:151` 为主 + `:60` 独有 | 整数除法、fixnum 补充、位运算；`:60` 与 `:151` 同名不同义的（`copy-bit` …）按 `:151` |
| `syntax` | `:0` `:2` `:8` `:15` `:31` `:145` | `cond-expand` `and-let*` `receive` `fluid-let` `rec` `assume` |
| `procedures` | `:26` `:156` `:51` + `:102` 独有 | `cut` `cute` `is` `isnt`、剩余参数处理、`procedure-arity-includes?` 等 |
| `records` | `:99` 的过程部分 | `make-rtd` `rtd-*`；`define-record-type` 用 R6RS 的 |
| `conditions` | `:35` 独有 | `make-condition-type` `condition-ref` …；在 R6RS 条件之上按 SRFI 35 文本重写（参照实现自带一套并行的条件系统，D2 不导出其同名名字后无法使用）：条件类型即 `&condition` 子类型的记录类型描述符，可直接配合 `raise`、`guard` |
| `boxes` | `:111` | |
| `lazy` | `:45` | `lazy` `eager` `delay-force`（D7） |
| `streams` | `:41` | |
| `lazy-sequences` | `:127` | |
| `generators` | `:158`（移植，D6） | `make-coroutine-generator` 需要可重入续延，新系统只有逃逸续延：改为 proc 在后台线程运行、与调用方用两个信号量严格交替；限制：`parameterize` 的参数在 proc 中不可见 |
| `comprehensions` | `:42` | |
| `time` | `:19` | 修正参照实现两处缺陷（`time-difference!` 总报类型不符、`date->julian-day` 括号错位）；时区偏移取自系统时区 |
| `random` | `:27` | |
| `testing` | `:64` + `:78` | 两者无同名过程，全部导出；`check-ec` 依赖 `comprehensions`，用户须自行导入 `:range` 等；`test-log-to-file` 为存取过程，缺省不写日志 |
| `regexp` | `:115` | SRE 正则；.NET 正则另见 `(ironscheme regex)`；字符类按 ASCII；不再依赖 `:69` |
| `args` | `:37` | 命令行选项解析 `args-fold` |
| `system` | `:98` + `:112` | 环境变量、实现信息；`:112` 各项取 IronScheme 的实际值，体系结构名与 `cond-expand` 的特性同名 |
| `localization` | `:29` | SRFI 29 自带的 `format`（支持位置参数 `~n@*`）与基础库同名，不导出；基础库的 `format` 不支持 `~n@*` |
| `format` | `:54` | `cat`；`format` 用基础库的 |
| `ports` | `:6` 独有 + `:38` | `open-input-string`；带共享结构的读写 |
| `persistent lists` | `:116` | 不可变序对 `ipair` … |
| `persistent random-access-lists` | `:101` | 44 个与基础库同名的表操作改名加 `ra-` 前缀（`ra-car` `ra-cons` `ra-map` …）；`ra-quote` 是语法 |
| `persistent queues` / `deques` | pfds queues / deques | |
| `persistent sorted-maps` | pfds bbtrees | 名字保持 `bbtree-*` |
| `persistent sets` | pfds sets | 与 `sets`（SRFI 113）有同名过程而语义不同，同时使用时给其一加前缀 |
| `persistent difference-lists` | pfds dlists | |
| `persistent priority-search-queues` | pfds psqs | |
| `persistent finger-trees` / `sequences` | pfds fingertrees / sequences | |
| `persistent heaps` | pfds heaps | |
| `persistent hash-maps` | pfds hamts | 修正了 pfds HAMT 的五处缺陷（原实现随机键查找约 9% 出错），见 iron-045 结论 |
| `queues` | `:117` | 可变的表队列 |

## §3 逐个 SRFI 的裁决（70 个，一个不漏）

新/同/冲 = 新增 / 与基础库同一绑定 / 同名不同绑定 的导出个数。

| SRFI | 新/同/冲 | 去向 |
|---|---|---|
| `:0 cond-expand` | 1/0/0 | `syntax` |
| `:1 lists` | 93/45/11 | `lists` |
| `:2 and-let*` | 1/0/0 | `syntax` |
| `:4 numeric-vectors` | 80/0/0 | `numeric-vectors` |
| `:5 let` | 0/0/1 | ⛔ 不收：基础库 `let` 已含命名 let |
| `:6 basic-string-ports` | 1/2/0 | `ports` |
| `:8 receive` | 1/0/0 | `syntax` |
| `:9 records` | 0/0/1 | ⛔ 不收：R6RS `define-record-type` |
| `:11 let-values` | 0/2/0 | ⛔ 不收：基础库已有 |
| `:13 strings` | 69/8/9 | `strings`（为主） |
| `:14 char-sets` | 64/0/0 | `char-sets` |
| `:15 fluid-let` | 1/0/0 | `syntax` |
| `:16 case-lambda` | 0/1/0 | ⛔ 不收：基础库已有 |
| `:17 generalized set!` | — | ⛔ 不收：无主库，且重定义 `set!` 与基础库冲突 |
| `:19 time` | 80/0/0 | `time` |
| `:23 error` | 0/0/1 | ⛔ 不收：基础库 `error` |
| `:25 multi-dimensional-arrays` | 10/0/0 | `arrays` |
| `:26 cut` | 4/0/0 | `procedures` |
| `:27 random-bits` | 11/0/0 | `random` |
| `:28 basic-format-strings` | 0/0/1 | ⛔ 不收：基础库 `format` |
| `:29 localization` | 8/0/0 | `localization` |
| `:31 rec` | 1/0/0 | `syntax` |
| `:34 exception-handling` | 0/0/3 | ⛔ 不收：R6RS `guard` `raise` |
| `:35 conditions` | 7/0/11 | `conditions`（只收 7 个新增） |
| `:37 args-fold` | 7/0/0 | `args` |
| `:38 with-shared-structure` | 4/0/0 | `ports` |
| `:39 parameters` | 0/2/0 | ⛔ 不收：基础库已有 |
| `:41 streams` | 37/0/0 | `streams` |
| `:42 eager-comprehensions` | 37/0/0 | `comprehensions` |
| `:43 vectors` | 21/6/9 | ⛔ 不收：被 `:133` 覆盖（D3） |
| `:45 lazy` | 2/0/2 | `lazy` + 基础库 promise 改为迭代强制（D7） |
| `:48 intermediate-format-strings` | 0/0/1 | ⛔ 不收：基础库 `format` |
| `:51 rest-values` | 9/0/0 | `procedures` |
| `:54 cat` | 1/0/0 | `format` |
| `:60 integer-bits` | 24/5/0 | `arithmetic`（只收 `:151` 没有的） |
| `:61 cond` | 0/0/1 | ⛔ 不收：R6RS `cond` 已含 `=>` |
| `:64 testing` | 72/0/0 | `testing` |
| `:67 compare-procedures` | 58/0/1 | `compare-procedures` |
| `:69 basic-hash-tables` | 22/0/2 | ⛔ 不收：被 `:125` 的兼容名覆盖（D3） |
| `:78 lightweight-testing` | 6/0/0 | `testing` |
| `:98 os-environment-variables` | 2/0/0 | `system` |
| `:99 records` | 11/2/1 | `records`（过程部分） |
| `:101 random-access-lists` | 4/0/44 | `persistent random-access-lists`（冲突名加 `ra-`） |
| `:102 procedure-arity` | 3/0/1 | `procedures`（只收 3 个新增；`procedure-arity` 用基础库的） |
| `:111 boxes` | 4/0/0 | `boxes` |
| `:112 environment-inquiry` | 6/0/0 | `system` |
| `:113 sets-and-bags` | 113/0/0 | `sets` |
| `:115 regexp` | 23/0/0 | `regexp` |
| `:116 ilists` | 125/0/0 | `persistent lists` |
| `:117 list-queues` | 23/0/0 | `queues` |
| `:125 hashtables` | 46/0/0 | `hashtables` |
| `:126 r6rs-hashtables` | 24/14/7 | `hashtables` |
| `:127 lazy-sequences` | 29/0/0 | `lazy-sequences` |
| `:128 comparators` | 32/3/0 | `comparators` |
| `:129 titlecase` | 0/0/3 | ⛔ 不收：基础库已有 |
| `:130 string-cursors` | 59/0/0 | `string-cursors` |
| `:131 records` | 0/0/1 | ⛔ 不收：R6RS `define-record-type` |
| `:132 sorting` | 17/0/3 | `sorting` |
| `:133 vectors` | 28/2/7 | `vectors` |
| `:134 ideques` | — | ⛔ 不收：只有 Chez 实现；用 `persistent deques`（D6） |
| `:141 integer-division` | 18/0/0 | `arithmetic` |
| `:143 fixnums` | 12/30/2 | `arithmetic`（只收 12 个新增） |
| `:145 assumptions` | 1/0/0 | `syntax` |
| `:146 mappings` | — | ⛔ 不收：只有 Chez 实现；用 `persistent sorted-maps` / `hash-maps`（D6） |
| `:151 bitwise-operations` | 34/5/0 | `arithmetic`（为主） |
| `:152 strings` | 50/9/14 | `strings`（只收 `:13` 没有的） |
| `:156 predicate-combiners` | 2/0/0 | `procedures` |
| `:158 generators-and-accumulators` | — | `generators`（从 Chez 实现移植，D6） |
| `:175 ascii` | 35/0/0 | `ascii` |
| `:219 define` | 0/0/1 | ⛔ 不收：柯里化的 `define` 与基础库冲突 |

收 **52** 个，不收 **18** 个：基础库已覆盖 12（`:5 :9 :11 :16 :23 :28 :34 :39 :48 :61 :129 :131`）、被同族较新的 SRFI 覆盖 2（`:43 :69`）、只有 Chez 实现且功能重叠 2（`:134 :146`）、无主库 1（`:17`）、与基础库语法冲突 1（`:219`）。共得到 **34** 个 std 库与 **12** 个 `persistent` 库（pfds 10 个 + `:101` + `:116`）。

## §4 依赖方的迁移

| 依赖方 | 原来 | 改为 |
|---|---|---|
| `lib/wak/foof-loop*`、`fmt*`、`trc-testing*`、`lib/diff.sls` | `:1` `:6` `:8` `:9` `:13` `:39` `:69` | `lists` `ports` `syntax` R6RS `strings` 基础库 `hashtables` |
| `lib/wak/riastreams` | `:45` | `lazy` + 基础库 `delay`/`force`（D7） |
| 示例 WordCount、测试 `repl-hooks.sps`、`LineEditorTests` | `(srfi :1 lists)` | `(ironscheme std lists)` |
| `system-libraries.ss`、`system-libraries.srfi.ss` | 135 个 srfi / pfds 库 | std 库清单 |
| 测试类别 `SRFI` | 24 个 `lib/srfi/tests/*.sps` | `Std`：`tests/std/*.sps` |

## §5 落地顺序

| 任务 | 内容 |
|---|---|
| iron-041 | 基础：std 目录、许可证、测试约定、基础库 promise 改为迭代强制（D7）、`syntax` `procedures` `boxes` `lazy` |
| iron-042 | 表、字符串与字符：`lists` `strings` `string-cursors` `char-sets` `ascii` |
| iron-043 | 向量、散列表、比较、排序与算术：`vectors` `numeric-vectors` `arrays` `hashtables` `sets` `comparators` `compare-procedures` `sorting` `arithmetic` |
| iron-044 | 惰性与其他：`streams` `lazy-sequences` `generators` `comprehensions` `records` `conditions` `time` `random` `testing` `regexp` `args` `system` `localization` `format` `ports` `queues` |
| iron-045 | persistent：pfds 10 个库与 `:101` `:116` |
| iron-046 | 删除 `lib/srfi`、`lib/pfds`，迁移依赖方，更新系统库清单、测试类别与文档 |

# iron-045 std：持久数据结构

- 里程碑：M9　依赖：iron-041　状态：完成
- 设计依据：[08](../designs/08-std-library.md) §1 D1、§2

## 工作内容
`(ironscheme std persistent …)`：pfds 的 queues、deques、bbtrees（sorted-maps）、sets、dlists（difference-lists）、psqs（priority-search-queues）、fingertrees（finger-trees）、sequences、heaps、hamts（hash-maps），以及 `:101`（random-access-lists，冲突名加 `ra-`）、`:116`（lists）。测试由 pfds 的 `tests.scm` 与 SRFI 测试改写。

## 验收标准
- pfds 原测试（255 项）改写后全部通过；D2 守卫通过。

## 结论（2026-10-09）

完成。12 个库在 `src/scheme/lib/ironscheme/std/persistent/`，测试为 `src/scheme/tests/std/persistent-<库>.sps`。

**库与测试**

| 库 | 来源 | 导出 | 测试项 | 原测试 |
|---|---|---|---|---|
| `queues` | pfds queues | 9 | 17 | 9 |
| `deques` | pfds deques | 11 | 35 | 13 |
| `sorted-maps` | pfds bbtrees（名字保持 `bbtree-*`） | 21 | 64 | 43 |
| `sets` | pfds sets | 21 | 45 | 38 |
| `difference-lists` | pfds dlists | 7 | 11 | 无（按 `doc/dlists.scm` 编写） |
| `priority-search-queues` | pfds psqs | 14 | 54 | 53 |
| `finger-trees` | pfds fingertrees | 17 | 46 | 43 |
| `sequences` | pfds sequences | 23 | 30 | 4 |
| `heaps` | pfds heaps | 15 | 28 | 25 |
| `hash-maps` | pfds hamts | 14 | 94 | 27 |
| `lists` | SRFI 116 ilists | 125 | 199 | 199 |
| `random-access-lists` | SRFI 101 | 48 | 80 | 50 |

- pfds 原测试 255 项全部改写并通过（共 413 项；改写后计的是实际执行的断言数）。原测试没有覆盖的导出名都补了测试，每个导出名至少一项（脚本检查）。
- D2 守卫：12 个库与 `(ironscheme)` 都没有交集。

**做法**
- pfds 的四个辅助库（lazy-lists、vectors、alists、bitwise）合并为内部库 `(ironscheme std private pfds)`。queues、deques 的条件类型库并入各自的库。sets 导入 sorted-maps，sequences 导入 finger-trees。pfds 原文件的说明与版权声明保留在各库文件中，许可证见 `LICENSES/pfds.txt`。
- pfds 的 `alists` 用的是 SRFI 1 的三参数 `assoc`；`(ironscheme std lists)` 不导出它（D2），改用 `assp`。
- `random-access-lists`：SRFI 101 中与基础库同名的 44 个名字加 `ra-` 前缀导出（`ra-quote` 是语法）。其余 4 个名字保持原名：`list-set`、`list-ref/update`、`random-access-list->linear-access-list`、`linear-access-list->random-access-list`。
- `random-access-lists` 的原测试用 `(srfi :101)` 遮蔽了基础库的 `car`、`quote` 等，这里机械改写：这 44 个名字换成 `ra-` 版本，`'数据` 换成 `(ra-quote 数据)`，`r6:` 前缀的基础库名去掉前缀。另补了 28 个 `ra-c…r` 的测试：用深度为 4 的完全二叉树，叶子名即访问路径。
- `lists`（SRFI 116）：SRFI 9 形式的记录定义取自 `(ironscheme std private compat)`；`set-car!`、`set-cdr!` 取自 `(rnrs mutable-pairs)`。
- pfds 测试所用 trc-testing 的接口，由 `tests/std/trc-check.ss` 模拟（与 `check.ss` 一起 `include`）。

**发现并修正的问题**
- **pfds 的 HAMT（`hash-maps`）有五处缺陷**，原测试键少、散列值小，没有暴露。用随机键与关联表对照试验时，约 9% 的查找出错（插入、删除交替时更多）：
  1. `mask` 先取低 5 位再右移，次序反了，第二层起下标恒为 0；
  2. 叶子或冲突节点拆成子树后，按下一层继续插入，层次错开一层；子树中的叶子与冲突节点又按本层处理；
  3. 子树的向量是压缩存储的，插入、删除时却按位号而不是按位置（`ctpop`）改写向量；删除最后一个元素后判断"子树已空"时，检查的是旧向量；
  4. 冲突节点保存的是右移到本层后的散列值，而不是完整散列值；
  5. 负的散列值算术右移永远得不到 0。现在散列值先截成 32 位非负整数，截断造成的冲突由冲突节点按等价谓词区分。

  修正后，以三种散列分布（小范围多冲突、带符号 32 位、大整数）各做数百组随机的插入、更新、删除序列，结果与关联表完全一致。精简版（60 组）固定在测试中，另有一项负散列值的确定性回归测试。逐处修正都注明在库文件头与代码中。
- **pfds 原测试中有 7 项断言从未执行过**：trc-testing 里，带 `()` 的 `define-test-case` 中嵌套的 `test-case` 只被构造、不被运行。其中 bbtrees 的 3 项期望本身就写错了（`bbtree-update` 返回新树而不是值），已改为对返回的树取值；hamts 的 4 项在新实现下通过。
- sorted-maps、priority-search-queues、heaps、sequences、sets 也做了同样的随机对照试验（各数百组），没有发现问题。

**基础库的偏差（只记录，未修）**
- `string-hash` 返回负数，而且同一字符串在不同进程中的值不同（直接取 .NET 的 `GetHashCode`，它按进程随机化）。R6RS 要求散列过程返回非负精确整数。依赖它作为散列过程的代码（如 pfds 的 HAMT）可能出现时有时无的错误。

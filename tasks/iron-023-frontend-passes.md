# iron-023 前中端 pass

- 里程碑：M4　依赖：iron-022　状态：完成
- 设计依据：[03 §4](../designs/03-compiler.md) 第 2 ~ 5 步

## 目标
实现 `recognize-let`、`simplify-letrec`、`cp0-lite`、`convert-assignments`。

## 工作内容
1. 四个 pass 及其中间语言。
2. `cp0-lite` 只折叠原语表标为 `pure` 的 fixnum/flonum/谓词运算，结果经中立编码可表示。
3. 快照测试。

## 验收标准
- boot 源文件全部通过；L2 中不存在对被捕获变量的 `set!`（由文法保证）。

## 结论（2026-10-08）

完成（`front.sls`）。

- **analyze**：L0 上一遍自底向上的自由变量计算，记录被 `set!` 的词法变量、出现在某个 lambda 自由变量中的（被捕获的）变量、每个 letrec 右边引用的同组变量、被 `mset!` 的库变量。
- **recognize-let 与 simplify-letrec 合为一个 pass**（L0 → L1）：`((lambda (x …) body) e …)` → `let`；letrec（按 letrec* 语义）中连续的、未被赋值的 lambda 绑定成为一组 `letrec`，其余为 `let`；右边引用了此后才绑定且不在同一组的变量时，这些"前向变量"先在外层绑定为未指定值，到位置再 `set!`。库变量（library-letrec*）是静态字段，不经此处理。
- **cp0-lite**：`if` 的常量测试、`begin` 中的常量去除、`not`/`null?`/`pair?`/`eq?`/`fixnum?` 与 `$fx` 算术比较的常量折叠（结果为可编码常量；`$fx` 溢出时不折叠）。折叠在编译器中用 Scheme 计算，不执行目标原语。
- **convert-assignments**：既被赋值又被捕获的变量改为 Box；形参在子句入口 `(set! x (box x))`。L2 中对这类变量的 `set!` 由该 pass 消除，代码生成时若遇到对被捕获变量的 `set!` 会报错（nanopass 文法无法区分"被捕获"，所以由 pass + 代码生成检查保证，而不是文法）。

验收：`compiler/tests/front-seed.sps`——种子 38 个形式全部通过四个 pass；样例中前向变量被装箱、常量被折叠。快照 `*.l2`。

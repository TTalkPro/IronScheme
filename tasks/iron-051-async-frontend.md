# iron-051 异步：展开器、parse-core 与 `lower-async`

- 里程碑：后续　依赖：iron-050　状态：未开始
- 设计依据：[10 §1](../designs/10-async.md) D1 ~ D2、[10 §3.1 ~ 3.2](../designs/10-async.md) D9 ~ D11

## 目标
让 `async-lambda` / `define-async` / `await` 从源码一路走到 L3，并由新 pass `lower-async` 把 async 体整理成 codegen 能直接生成状态机的形状。本任务结束时 codegen 对这些节点还只是报"未实现"，但 `lower-async` 的输出可以用 `IRONSCHEME_DUMP_PASSES` 检查。

## 工作内容
1. **展开器**：核心宏 `async-lambda`（`boot/expander/core.sls`，与 `lambda` 的转换器并列；在 `ironscheme-buildscript-nano.sps` 的 `expander-system-macros` 与 `identifier->library-map` 登记）；builders 产生 Lcore `(async-lambda fmls body)`；`define-async` 是普通 `syntax-rules` 宏。`await` 加入 PrimGen 的 `specials`（种类 `await`），重新生成 `primitives.ss`，经 `(ironscheme)` 导出。
2. **`rewrite`**（`boot/expander/internal.sls`）：像 `lambda` 一样显式走 `async-lambda` 的形参与体。
3. **parse-core**（`compiler/parse.sls`）与 **L0**（`languages.sls`）：节点 `(async-lambda nm (x* …) (maybe x) body)` 与 `(await e)`；再加 `lower-async` 产生的 `(label f (x* …) body fbody)`、`(jump f e* …)`、`(escape-frame k body)`。
4. **`lower-async`**（新文件 `compiler/async.sls`，L0 → L0，接在 parse-core 之后）：
   - 单元里没有 `async-lambda` 时恒等返回；
   - D9：letrec/letrec* 绑定的 lambda 的引用分析（全部是尾位置、参数个数相符的调用 ⇒ `label`/`jump`）；
   - D10：五种内联（立即调用的 lambda、`dynamic-wind`、`with-exception-handler`、`call-with-values`、`call/cc`），按绑定身份识别；实参是 let/letrec 绑定的 lambda 且全部引用都在内联位置时也内联并删除绑定；
   - D11：拆分，`await` 只留在语句位置；`and`/`or` 含 await 时改写为 `if`；
   - D2：剩余的、处于普通 lambda 体内的 `await` 报错，错误信息说明原因（嵌套 lambda / 非尾位置循环 / 参数个数不符 / finally 或处理器体内）。
5. **各 pass 透传**：`analyze`、`simplify-letrec`、`check-forward`、`cp0-lite`、`convert-assignments`、`uncover-free` 对新节点的处理（`async-lambda` 按 lambda；`label` 的参数是绑定变量；`escape-frame` 的 `k` 是绑定变量）。
6. 更新 [03 §2](../designs/03-compiler.md) 的 Lcore 文法和 §4 的 pass 表。

## 验收标准
- `compiler/tests/` 新增 `lower-async` 的快照测试：命名 let、`do`、`parameterize`、`dynamic-wind`、`guard`、`with-exception-handler`、操作数位置的 await、`and`/`or` 各一个用例，比对 `.l0` dump。
- 错误用例：`(for-each (lambda (x) (await x)) l)`、非尾位置调用的循环、finally 里的 await，各给出预期错误信息。
- 编译整个种子的统计输出（类数、方法数、指令数）与改动前相同。

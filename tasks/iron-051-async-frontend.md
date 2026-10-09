# iron-051 异步：展开器、parse-core 与 `lower-async`

- 里程碑：后续　依赖：iron-050　状态：完成
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

## 结论
- 展开器：`core.sls` 加核心宏 `async-lambda`（`async-lambda-transformer`，与 `lambda` 并列）与普通宏 `define-async`；`builders.sls` 加 `build-async-lambda`（Lcore `(async-lambda fmls body)`，暂无注解变体）；`rewrite` 显式走 `async-lambda`；两个构建脚本的 `expander-system-macros` 与 `identifier->library-map` 登记 `async-lambda`、`define-async`、`await`；PrimGen 的 `specials` 加 `await`（`primitives.ss` 已重新生成，11 个特殊原语）；种子已重新生成。stage0 不解释 `async-lambda`（不需要：boot 与构建脚本里没有）。
- 编译器：L0 加 `async-lambda`（LambdaExpr，单子句）、`await`、`label`、`jump`、`escape-frame`，并把 `let` 从 L1 提前到 L0（lower-async 的输出要用）；L3 的 `async-lambda` 带自由变量表。新 pass `compiler/async.sls`（`lower-async`，L0 → L0，接在 parse-core 之后，`IRONSCHEME_DUMP_PASSES` 的 `.la` 是它的输出）；analyze / simplify-letrec / convert-assignments / uncover-free 透传（`label` 的形参被装箱时 `jump` 传新 Box）；codegen 对这些节点报 "not supported by codegen yet (iron-052)"。
- 与设计的出入（已写回 [10 §3.2](../designs/10-async.md)、[03 §2、§4.1](../designs/03-compiler.md)）：`dynamic-wind` / `with-exception-handler` 按全局位置符号的名字识别（编译器拿不到绑定身份）；只降级单绑定的 letrec，互相递归的局部过程保持 lambda；嵌套普通 lambda 的体完全不变换；D9 / D10 在 async 体内无条件进行；`((letrec ((f le)) f) e …)`（命名 let 的实际展开形状）先归一成 `(letrec ((f le)) (f e …))`。
- 验收：`tests/compiler/async-snapshots.sps`（9 个用例 × la / l2 / l3 快照，7 个错误用例：for-each 回调、非尾位置循环、参数个数不符、当值使用、finally 里的 await、互相递归、async-lambda 之外的 await）全部通过；原有 `snapshots.sps` 不变；`slow-compile-seed.sps` 的统计与改动前相同（2360 个类、2530 个方法、158918 条指令）；`define-async` 端到端：展开 → lower-async 输出正确，codegen 按预期报未实现。

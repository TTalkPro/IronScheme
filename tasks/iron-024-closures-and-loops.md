# iron-024 闭包转换、类提升与循环降级

- 里程碑：M4　依赖：iron-023　状态：完成
- 设计依据：[03 §4](../designs/03-compiler.md) 第 6 ~ 9 步、[02 §4](../designs/02-runtime.md)

## 目标
把 lambda 变成 `Procedure` 子类与静态方法，自尾调用变成循环。

## 工作内容
1. `uncover-free`、`convert-closures`（扁平闭包；无自由变量者提升为静态方法 + 单例；已知调用直接化）。
2. `lift-to-classes`：模块入口 `Initialize`；`library-letrec*` 绑定写入 loc 值槽。
3. `lower-loops`：自尾调用、命名 let、`do`。
4. case-lambda 与剩余参数对应的 `InvokeK` / `InvokeN` 重写方案。

## 验收标准
- 快照测试；类数量、静态方法比例的统计输出。

## 结论（2026-10-08）

完成（`closures.sls` 的 uncover-free；convert-closures、lift-to-classes、lower-loops 在 `codegen.sls` 中）。

- **过程类**：每个 lambda 一个 Procedure 子类，有剩余参数子句时基类为 VariadicProcedure；子句体为方法 `C0`、`C1` …；`Invoke0..4` 转发到第一个参数个数匹配的固定参数子句（`tail. call`）；有剩余参数或参数多于 4 的子句时重写 `InvokeN`，按子句顺序分派，剩余参数用 `RestList` 打包，都不匹配时 `ArityError`。
- **静态与闭包**：无自由变量的 lambda 子句方法为静态方法，实例为单例（`.cctor` 创建、静态字段 `Instance`）；有自由变量的为实例字段 `c0 …`。letrec 绑定的 lambda 引用自己时用 `this`（或 `Instance`），不占字段——命名 let 循环因此通常是静态的。letrec 组先创建全部对象再填字段，支持互相引用。
- **模块**：库变量为模块类型的静态字段；每个顶层形式一个 `Init<k>` 静态方法，入口 `Initialize` 依次调用。库中无自由变量且不被再赋值的 lambda 是**已知过程**：入口先预链接（把全部已知过程写入字段与位置 loc，等同旧 boot 编译器的静态链接，种子中的跨库前向引用因此成立），参数个数相符的调用直接 `call` 静态子句方法。
- **循环**：自尾调用（letrec 中的自己，或已知过程调用自己）在尾位置、参数个数与当前子句相同时，重新赋参数并跳回方法开头的标签。`do` 与命名 let 都经此成为循环。

验收（统计，`compiler/tests/slow-compile-seed.sps` 编译整个种子）：**2269 个过程类，其中静态 / 单例 1416 个（62%），闭包 853 个；子句方法 2433 个，静态 1574 个**；指令 14.2 万条；常量 2887 个。快照 `*.l3`、`*.lcil`。

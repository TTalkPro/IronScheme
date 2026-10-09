# iron-034 编译器深度优化

- 里程碑：后续（M7 之后）　依赖：iron-033（已完成）、iron-057（已完成：codegen 的类名与 `tail.` 已经查表，新增的生成形状要进 `targets.sls`）　状态：未开始（设计已定，见下）
- 设计依据：[03 §4 末尾](../designs/03-compiler.md)、[02 §4](../designs/02-runtime.md)、[10 §3.2 D9](../designs/10-async.md)（`label` / `jump`）

## 目标
在 iron-033 消除运行时开销之后，提升生成代码本身的质量：少几次间接调用、少装箱、少一些类型。每一项都要先量后改，用同一组基准验收，不能让自举不动点与整套测试退步。

## §0 事实（2026-10-09，编译当前种子的 boot 镜像）

| 项 | 数 | 说明 |
|---|---|---|
| 过程类 | 2360 个，其中 1451 个是无自由变量的静态单例，908 个闭包 | 每个 lambda 一个类；boot 镜像加载时要建这么多类型 |
| 命名 let 类 | 约 156 个（类名以 `$loop`、`$f` 等结尾） | 每个命名 let 一个类，自尾调用在类内是循环，但进入循环要 `newobj` 或取单例再 `callvirt` |
| 子句方法按形参个数 | 0：379，1：1012，2：655，3：325，4：93，5：34，6：8，7：9，8：8，更多：5 | 4 个以上的只占 2.5%，`Invoke0..4` 的上限不必动 |
| 直接 `call` 子句方法（已知过程） | 5666 处 | 库内无自由变量、不被再赋值的过程，参数个数相符 |
| 间接 `callvirt Invoke0..4` | 5421 处 | 跨库调用、闭包调用、过程当值用后的调用 |
| 间接 `callvirt InvokeN` | 398 处 | 打包数组 |
| `tail.` 前缀 | 4734 处 | |
| 取全局位置的值（`Calls.Global`） | 4623 处 | 其中大半是跨库引用导出的过程：先 `ldconst` 符号 → 读值槽 → `Calls.Proc` 转型 → `callvirt` |
| 装箱 fixnum（`RT.Box`） | 3078 处 | 拆箱 `unbox.any Int32` 742 处、`Double` 217 处：算术内联模板的结果立刻装回 |

剖析方法（iron-033 留下的）：`dotnet tool install -g dotnet-trace`，`dotnet-trace collect --format speedscope -- dotnet IronScheme.Host.dll …`；`tail.` 调用会抹掉中间帧，看到的调用者可能是更外层的过程。

## §1 决策

**D1 先量后改，一组固定基准**。新建 `tests/perf/`（不进 `dotnet test`，手动跑）：`boot-load`（启动到 REPL 可用的毫秒数）、`compile-seed`（`slow-compile-seed.sps` 的 front end + codegen 毫秒数）、`r6rs-run`（`tests/r6rs/run.sps` 总时间）、`fib`（`(fib 30)` 的 fixnum 递归）、`fl-loop`（一百万次 flonum 累加的命名 let）、`wordcount`（大文件）。每个子任务开始前后各跑三次取中位数写进任务书。基准脚本本身是第一个交付物（iron-034a）。

**D2 局部循环降级推广到普通代码**（对应候选 6 的一半，复用 iron-051 的 D9）。`lower-async` 里单绑定 letrec 的 lambda 若全部引用都是参数个数相符的尾调用，就变成 `(label f (x …) body fbody)` + `(jump f e …)`；现在只在 async 体内开。改成**对所有 lambda 体都做**：pass 改名为 `lower-loops`（仍在 `async.sls` 里实现，或拆出 `loops.sls`），对普通 lambda 只做 D9（不做 D10 内联、不做 D11 拆分）。codegen 的同步上下文要支持 `label` / `jump`：形参是 IL 局部变量（async 下是帧字段），`jump` 先把实参全部求值到临时变量再写回（并行赋值）再 `br`；跳出 try 区域的 jump 由 lower-loops 的"跨 try 的调用不算尾调用"规则排除，和 async 一样。效果：156 个命名 let 类消失，循环入口不再 `newobj` / `callvirt`，循环变量仍是 IL 局部变量（为 D4 的拆箱铺路）。`convert-assignments` 对被捕获又被赋值的循环变量已经会在 `jump` 处新建 Box（iron-051），语义不变。

**D3 无自由变量的过程共享一个类**（候选 6 的另一半）。无自由变量的 lambda 现在是"静态方法 + 单例子类"；改成子句方法放进模块类（或每 N 个一个共享类，避免单个类型过大），过程对象用一个通用的 `IronScheme.Core.StaticProcedure`（持有 `Func<…>` 委托、`Arity`、`Form`、`Name`）在模块初始化时创建并存进静态字段 / 位置。直接调用（`call C0`）不变；`Invoke0..4` 经委托多一次间接（委托调用 ≈ 虚调用，持平）。代价：`Form` / `Name` / `Arity` 要作为数据传给构造函数而不是 override，`procedure-name` 等不变。先量 boot 加载时间里类型加载占多少（D1 的 `boot-load`），若不到 20% 就不做。

**D4 fixnum / flonum 拆箱**（候选 2）。新 pass `infer-types`（L2 之后，输出 L2 带类型标注，或 L3 的 `let` 带类型）：
- 来源：fixnum 常量、`$fx…` / `$fl…` 原语的结果（原语表要加结果类型，PrimGen 从 C# 方法的返回类型或新属性 `Result = "fixnum"` 生成，见 03 §4 末尾对 Chez `primdata.ss` 签名的说明）、`(fixnum? x)` 测试为真的分支里的 `x`（流敏感只做这一种）。
- 汇点：`let` 绑定的、不被捕获、不被赋值的局部变量，全部定义点都是 fixnum（或都是 flonum）时标为 `int32` / `double`；`label` 的形参同理（所有 `jump` 实参同类型，这是 D2 的回报）。
- codegen：标了类型的局部变量用对应类型的 IL 局部变量，读时不拆箱、写时不装箱；作为 `object` 使用的位置（传参、存字段）装箱。`$fx+` 等内联模板的操作数若是已拆箱变量直接 `ldloc`。
- 不做：跨过程的类型（参数仍是 `object`）、浮点以外的数值塔、数组元素类型。
- 先在 `fib` / `fl-loop` 上量收益；预期 fixnum 循环快 2 ~ 3 倍。

**D5 跨库直接调用**（候选 1，最大的改动）。原则：编译器仍不读运行时状态（05 §6），被调库的信息来自**接口文件**。
- 库编译为 `.fasl` / dll 时同时写出 `库名.ifc`（S 表达式）：每个导出的已知过程的 `(符号 类名 子句形状 …)` 与库的编译实例 id（现有 `library-spec` 的 id）。
- 编译导入了它的单元时，若找到 `.ifc` 且其 id 与展开器实际装入的库实例一致，`collect-known!` 把这些导出也登记为已知过程；调用参数个数相符时直接 `call 类::C0`（codegen 已经支持跨单元的类名引用，预链接写入位置的机制不变）。
- 失效：程序 / 库记录依赖的编译实例 id（现有机制，`load` 时"requires a different compilation of a library"），直接调用的静态绑定由同一检查保护，不需要新的失效逻辑。
- boot 镜像内的库互相之间：已经在同一编译单元里，收益在用户库与 std 库对 boot 导出的调用（§0 的 4623 处 `Calls.Global` 里的大半）。boot 镜像自己的 `.ifc` 由 nano 构建脚本一起写出。
- 风险：`.ifc` 过期、`define` 覆盖（`set-symbol-value!`）导出名的旧习惯——只对不被 `mset!` 且库里没有再赋值的导出做，和现在库内的规则一致；REPL 里重定义导出名只影响经位置的调用（和 Chez 的行为一致，文档写明）。

**D6 小项**（候选 3、4、5）：
- `Invoke0..4` 上限不动（§0：4 个以上只占 2.5%）。
- 已知 RTD 的访问器内联为字段读：记录字段现在是 `object[]`（`Record.Fields`），访问器调用 `callvirt Invoke1` + 下标检查；展开器知道 RTD 时可以直接生成 `($record-ref r k)` 原语调用并内联成 `ldfld Fields; ldelem.ref`。要先看 `define-record-type` 的展开里有没有 RTD 的静态信息可用，否则放弃。
- `call-with-values` 消费者为字面 lambda 时内联为 `let`（多值用 `MultipleValues` 拆开），这在 03 §6 原本就写了"可内联"，现在没做。
- `typed-lambda` 利用类型说明：等 D4 的类型标注有了再做，强类型子句方法是 D4 的自然延伸。
- 序列点：调试信息，不属于性能，另开任务。

**D7 顺序与取舍**：iron-034a 基准 → 034b D2（最便宜，复用现成 pass）→ 034c D4（收益最直观）→ 034d D3（先量类型加载占比）→ 034e D5（最大、最后）。每一步单独可交付；任何一步基准不劣化、测试全过才合入。

## 工作内容
1. **iron-034a 基准**：`tests/perf/` 六个脚本与一个 `run-all.sps`（打印表格），任务书记录当前数字。
2. **iron-034b `lower-loops`**：把 D9 推广到普通 lambda；codegen 同步上下文的 `label` / `jump`；快照测试加命名 let、`do`、带捕获变量的循环三个用例；种子统计里 `$loop` 类应减到接近 0。
3. **iron-034c 拆箱**：原语表结果类型（PrimGen）；`infer-types` pass；codegen 带类型的局部变量；快照测试；`fib` / `fl-loop` 基准。
4. **iron-034d 共享类**：`StaticProcedure`；codegen 改无自由变量过程的生成；`boot-load` 基准；ILVerify。
5. **iron-034e 跨库直接调用**：`.ifc` 的写出与读取、`collect-known!` 扩展、nano 构建脚本写 boot 的 `.ifc`、失效检查的测试。
6. 每项更新 [03](../designs/03-compiler.md) 的 pass 表与 §5 / §6，必要时 [02 §4](../designs/02-runtime.md)。

## 验收标准
- 每个子任务：自举不动点不变（stage1 / stage2 / stage3 字节相同）；全部测试通过；ILVerify 通过；`tests/perf` 的六项基准没有一项劣化超过 5%，目标项有记录在案的改善。
- 034b：`slow-compile-seed.sps` 的类数减少约 150，命名 let 的快照里没有新类。
- 034c：`fib` 至少快 2 倍，`fl-loop` 至少快 2 倍；`(fixnum? x)` 分支外的变量仍按 `object` 处理（快照验证）。
- 034e：跨库调用 `Calls.Global` 的次数在用户库里显著下降（用 `wordcount` 的 Lcil 计数）；库重新编译后旧程序按现有机制报"需要重新编译"。

## 从 iron-033 转来
- 剩余的运行时互操作决议点（boot 中 31 处，多为 `clr-new` 的重载构造函数，如 `make-hashtable`、`string`、编解码器）可按 `values` 的做法加 `clr-cast` 提示——iron-056 之后这些都变成了原语调用，此项已无对象。

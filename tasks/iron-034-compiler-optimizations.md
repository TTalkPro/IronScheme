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

**2026-10-10 补充（重建后实测，Release 宿主，三次）**：

| 基准（`scratchpad/arith.sps`，100 万次或 `fib 30`） | 通用过程 | `$fx` / `$fl` 原语 | 倍数 |
|---|---|---|---|
| 计数循环 `(if (= i n) … (loop (+ i 1)))` | 112 ~ 120 ms | 4 ~ 8 ms | 15 ~ 30× |
| 同上，用 `(rnrs arithmetic fixnums)` 的 `fx=?` / `fx+`（带检查的 Scheme 包装） | 48 ~ 80 ms | — | 6 ~ 10× |
| `fib 30` | 140 ~ 160 ms | 12 ~ 16 ms | 10× |
| flonum 累加，`fl+`（带检查的 Scheme 包装）对 `$fl+` | 24 ~ 32 ms | 12 ~ 16 ms | 2× |

结论：通用算术与比较的**调用**（不是装箱）是最大的单项开销；`fx+` 这类带检查的包装也走同一条慢路径。装箱本身（`$fx` 版本仍装箱）只占几毫秒。

**`+` / `=` 到达 codegen 的实际路径**（重建后 dump 核实）：`(lambda (a b) (if (= a b) (+ a 1) (values a b)))` 的 L0 是
`(if (call (gref g$=$321$%b) a b) (call (gref g$+$333$%b) a '1) (call (gref g$values$301$%b) a b))`，
Lcil 是每处 `ldconst 符号 → Calls.Global → Calls.Proc → callvirt Invoke2`（约 10 条指令）。也就是说这些名字以**全局位置**（`rewrite` 用 `current-primitive-locations` 换上的 boot 位置符号）到达编译器，不是原语；`values` 的 special 同样从未触发。D8 的识别必须按这个事实设计（见 D8）。

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

**D8 通用算术与比较在调用处内联**（iron-059 转来，仿 Chez）。
- 现状：用户代码里的 `+ - * = < <= > >=` 是 boot 中用 Scheme 定义的过程（`boot/primitive-numbers.sls`、`boot/numbers.sls`），不在原语表里，codegen 走 `cg-primcall` 的"没有重载"分支 `cg-call-prim-value`：`ldconst` 符号 → `Calls.Global` → `Calls.Proc` → `callvirt Invoke2`。iron-059 已在这些过程内部加了 fixnum / flonum 快速路径，但调用本身省不掉。2026-10-10 实测（Release，100 万次计数循环 `(if (= i n) … (loop (+ i 1)))`）：
  - 用通用的 `=` 与 `+` 为 49ms；
  - 只用 `$fx=?`、`$fx+` 为 5ms；
  - 其中跨库调用每次约 8–15ns，`+` 内的 `define/contract` 检查约 10ns，其余是装箱与命名 let 的进入开销（D2）。
- Chez 的做法（`s/cpprim.ss:4546` 起，`define-inline 2 +`、`=`、`define-relop-inline`）：
  - 在调用处展开为"两个操作数都是 fixnum → 机器指令（加法带溢出检查），否则 `build-libcall` 调库函数"；
  - 库函数（`s/library.ss:749`，"The generic comparison entries assume the fixnum case is inlined"）只处理其余类型；
  - `primdata.ss` 为这些名字声明签名与 `pure` / `mifoldable` 等标志。
- 做法：
  - **识别（2026-10-10 核实后改写）**：这些名字到 codegen 是 `(call (gref g$+$333$%b) a b)`——`rewrite` 已把 `(primitive +)` 换成 boot 的位置符号，走的是 `cg-call` 的一般路径，不是 `cg-primcall`；往 PrimGen 的 `s_specials` 登记不会生效（`values` 的 special 就是这样从未触发的，不能当先例）。改为在 `cg-call` 里识别：操作符是 `(gref s)`，`s` 去掉 gensym 后缀的名字是八个之一，**且后缀是 `$%b`**（boot 镜像规范改名后的后缀，05 §7）。后缀是关键：用户库里 `(define (+ …))` 的位置是 `g$+$N$<进程戳>`，只按名字会把模运算库之类的 `+` 当成 fixnum 加法。代价：boot 自己构建时内部对 `+` 的引用后缀是进程戳，不内联——boot 的热循环本来用 `$fx`，可接受。lower-async 对 `dynamic-wind` / `with-exception-handler` 的按名识别（iron-051）漏了后缀检查，一并补上。
  - **范围**：第一批八个名字；第二批 `fx+ fx- fx* fx=? fx<? …` 与 `fl+ fl- fl* fl/ fl=? fl<? …`（`(rnrs arithmetic fixnums)` / `flonums` 的带检查包装，§0 实测同样慢 6 ~ 10 倍）：两个操作数是 fixnum 时直接用现有 `$fx…` 内联模板（`fx+` 要带溢出检查，用 `fx+internal` 原语或 `RT` 助手），否则调原过程报错。
  - **codegen**（两参数；其余参数个数仍走值槽调用）：
    - 两个操作数求值到临时变量，各做 `isinst Int32`；fixnum 常量操作数（`fixnum-constant`）不检查、直接 `ldc.i4`。
    - 比较：`unbox.any int32` 后用 `emit-compare!`，在测试上下文里直接 `brtrue`，不经布尔对象。
    - `+ - *`：调用 `RT` 中新增的静态助手（如 `RT.AddFixnums(int, int) → object`：`long` 运算，在 int 范围内时装箱，否则转大整数），由 JIT 内联。不在 IL 里手写溢出分支。
    - 任一操作数不是 fixnum 时，跳到慢路径：对 `pr` 做与现在相同的 `cg-call-prim-value`，位于尾位置时照样加 `tail.`。错误信息与 who 不变，因为都由原过程报出。
    - 第二步再考虑两个 flonum 的快速路径（`isinst Double`），量过 `fl-loop` 再定。
  - **与 D4 的关系**：D4 的类型来源原来只有 `$fx…` / `$fl…` 原语，而用户代码很少直接写它们。D8 之后，操作数已知为 int32 的局部变量可以连 `isinst` 一起省掉，结果保持不装箱。D4 的 `infer-types` 应把 `+ - *`（fixnum 结果）与比较（bool）作为类型来源；`+` 可能溢出成大整数，结果类型只能是"fixnum 或 bignum"，除非范围已知。
  - **代价**：每个调用点的 IL 变长（约 20–30 字节）。要量 boot 镜像的大小与 `boot-load`，必要时只在循环体内展开，或设展开次数上限。
  - **语义**：词法遮蔽的 `+` 是词法变量，不受影响。R6RS 不允许对导入的名字 `set!`；REPL 里重定义 `+` 的旧习惯不再影响已编译的调用点，与 D5 一样在文档中写明（Chez 相同）。
- 预期：计数循环由 49ms 降到 15ms 以下（只剩装箱与 D2 的开销）；D2、D4 完成后应接近 `$fx` 版本的 5ms。

**D7 顺序与取舍（2026-10-10 按实测调整）**：iron-034a 基准 → **034f D8**（§0 的实测说明通用算术的调用是最大的单项开销，10 ~ 30 倍；改动集中在 `cg-call` 一处）→ 034b D2 → 034c D4（类型来源要把 D8 的结果算进去：`+` 的结果是 fixnum-or-bignum，比较的结果是 bool）→ 034d D3（先量类型加载占比）→ 034e D5（最大、最后）。每一步单独可交付；任何一步基准不劣化、测试全过才合入。

## 工作内容
1. **iron-034a 基准**：`tests/perf/` 六个脚本与一个 `run-all.sps`（打印表格），任务书记录当前数字。
2. **iron-034b `lower-loops`**：把 D9 推广到普通 lambda；codegen 同步上下文的 `label` / `jump`；快照测试加命名 let、`do`、带捕获变量的循环三个用例；种子统计里 `$loop` 类应减到接近 0。
3. **iron-034c 拆箱**：原语表结果类型（PrimGen）；`infer-types` pass；codegen 带类型的局部变量；快照测试；`fib` / `fl-loop` 基准。
4. **iron-034d 共享类**：`StaticProcedure`；codegen 改无自由变量过程的生成；`boot-load` 基准；ILVerify。
5. **iron-034e 跨库直接调用**：`.ifc` 的写出与读取、`collect-known!` 扩展、nano 构建脚本写 boot 的 `.ifc`、失效检查的测试。
6. **iron-034f 通用算术与比较内联**（D8）：
   - PrimGen 的 `s_specials` 加八个名字；
   - codegen 的两参数 fixnum 快速路径与值槽慢路径，以及 `RT.AddFixnums` / `SubtractFixnums` / `MultiplyFixnums`；
   - 快照测试：常量操作数、测试上下文、尾位置的慢路径、三参数不展开；
   - 基准新增 `arith-loop`，即 iron-059 的计数循环：`=` 与 `+`、`<` 与 `-`，各 100 万次。
7. 每项更新 [03](../designs/03-compiler.md) 的 pass 表与 §5 / §6，必要时 [02 §4](../designs/02-runtime.md)。

## 验收标准
- 每个子任务：自举不动点不变（stage1 / stage2 / stage3 字节相同）；全部测试通过；ILVerify 通过；`tests/perf` 的六项基准没有一项劣化超过 5%，目标项有记录在案的改善。
- 034b：`slow-compile-seed.sps` 的类数减少约 150，命名 let 的快照里没有新类。
- 034c：`fib` 至少快 2 倍，`fl-loop` 至少快 2 倍；`(fixnum? x)` 分支外的变量仍按 `object` 处理（快照验证）。
- 034f：`arith-loop` 至少快 3 倍；`tests/base-library.sps` 的比较组（K 组）、`tests/bignums.sps` 与 R6RS 测试全过，fixnum 溢出到大整数、非数参数的报错（who 与消息）不变；boot 镜像增大不超过 5%，`boot-load` 不劣化超过 5%。
- 034e：跨库调用 `Calls.Global` 的次数在用户库里显著下降（用 `wordcount` 的 Lcil 计数）；库重新编译后旧程序按现有机制报"需要重新编译"。

## 从 iron-059 转来
- D8（上文）。另外，通用路径的现状供 D8 参考：iron-059 已在比较过程内部加了 fixnum、flonum、fixnum 与 flonum 混合的快速路径，其余实数一次 `$real-compare`。数据见 [iron-059](iron-059-system-numerics-bignum.md) 结论的"数的比较的快速路径"一节。

## 从 iron-033 转来
- 剩余的运行时互操作决议点（boot 中 31 处，多为 `clr-new` 的重载构造函数，如 `make-hashtable`、`string`、编解码器）可按 `values` 的做法加 `clr-cast` 提示——iron-056 之后这些都变成了原语调用，此项已无对象。

## 进度记录

基准：`src/scheme/tests/perf/run-all.sps`（Release 宿主，每项三次取中位数，毫秒）。

| 阶段 | boot-load | compile-seed | r6rs-run | fib | fl-loop | arith-loop | wordcount |
|---|---|---|---|---|---|---|---|
| 034a 基线（2026-10-10） | 756 | 597 | 6853 | 172 | 76 | 103 | 3581 |
| 034f 之后 | 745 | 615 | 6895 | 11 | 9 | 8 | 2886 |
| 034 全部完成（较安静的一次） | 677 | 681 | 6291 | 11 | 6 | 12 | 2894 |
| 同上，机器有其它负载的两次 | 755 / 815 | 790 / 672 | 7557 / 7211 | 11 / 11 | 7 / 5 | 12 / 10 | 3655 / 3317 |

墙钟数字受本机其它进程影响很大（同一镜像连续两次 `boot-load` 相差 20%）。结论以同一镜像交替运行的 CPU 时间为准（`IRONSCHEME_NO_034=1` 只关掉新编译代码的 034 生成，boot 本身不变）：

| CPU 时间（5 次中位数，秒） | 034 全开 | `IRONSCHEME_NO_034=1` |
|---|---|---|
| `tests/r6rs/run.sps` | 8.42 | 9.45 |
| `tests/perf/empty.sps`（启动） | 0.77 | 0.75 |

`compile-seed`（编译器本身的吞吐，进程内 CPU 时间，5 次）：全开 604 ~ 827 ms、中位 684，分配 810 MB；`NO_034=1` 621 ~ 786 ms、中位 644，分配 727 MB。多出的分配来自三个新的遍历（`lower-loops`、拆箱推断、大过程体计数），每个约 +4 ~ 7%；拆箱推断已改为只对含循环的形式做（`loop-forms`），时间差在噪声之内。修掉 nanopass 每次调用重建记录类型的开销之后（见测量说明）：全开 553 ~ 620 ms、中位 606，分配 685 MB；`NO_034=1` 中位 612，分配 615 MB。与 034a 基线的 597 ms 相比 +1.5%，在验收标准的 5% 之内。

**最终验收对照（2026-10-10，含 034d 共享类）**：本机一直有别的构建在跑，墙钟读数不可靠，所以把 034 之前的提交（HEAD `26386793`，`git archive` 导出到临时目录单独构建）与当前工作区交替运行，比较进程 CPU 时间（中位数）：

| 项 | 034 之前 | 034 完成 | 变化 |
|---|---|---|---|
| boot-load（10 次） | 0.68 s | 0.62 s | −9% |
| compile-seed（进程内中位数） | 626 ms | 507 ms | −19% |
| r6rs-run | 8.17 s | 5.73 s | −30% |
| wordcount | 3.77 s | 3.49 s | −7% |

fib、fl-loop、arith-loop 见上表（172 → 11、76 → 6、103 → 10 ms 量级）。没有一项劣化。最终 boot（stage0 构建）ILVerify 通过，全部测试通过（含自举不动点、系统库与 .fasl 的 ILVerify）。

**逐项验收（最终代码，2026-10-10）**

| 子任务 | 验收标准 | 最终代码上的结果 |
|---|---|---|
| 全部 | 自举不动点、全部测试、ILVerify | Core 260 / 全量 89 通过（含 Bootstrap 的 stage1 = stage2 = stage3、SystemLibraries 126 个库 dll 的 ILVerify、`.fasl` 的 ILVerify）；boot ILVerify 通过；跨 `.fasl` 直接调用的程序 ILVerify 通过（`ProgramCallsCompiledLibraryDirectly`） |
| 全部 | 基准不劣化超过 5% | 见上面与 034 之前的交替对照：全部改善 |
| 034b | 种子的类数减少约 150；命名 let 快照没有新类 | 同一编译器下关掉循环降级（`NO_034=loops`）对照：种子类数 926 → 762（−164）；`named-let-loop.lcil` 只有模块类 |
| 034c | fib、fl-loop 至少快 2 倍；`(fixnum? x)` 分支外仍是 object | fib 145 ~ 153 → 16 ms（约 9.5 倍），fl-loop 73 ~ 74 → 5 ~ 6 ms（约 13 倍）；快照 `typed-loop` |
| 034f | arith-loop 至少快 3 倍；K 组、bignums、R6RS 全过；boot 增大不超过 5%；boot-load 不劣化 | arith-loop 92 ~ 97 → 11 ~ 12 ms（约 8 倍）；测试全过；boot 2,385,920 → 1,956,352 字节（−18%）；boot-load −9% |
| 034d | StaticProcedure、codegen、boot-load 基准、ILVerify | 见 034d 一节：类型 4327 → 1829，boot-load −12%（对每过程一个类），共享模式的不动点与 ILVerify 通过 |
| 034e | 用户代码的 `Calls.Global` 显著下降；库重新编译后旧程序报需要重新编译 | wordcount 的 Lcil：41 → 4（37 处直接调用 boot）；`ProgramCallsCompiledLibraryDirectly` 验证用户库直接调用与重新编译后的报错 |

（fib / fl-loop / arith-loop 为进程内五次中位数，034 之前的构建与当前构建各跑两次。ILVerify 按文件名找被引用的程序集，校验直接调用另一个 `.fasl` 的产物时，把被调的 `.fasl` 复制成以其程序集名命名的 dll 作为引用。）

### 034a 基准（完成）
- `tests/perf/run-all.sps`：七项（任务书 D1 的六项加 034f 的 `arith-loop`）；`boot-load`、`r6rs-run`、`wordcount` 另起宿主进程计时，`wordcount` 的输入（约 1.2 MB）首次运行时生成到 `tests/perf/wordcount-input.txt`（已加入 `.gitignore`）。

### 034f 通用算术与比较内联（完成）
- `codegen.sls`：`cg-call` 识别 boot 位置（后缀 `$%b`）上的 `+ - * = < <= > >=`、`fx+ fx- fx* fx=? fx<? fx<=? fx>? fx>=?`、`fl+ fl- fl* fl/ fl=? fl<? fl<=? fl>? fl>=?` 的两参数调用，生成"`isinst` 检查 → 直接算（比较在测试上下文里直接给 CLR bool）→ 否则经值槽调原过程"；fixnum / 有限 flonum 常量操作数不检查、直接 `ldc`。`+ - *` 经 `InlineArith.Add` 等（`long` 运算，溢出转大整数），`fx+ fx- fx*` 经 `InlineArith.FxAdd` 等（溢出返回 null，转慢路径由原过程报 `&implementation-restriction`）。`targets.sls` 加 `inline-arith` 类型名。
- `async.sls` 的 `gref-named?`（`dynamic-wind` / `with-exception-handler` 的识别）补上 `$%b` 后缀检查。
- 语义核对（溢出转大整数、`fx+` 溢出报错、非数报错的 who 与消息、`fl+` 收 fixnum 报错、词法遮蔽的 `+`）全部与原过程一致；快照 `inline-arith`（常量操作数、测试上下文、尾位置慢路径带 `tail.`、三参数不展开、用户定义的 `+` 不展开、`fx+` 的溢出分支、`fl*` 的常量）。
- boot 镜像不变（boot 内部对这些名字的引用是库变量，构建期间编译器库对 boot 导出的引用带进程戳，都不内联）。


### 034b 局部循环降级（完成）
- `lower-loops`（`compiler/async.sls`，导出；`compiler.sls` 的 front-end 在 `lower-async` 之后调用）：普通 lambda 体里只被参数个数相符的尾调用引用的单绑定 `letrec` lambda（命名 let、`do`）变 `(label f (x …) 体 循环体)` + `(jump f e …)`；命名 let 的展开形状先规范化。只做 D9，不做 async 的 D10 / D11。
- codegen：同步方法里的 `label` / `jump`（`mctx` 加 `labels` 表；`jump` 先把实参求值到临时变量再写回形参；循环体从未被跳到时不生成）。
- 推广到 `let`（034 收尾时加入）：`let` 绑定（包括立即调用的 lambda，即展开器的 let）的单子句 lambda，若体里只在尾位置按相符的参数个数调用它，也变成 label，嵌套在体外，其余绑定照旧。nanopass 生成的每个处理器都有这种形状——每个子句一个 `rhs` 闭包加一个 `else-th`，原来每次调用处理器都要分配；变成 label 后不再分配。编译器本身在 boot 里，所以编译种子的分配 720 → 468 MB（−35%）。快照 `let-lambda-labels`（不生成闭包类）；`typed-loop`、`typed-lambda-args` 的 `.l0` 里立即调用的 lambda 现在提早写成 `let`，后续各阶段不变。
- 种子统计：类 2354 → 2240（−114，任务书预计约 −150：其余命名 let 的循环名被捕获或有非尾调用，不满足条件）。快照 `named-let-loop` 更新，没有新类。自举不动点不变。

### 034c 拆箱（完成）
- 没有单独的 L2 pass：类型推断放在 codegen 里，每个形式先跑一遍库级 `define-pass infer-walk`（处理器 MaybeTyped / Raw / Body / Expr），得到 `var-types`（变量 → `fx` | `fl`），依赖用工作表求不动点；变量只在拆箱后的原始读不少于装箱读时才拆（否则装箱次数反而变多）。来源：fixnum / flonum 常量、`$fx` / `$fl` 原语与内联算术（034f）的结果、只被这类值赋值的 `let` 变量与 `label` 形参。
- codegen：`expr-type`、`cg-raw`（求原始值）、`box-raw!`；带类型的变量位置 `(tlocal i . 类型)` 用 `int32` / `double` 的 IL 局部变量；`let` / `label` / `jump` 按类型存取；原语的拆箱参数与内联算术的操作数直接用原始值。async 方法与大过程体不拆箱。编译驱动按 `lower-loops` 是否生成了 `label` 给出 `loop-forms`，只对含循环的形式做推断（收益几乎都在循环变量上，省下一部分编译分配）。
- 快照 `typed-loop`：fixnum 计数循环与 flonum 累加用原始局部变量，`(fixnum? x)` 分支外的变量仍是 `object`。
- 测量：见下面的表（`IRONSCHEME_NO_034=infer` 对照）。

### 034d 共享类（完成）
- 第一版（每单元一个 `…$Procs : SharedProcedure`，`Invoke` 按 id `switch`）实测 `boot-load` 不变、`compile-seed` 慢 16%，撤回。用事件追踪拆开，boot 入口 cctor 的约 148 ms 是常量表反序列化，不是类型加载。
- 按 D3 原设计重做（委托）：
  - 运行时 `StaticProcedure`（`IronScheme.Core`）：名字、`procedure-arity`、`procedure-form` 与六个入口委托（`Func` 0 ~ 4 个参数各一个，加上收实参数组的通用入口）。
  - codegen：无自由变量的同步过程不再各生成一个类。子句方法 `P<id>$C<i>`（与通用入口 `P<id>$N`）放进每单元的持有类 `#Module$P<k>`（每 200 个过程一个），过程对象存在持有类的静态字段 `P<id>`，由持有类的静态构造函数依次创建（`ldftn` + `newobj Func`）。已知过程的直接调用变成 `call #Module$P<k>::P<id>$C<i>`（known 记录的 owner / prefix），值是 `ldsfld #Module$P<k>::P<id>`；接口文件的条目多一项前缀。async 过程、有自由变量的闭包不变。
  - 尾调用：C# 不能写 `tail.`，JIT 只在优化编译时才可能把委托调用做成尾调用——实测 Debug 构建下经过程对象的深度尾递归栈溢出。所以每个单元再生成一个 `#Module$SP : StaticProcedure`，`Invoke0..4` / `InvokeN` 在 Lcil 中以 `tail. callvirt` 调委托（参数打包后交给通用入口的路径也是），过程对象是它的实例。Debug 与 Release 下三百万层的互相尾递归、`apply` 尾递归都通过。
- 结果：boot 的类型 4327 → 1829，镜像 2.28 → 1.95 MB；共享模式的自举不动点成立，ILVerify 通过。与每过程一个类交替对照（CPU 中位数）：

| 项 | 每过程一个类 | 共享类 |
|---|---|---|
| boot-load | 0.74 s | 0.65 s（−12%） |
| compile-seed（进程内） | 521 ms | 524 ms（持平） |
| wordcount | 3.63 s | 3.43 s（−5%） |
| r6rs-run | 6.74 s | 5.72 s（−15%） |

  默认开启；`IRONSCHEME_NO_034` 含 `shared` 时恢复每过程一个类。快照里出现 `#Module$SP` 与 `#Module$P0`（10 个 `.lcil` 快照更新）。

### 034e 跨库直接调用（完成）
- **单元内**：`unit-known-loc`（位置符号 → 已知过程记录，只登记库形式的导出、不被 `mset!` 的过程）。`(gref s)` 若是本单元的已知过程，值为 `ldsfld 类::Instance`，参数个数相符的调用直接 `call 类::C<i>`。boot 镜像内库之间的调用全部变成直接调用：种子编译的 `Calls.Global` 4654 → 189，直接调用 5447 → 8096，指令数 −8%，`boot-load` 约 760 → 700 ms。
- **跨单元（boot 导出）**：nano 构建脚本在镜像旁写 `ironscheme.boot.ifc`（`(ironscheme-interface 1 "镜像 MVID" ("位置符号名" "类名" 子句形状) …)`，按规范 gensym 名，1350 个过程），随宿主输出目录复制。codegen 编译别的单元时读一次（原语 `$boot-interface-file`、`$boot-image-id`，经 `symbol-value` 取，旧镜像里从源码加载编译器时也能用），文件的 id 与正在运行的镜像不同就不用；命中的 `(gref s)` 按已知过程处理，类名写成 `类名, ironscheme.boot`（发射器 `T()` 支持方括号外的程序集限定名，按简单名在已加载的程序集中找）。
- **失效**：D5 原以为库的编译实例 id 能保护直接调用，但 boot 库的 id 是规范 gensym（只取决于输入顺序），镜像改了 id 未必变。所以改用镜像的 MVID（内容哈希）：用了接口的单元在入口第一条调用 `BootInterface.Check("MVID")`，镜像不同就报 "compiled code requires a different boot image; recompile it"。库的 `.fasl` / dll 由加载方（`host-guard`）打印警告并退回源码；程序报错。`ModuleLoader.Run` 登记第一个 `ironscheme.boot` 程序集，并注册 `AssemblyResolve`（按字节加载的 `.fasl` 与嵌入的 boot 各在独立的加载上下文中）。自包含发布的 boot 嵌在可执行文件里，没有接口文件，编译时不用接口（发布的应用由正常宿主编译，镜像相同，`Check` 通过）。
- **用户库（`.fasl` / 库 dll）**：所有产物都经编译器的 `compile-library-dll` 写出，它现在
  - 用唯一的程序集名（文件名 + `$` + 进程内唯一的 gensym 后缀，只留安全字符）：别的单元按名字引用其中的类时不会与另一目录的同名文件混淆；
  - 在旁边写 `名字.ifc`（格式同 boot 的接口文件，第三项是程序集名）。
  - codegen 的 `collect-known!` 也登记嵌套在产物里的库形式（`(list … (lambda () (library …)) …)`，`nested-libraries` 只沿调用实参与"体就是 library 的无参 lambda"找）中的已知过程，类名固定；求值顺序不变（不预链接，类的单例由静态构造函数建立）。
  - 运行时 `ModuleLoader.LoadModule` 加载 `.fasl` / 库 dll 后，旁边接口文件记录的程序集名与加载的相同就登记（原语 `$library-interface-files`）；codegen 读新登记的文件，`(gref 位置)` 命中时按已知过程直接调用 `类名, 程序集名`。`ModuleLoader.Run` 按名字登记每个运行过的产物（同名再次加载以最新为准，boot 只认第一个），`AssemblyResolve` 从登记表解析；发射器的类型缓存不缓存库产物的限定名。
  - 只用真正加载过的产物的接口：装入的库实例就是那个产物，模块字段已由其入口初始化。同一进程里 `compile-library` 之后装入的是源码展开的实例、产物程序集没有加载，不用（否则同一进程里接着 `load` 编译好的程序会引用未加载的程序集——实测过，已排除）。
  - 失效：位置符号是每次展开的 gensym，库从源码重新展开后旧条目不会命中；编译好的程序 / 库对被调库编译实例的依赖由现有的 id 检查保护——库重新编译后旧程序报 "requires a different compilation of a library"（测试 `ProgramCallsCompiledLibraryDirectly`）。
- `wordcount` 的 Lcil（`IRONSCHEME_DUMP_PASSES` 现在也写出 eval 单元的 `.lcil`）：`Calls.Global` 41 → 4，37 处变为直接调用 boot 的类。
- 测试：`CompileFile` 加三项——编译产物引用 `ironscheme.boot` 且能运行、接口文件 id 不符时不用（产物不引用 boot）、`Check` 的报错。ILVerify（`tools/build.cs ilverify` 与测试里的 `Bootstrap.ILVerify`）校验非 boot 产物时引用 boot 镜像。
- 语义（文档写明，同 Chez）：`set-symbol-value!` 改写 boot 导出名的值槽不影响已编译的直接调用点。

### D6 小项
- `call-with-values` 内联（完成，放在 `lower-loops` 里）：`(call-with-values (lambda () p) (lambda (x … . r) b))` → 求一次 `p`，`$values-count` 检查个数（`=` 或 `>=`），`$values-ref` / `$values-tail` 绑定；个数不符时退回原 `call-with-values`（换一个同名、体为空的消费者 lambda，报错与原来完全相同）。原语在 `InlineArith.cs` 的 `ValuesPrimitives`，`primitives.ss` 重新生成。R6RS 测试运行时 JIT 的方法少约 1200 个。快照 `inline-values`。
- 记录访问器（完成）：展开器的 `define-record-type` 把谓词、访问器、修改器展开为 `(lambda (r) ($record-instance? rtd r))`、`(lambda (r) ($record-field-ref rtd k r))`、`(lambda (r v) ($record-field-set! rtd k r v))`（原语在 `Records.cs`，检查与报错——who 为"类型名-字段名"、消息 "not a record of type …"——与原来 `record-accessor` 等返回的过程相同）。库中它们是已知过程：调用点从 `Calls.Proc` + `callvirt Invoke1` 变为直接 `call 类::C0`，跨库时经 boot / 用户库的接口文件同样直接调用；boot 接口的过程数 1358 → 1683。快照 `record-accessor`。
- `typed-lambda`（完成）：类型说明原来在 parse 时丢掉。现在形参类型为 `Int32` / `Double`（或 `fixnum` / `flonum`）时，parse 把形参改名为 `x$typed`、体外包 `(let ((x ($as-fixnum x$typed))) 体)`；`$as-fixnum` / `$as-flonum` 是恒等原语，codegen 把它们算作 fixnum / flonum 的来源（034c），`x` 用 `int32` / `double` 局部变量。boot 的 `define-fx` / `define-fl` 都是先检查参数再调用 typed-lambda，与旧系统强类型形参的约定相同。含 typed-lambda 的形式也做类型推断（`loop-forms` 计入 `typed-clauses-made`）。快照 `typed-lambda-args`。
- fresh 名的确定性：`reset-fresh-names!` 改为每个编译单元开始时调用一次（`compile-forms->lcil*` 与快照脚本），`lower-async` 里不再重置。

### 测量说明
- `r6rs-run` 以编译和 JIT 为主：同一镜像下 `IRONSCHEME_NO_034=1` 对照，CPU 时间差从 7 ~ 10%（034 的额外 pass 与更大的 IL）降到 call-with-values 内联之后的约 2%（CPU 7345 vs 7188 ms，分配 1681 vs 1522 MB）。机器上有其它进程，墙钟噪声大，比较时用 `DOTNET_gcConcurrent=0` 与 CPU 时间的中位数。
- nanopass 的开销（已修）：每个 `define-pass`（`nanopass-case` 也展开成一个）的过程体里有 `(define-nanopass-record)`，原版对 IronScheme 展开为 `define-record-type`，每次调用 pass 都重新求 rtd / rcd / 谓词 / 访问器（同一个 nongenerative uid，每次约 350 字节、0.2 µs）。覆盖库 `lib/nanopass/implementation-helpers.ironscheme.sls`（子模块同名文件的副本，库路径中 `lib` 在子模块之前；只改这一处）把记录类型在库里定义一次，`define-nanopass-record` 只把名字绑定过去。种子编译分配 810 → 685 MB；boot 构建输入加上 `lib/nanopass/**`。
- 测量开关：环境变量 `IRONSCHEME_NO_034=1` 关掉全部，包含 `known` / `inline` / `infer` 子串时分别关掉直接调用（含 boot 接口）、内联算术、拆箱，等于 `loops` 时关掉循环降级；包含 `letlab` 时不做 let 绑定 lambda 的降级，包含 `typed` 时不用 typed-lambda 的类型说明，包含 `shared` 时恢复每过程一个类（这两个在编译器内部生效，构建 boot 时设置可得到对照用的镜像）。

# CIL 上的真尾调用：机制调研与本项目的取舍

（2026-10-09。本笔记整理"真尾递归、CPS 与 dynamic-wind"的一次设计调研。所有来源均内联标注；规范与实现的引文保留原文，其余为中文论述。）

## 本笔记回答的问题

1. CIL 上如何实现真尾递归？
2. Clojure 在 JVM 上怎么做的？（简答：没做）
3. Common Lisp 的 tail merging 是什么意思？
4. JVM 与 CIL 能否使用 tail merging 这种方式？
5. 通用 CPS 变换能否实现无栈式尾递归？
6. CPS 变换后，尾递归能否在 try/catch 中使用？
7. Chez Scheme 用什么方式实现尾递归？
8. JVM 上没有 `tail` 指令，能否按 Chez 的 `jmp` 模式实现尾递归？

## 结论速览

- **CIL 有真正的、以正确性为目的的尾调用机制**：`tail.` 前缀。CoreCLR 通过两条路径兑现它——fast tailcall（拆帧 + `jmp`）或便携式 helper 调度（运行时生成 IL stub + `DispatchTailCalls` 循环）。本编译器已经在用它（`codegen.sls` 的 `tail-ok?`、`Emitter.cs` 的 `InstrKind.Tail → OpCodes.Tailcall`、未知目标/`apply` 的 `tail. callvirt InvokeN`）。
- **try 区域的限制不是 CLR 的缺陷，而是 ECMA-335 的正确性规则**：尾调用丢弃帧，帧上的 `finally` 就无法再执行，因此规范直接禁止。任何 CLI 都绕不过去。真正"花钱"的是**挂起的 finally/handler 义务**，代价是**每个活跃义务一帧**——这与 R6RS/R7RS 参考实现属于同一类。
- **通用 CPS 变换本身不产生无栈尾递归**：它把动态区域义务的 O(N) 从栈**搬到堆**。现有的直接式实现恰好落在 Danvy 证明的零开销分裂上（二阶续延 = 栈帧），所以为 TCO 而做 CPS 是净退步——除非目标是一阶续延。
- **Chez Scheme 没有"尾调用优化"这个 pass**：它的调用约定让一切调用都是 `jmp`，非尾调用才额外存返回地址。TCO 是默认形态。Chez 真正比我们强的是**可重入续延**（分段栈 + 有界复制 + winders），而不是尾调用。
- **JVM 复刻 Chez 裸 `jmp` 在字节码层面不可能**（无跨方法跳转指令、帧布局由规范固定）——但 JVM 曾实验过同款机制（mlvm 的 `tailcall` 前缀 + JEP 草案，校验规则与 CIL `tail.` 逐条相同），因保护域安全模型与拆帧冲突而未合并（JDK-6804517 至今 Unresolved）；可行的变体是单方法标签分派 / 方法级 trampoline / 堆帧 + Truffle。
- **建议**：保持方案 A（`tail.` 前缀），补测试矩阵与精确的符合性措辞；**不要**为 TCO 做 CPS；若 wind 开销真成问题，把基于 CIL try 的 `dynamic-wind` 换成堆上的 winders 表（Chez/Ikarus 模型），而不是上 CPS；完整 call/cc（帧机）是独立里程碑，触发条件是把 `windtests.sps` 重新纳入测试。

## 1. CIL 到底保证什么（已核对原文）

ECMA-335 Partition III §2.4（`tail.` 前缀），原文：

> "The tail. call instruction cannot be used to transfer control out of a try, filter, catch, or finally block."

其他要点：

- 合法序列只有 `tail.` + `call`/`calli`/`callvirt`，且必须紧跟 `ret`；求值栈上除参数外必须为空。
- **强制兑现的只有一种情形**：同程序集、非 `synchronized`、可验证的 `tail. call`（静态直接调用）。规范明确写了 CLI 实现 "need not honor tail. calli or tail. callvirt sequences"。
- 被调方返回类型必须能赋给调用方返回类型（本项目恒为 `object`，构造上天然满足）。

对项目的含义：`codegen.sls` 的 `known-target` 静态尾调用（同程序集）恰好落在 **ECMA 强制**的子集里；而兜底路径 `tail. callvirt Proc.InvokeK/InvokeN` 依赖的是 **CoreCLR 的实现质量**，不是标准保证——若 `designs/11`（"CLR 作为目标机器"）将来要跨到别的 CLI，这是一处可移植性风险点，需要记录。

CoreCLR 的行为（`dotnet/runtime` 的 `docs/design/features/tailcalls-with-helpers.md`）：

- 显式 `tail.` **无条件被兑现**：JIT 能做就走 fast tailcall，否则走 portable helper（运行时生成两个 IL stub + 一个带 TLS 簿记的 `DispatchTailCalls` 循环）。两条路都不涨栈；helper 路径更慢（issue #2191 有人测出病态的 ~60x；iron-003 实测栈传参情形 ~8x——本项目的 ≤4 参数约定在 x64 上永远不会触发）。
- 含显式尾调用的方法会被 JIT **强制优化、不走 Tier-0**，这正是 iron-003 在 `DOTNET_JITMinOpts=1` 下依然通过的原因。
- iron-003 探针（.NET 10、Linux x64、千万层深度）验证：虚调用互递归、变 arity、静态调用、栈传参全部真尾调用；不加前缀的对照在关优化时约一万层溢出。

`jmp`（ECMA-335 III.3.35）：要求签名**完全相同**，同样不能离开保护区域，相比同程序集 `tail. call` 没有任何额外收益。不值得用。

没有任何运行时开关能改变 EH 规则（也不需要——显式 `tail.` 是无条件兑现的）。ReadyToRun 与本项目无关——代码全部经 Reflection.Emit 在运行期 JIT。

## 2. JVM 与 Clojure（已核实）

**Clojure 根本没有实现通用 TCO**，而且 JVM 是**刻意**不给：字节码里没有跨方法跳转指令，所有调用指令都必然压入返回地址，帧布局由规范固定，HotSpot 的 GC 根扫描、异常处理、deopt、JVMTI 全部依赖完整可遍历的帧链。Brian Goetz 在 ClojureConj 2014 明确把栈帧折叠称为攻击面。

Rich Hickey（Clojure 官方 Google Group 的 TCO 讨论串，原文）：

> "Clojure has recur, which clearly labels the only situations that won't grow the stack, apologizes for no real TCO, doesn't pretend to support function calls for control flow..."

`recur` = 同一方法内的 JVM 跳转（重赋局部变量 + `goto` 循环头），**只限自递归**；跨 `try` 使用是编译错误。互递归只能靠 trampoline。

**clojure-tco**（cjfrisz，2012，MIT；Chris Frisz 与 Daniel P. Friedman）：源到源编译器。流水线（`src/ctco/core.clj`）：

```
parse → unrecurify → 一遍一阶 CPS（Danvy & Nielsen 2007，
  "A First-Order, One-Pass CPS Transformation"）→ recurify（自尾调用
  还原成真 recur）→ thunkify（非尾续延包成 ^{ :thunk true} 的零参闭包）
  → load-tramp → unparse，外层包成：

(letfn [(tramp [thunk]
          (if (:thunk (meta thunk))
              (recur (thunk))
              thunk))]
  (tramp <body>))
```

它成立的原因：CPS 让所有调用落在尾位置；`recurify` 让自调用零分配（真 JVM 跳转）；**驱动循环本身也是真 Clojure `recur`**，即同样是 JVM 跳转。两层循环相乘才是常数空间。代价：常数**栈**但不是常数**堆**——非尾递归每次调用都要分配续延闭包（它的宏文档字符串里自己写明）。它接受的文法极小，**不含 `try`/`catch`**——所以对 `dynamic-wind` 一点忙都帮不上。

## 2.5 JVM 上能否按 Chez 的 jmp 模式实现？（Da Vinci/mlvm 史实与三条变体路线）

直接结论：**字节码层面做不到——但不是没人试过；JVM 曾有过完整的实验实现（mlvm `tailc.patch` + JEP 草案），最终未合并。** 而 Chez 模式的"精神"（控制流是跳转、不依赖宿主栈）在 JVM 上有三条可行的变体路线。

### 史实：JVM 做了又放弃了

2007–2009 年 Da Vinci Machine（OpenJDK mlvm）项目实现了硬尾调用（John Rose 主导，Arnold Schwaighofer 写的原型）：

- 新增 `tailcall` 字节码前缀（数值 196，复用 `wide` 操作码），可加在任何 `invoke` 指令前；解释器、client compiler、server compiler 三端都实现（x86-32 原型）；
- 校验器规则（John Rose 博客与 JEP 草案原文）：

  1. The callee method's return signature is identical with the caller method's return signature.
  2. The invoke instruction is immediately followed by a return instruction.
  3. **No exception handlers apply to the invoke instruction.**
  4. The caller method is not synchronized.
  5. The caller method is holding no object locks.
  6. The callee method is accessible and linkable from the caller method.

注意第 2、3 条与 CIL 的 `tail.` 规则**逐条相同**——同一个设计在两个 VM 上的独立收敛。

**未合并的原因**（mlvm-dev 2009-01 原型进度邮件，原文）：

> "Some stack frames can not be removed because of java's access security mechanism. Every stack frame points to a **protection domain** via which permissions are computed. On access to a guarded resource permissions are computed by **intersecting all protection domains that are on the stack**. If caller and callee protection domain are different we can not remove the caller's stack frame… In such a case the tail call proceeds like a normal function call."

Java 的访问控制是**沿栈帧链做保护域权限交集**的（SecurityManager 时代的设计）。保护域不同就不能拆帧，尾调用退化为普通调用，还要定期压缩同保护域的帧——"硬尾调用"在跨安全边界时**不再被保证**，而对 Scheme 这恰是正确性需求；一个时灵时不灵的保证等于没有。John Rose 起草了 JEP（`vm-tailcall-jep.html`），JSR 292 专家组讨论后认为"可以安全且高性能地实现"，但最终只有 `invokedynamic` 进了主线。对应工单 **JDK-6804517**（"Some languages need to be able to perform tail calls"）至今仍是 **Unresolved**（P3，挂了十七年）。

对照：CLR 2002 年 v1 就有 `tail.`——F# 是第一方语言、CLR 从第一天就按多语言运行时设计；JVM 按 Java 设计，等动态语言成为议题时（JSR 292），资源给了 `invokedynamic`。

### Chez 模式的三要素与 JVM 的障碍

1. **跨过程跳转不压帧** → JVM 字节码**没有**跨方法跳转指令；
2. **自定义调用约定与帧布局** → JVM 帧布局由规范固定，GC 根扫描 / EH / deopt / JVMTI 全部依赖规范帧链；
3. **TCO 是默认形态而非优化** → 前两条不成立则无从谈起。

### 变体路线 A：单方法标签分派（最接近 jmp 模式）

把整个编译单元（库）编译进**一个** JVM 方法：每个 Scheme 过程是一个标签，"调用" = 重赋局部变量 + `goto` 标签；"返回"用 `tableswitch` 一个整数 tag 模拟 computed goto（JVM 没有计算跳转，老的 `jsr`/`ret` 子程序指令自 Java 6 起被禁）。

- 机器码形态与 Chez 完全一致：一切都是方法内跳转、零分配、自递归与互递归同价；
- 额外红利：常量 JVM 栈对**所有**调用（不只尾调用）成立；把 locals 快照进堆数组还能顺手得到完整 `call/cc`；
- 硬限制：方法字节码 **64KB 上限**（大库必须切块、块间调用退回 trampoline）；每个标签都要生成 **StackMapTable**（新校验器强制，大方法生成又慢又占内存）；每次调用/返回多一次 `tableswitch`（HotSpot 可编成跳转表，但比一条 `jmp` 多一次间接分支）；调试与栈跟踪失真（整个库是一个方法）；Java 互操作帧仍是真帧。

### 变体路线 B：方法级 trampoline（CTCO 模型）

每个 Scheme 过程 = 一个 JVM 方法，返回"值或 bounce（thunk）"，driver 循环驱动：

```java
Object run(Frame f) {
  while (f instanceof Bounce) f = ((Bounce) f).thunk.invoke();
  return f.value;
}
```

常量栈、无 64KB 问题、跨整个程序生效；代价是每次调用 = 一次真 JVM 调用 + 一次返回 + 一次间接再调用，**全部调用 2–4×**（Chez 的 `jmp` 是零开销），且 HotSpot 的内联无法消除"先返回再重入"这个形状。

### 变体路线 C：堆帧 / 解释器 + 部分求值

帧是堆对象（SISC、Haskell 的 STG 机在 JVM 上的实现 Eta 都是这个模型），TCO 与完整 `call/cc` 天生免费，代价是所有调用的常数因子。**现代工程正解是 GraalVM Truffle**：自己写解释器循环（JVM 栈不涨，TCO 在解释器语义层实现），交给 partial evaluation 把热路径编译成机器码——但架构从"AOT 编译器"变成"解释器 + PE"，是完全不同的项目形态。

### 对项目

- 若 `designs/11`（可移植性）将来要 JVM 后端：**不要复刻裸 jmp**（不可能）。路线排序：GraalVM Truffle > 方法级 trampoline（对现有 codegen 改动最小，把尾调用改成 bounce 协议）> 单方法分派（性能最好但 64KB 与 StackMap 的工程量最大）。Java 互操作的帧边界问题与你们在 CLR 上面对的互操作问题**同构**，Chez 用 `longjmp` 解耦两个栈的思路在那边同样适用。
- JVM 上同样有"大栈线程"这条退路（`new Thread(null, task, "scheme", 256*1024*1024)`），与 `Program.cs:27` 的做法等价。

## 3. Common Lisp（已核实）

ANSI CL 里**没有 `dynamic-wind`**。对应物是 `unwind-protect`——只有 "after" 那一半：

```lisp
(unwind-protect protected-form cleanup-form ...)
```

CLHS 的要点：cleanup 在**任何**退出方式下都执行（正常返回、`throw`、`return-from`、`go`、条件系统、restart）；多个 cleanup 按序求值；cleanup 不受自己的 unwind-protect 保护；返回值是 protected form 的值。**没有 `before` thunk**——CL 没有可重入续延，"跳回时该做什么"根本不可表达。CL 的 special（动态作用域）变量补上另一半：退出时（含非局部退出）恢复旧值；CLHS 5.2 把 unwind 次序规定得很细（cleanup 与动态绑定撤销按建立次序的**逆序交错**执行；cleanup 看到的是**进入 unwind-protect 时**的动态绑定）。

**tail merging** 是 LispWorks 给 TCO 起的名字（原文："When the Compiler compiles either a tail call or a self-tail call, it reuses the calling function's stack frame rather than creating a new stack frame. This optimization is called tail merging."）。SBCL 手册："The compiler is 'properly tail recursive.'... stack frame will be deallocated at the time of the call"。关键是 LispWorks 把例外条件写得很直白：

> "There is something with dynamic scope on the stack, such as a special binding, a catch or dynamic-extent allocation (**so it is not really a tail call**)" → 不合并

即"栈上有待清理的动态状态就不合并"这条 CL 规则，与 CIL 的 EH 禁令、R6RS 的尾上下文定义是**同一件事**的三种表述。另注意：SBCL **默认优化策略下并不做 tail merging**（Nikodemus Siivola："`Tail-merging is done if (> SPACE DEBUG) or (> SPEED DEBUG)` — not by default"）——正确性保证与"看得见的优化"是两回事，这与 CIL 的 `tail.`（保证正确）vs fast path（JIT 决定）完全平行。

ANSI CL 是否**强制**真尾递归，社区有分歧（一种常见说法是"不强制，与 Scheme 相反"）；SBCL/LispWorks/GCL/CLISP/CCL 全部实现。调研期间 CLHS 3.5 原文页未能取到，引用前请先核对。

## 4. dynamic-wind 的规范语义（已核对原文）

R7RS-small（standards.scheme.org/corrected-r7rs）：

§4.2.6：

> "In Scheme, call-with-current-continuation (section 6.10) allows reentering a dynamic extent after its procedure call has returned. Thus, the dynamic extent of a call might not be a single, continuous time period."

§6.10 `dynamic-wind`：进入/退出动态区域共**四条规则**（正常进入；调用"在区域内捕获的续延"也算进入；正常返回退出；调用"在区域外捕获的续延"也算退出），外加嵌套次序规则（内层 `after` 先执行、外层 `before` 先执行；穿越时 `after` 先于对方的 `before`）。最后一句是规范上唯一的洞：

> "The effect of using a captured continuation to enter or exit the dynamic extent of a call to before or after is unspecified."

R7RS 相对 R6RS **没有放宽任何要求**——逃逸续延实现对两者的偏差完全相同。项目的偏离记录在 `designs/06` §1。

**尾上下文问题（仍开放）**：`with-exception-handler`/`dynamic-wind` 的 thunk 实参按标准的句法定义是否算"尾上下文"。SRFI 157/255 的二手证据说 with-exception-handler 的 thunk 可以不在尾上下文；在定稿 `designs/06` 的措辞前，应直接引标准 PDF 原文。更重要的操作性事实是：这种调用的续延里挂着 `after`，按 Clinger 的 proper tail recursion 定义，它在**任何**实现里都不是真尾调用——Chez 也不例外。

## 5. Chez Scheme 的实现（一手源码核实）

`cisco/ChezScheme` 的 `IMPLEMENTATION.md`，原文：

> "A non-tail call moves SFP past all the live variables of the current function, installs the return address as a pointer within the current function, and then jumps to the called function. **Function calls and returns do not use machine 'call' and 'return' instructions; everything is just a 'jump'.** ('Call' and 'return' instructions are used for C interactions.) It's the caller's responsibility to reset SFP back on return, since the caller knows how much it moved SFP before calling."

也就是说，**没有 TCO 这个 pass**。调用约定里"调用"有两种形态；"尾调用"就是"不装返回地址"这个动作。自递归、互递归、未知目标（经闭包指针跳转）全部免费。这之所以可能，是因为 Chez 直接发机器码并拥有自己的调用约定和栈。我们的 `tail.` 前缀让 CoreCLR 的 JIT 替我们做了等价的事——**我们站在"Chez 阵营"，不在"Clojure 阵营"**。

**栈模型**：Dybvig 学位论文（《Three Implementation Models for Scheme》，1987）的 stack-based model；Scheme 栈与 C 栈分离；`%tc`（线程上下文）与 `%sfp`（栈帧指针）是保留寄存器；返回地址带 `rp-header` 元数据，GC 靠它识别帧形状。

**call/cc**：Hieb/Dybvig/Bruggeman 1990（《Representing Control in the Presence of First-Class Continuations》，PLDI）：分段栈；续延引用已保存的段；恢复时把段复制回来，必要时分裂以限制复制量；续延操作有界，且与栈溢出/下溢恢复共用同一套机制。C↔Scheme 边界经 `longjmp` 返回，原文明说是为了让两个栈相互独立、续延不污染外部帧。

**dynamic-wind**：纯 Scheme 实现，编译产物里没有一处机器 EH（`s/4.ss`）：

```scheme
(define (dwind in body out)
  (let ((old-winders ($current-winders)))
    (in)
    ($current-winders (cons (make-winder in out ($current-attachments))
                            old-winders))
    (call-with-values
      body                       ; ← 非尾调用；续延是消费者
      (case-lambda
        [(x)   ($current-winders old-winders) (out) x]
        [args  ($current-winders old-winders) (out) (apply values args)]))))

;; 续延跳转时 $do-wind：求公共前缀，先由内向外跑 out（unwind），再由外向内跑 in（rewind）
```

（Ikarus 的 `ikarus.control.ss` 是同算法的最简版：`winders` 列表、`unwind*`/`rewind*`、`call/cc` 保存 winders 并在调用时重绕。）

**对之前一处说法的修正**：早前备忘录里"Chez 级 O(1) 栈 + O(N) 堆 winders 能打败一帧一义务"对"递归穿过 wind"这一形态**不成立**。Chez 把 wind 的 body 当**非尾**调用（`call-with-values` 的生产者要带 `mvcall` 返回点），所以每轮重新进入 wind 的递归在 Chez 栈上同样每次激活压一个消费者帧——与我们现状完全同构。Chez 真正比我们强的只有**重入**（winders 随续延保存，跳回时 `rewind*` 重放 `before`）。

## 6. IronScheme 的现状（代码推导）

`codegen.sls`：

```scheme
(define (tail-ok? mc ctx)
  (and (eq? ctx 'tail) (= (mctx-try-depth mc) 0) (not (mctx-async mc))))
```

它门控四个发射点：

1. **自尾调用 / 命名 let 循环** → 重赋参数 + `br` 回 loop 标签（不涉及 CIL 调用，不需要 `tail.`）；
2. **已知目标** → 直接静态 `call` + `tail.`（同程序集，ECMA 强制情形；覆盖单元内互递归）；
3. **兜底** → `tail. callvirt Proc.InvokeK/InvokeN`（动态目标，依赖 CoreCLR 质量；iron-003 已验证千万层）；
4. **尾位置 `apply`** → 展开参数后 `tail. callvirt InvokeN`；
   （外加带 `allow-tail-call` 标志的原语）

`Emitter.cs`：`InstrKind.Tail → OpCodes.Tailcall`；结构化 `try` → `BeginExceptionBlock`/`BeginFinallyBlock`。

**当前行为的真实代价**（由 codegen 结构推导，需深度探针测试钉死）：

- 普通尾调用（自递归、互递归、未知目标、`apply`、带标志原语）：**真尾调用**。`EmitterTests` 已有 `MutualTailRecursionMillionDeep`。
- wind **体内部**的循环（`parameterize`/`dynamic-wind` 的 body 里写循环）：**常量栈**——body lambda 是独立方法，try-depth 0。（这是推断，必须用测试钉住。）
- 递归**穿过** wind 边界（每轮迭代重新进入 wind）：**每轮激活压一帧**——因为 `dynamic-wind` 是 `(in) ($try/finally (proc) (out))`，`(proc)` 在 try 内不是真尾调用。与 Chez 同价（见 §5），也与 R6RS/R7RS 的要求一致：这个调用的续延里挂着 `after`，在任何实现里都不算真尾调用。
- 余量：宿主跑在 **256 MB 栈线程**上（`Program.cs:27`），可撑数百万次保护激活。CLR 上 `StackOverflowException` 不可捕获，所以"栈深时抛一个清晰的 Scheme 条件"**不可实现**——大栈线程本身就是缓解手段，且已经存在。

## 7. CPS 的分析

遗留实验（`docs/notes/cps-conversion.txt`，DLR 时代）已经踩到两个硬点：

- 原语：统一转换为 `(proc k . args) => (k (proc . args))`，这样无需特殊发射；
- 高阶原语：`proc => (lambda (k . args) (k (apply proc args)))`，为异常处理捕获续延；
- 特殊 CPS 原语：`call/cc`、`call-with-values`、`values`、`apply`、`dynamic-wind`；
- 记录的问题：多余的闭包创建；"use labels and a **custom continuation class**... a fair amount of work"——即当时已经明白 CPS 下面必须垫帧/trampoline 层。

**决定性的结构事实**（本次调研）：

| | 栈 | 堆 |
|---|---|---|
| CPS + trampoline（穿过 wind 的递归） | O(1)（trampoline 循环） | O(N)（每轮 1 个 winder 节点 + 1 个消费者闭包，到底后按 LIFO 逐个调用跑 `after`） |
| 直接式（现状，与 Chez 相同） | O(N)（每轮 1 个消费者帧） | O(1) |

这些消费者续延是**严格 LIFO** 使用的（Danvy 意义上的二阶续延），其最优表示**就是栈帧**。所以直接式实现恰好落在 Danvy 1999 形式化证明的零开销策略上（《Formalizing Implementation Strategies for First-Class Continuations》：二阶续延留在栈上，一阶续延才复制到堆，并证明与标准 CPS 机等价）。**CPS 只是把同样的 O(N) 从廉价、缓存友好的栈，搬到昂贵、要过 GC 的堆。**

结论：**为 TCO 而做 CPS 在本项目是净退步**。唯一能为 CPS/帧机正名的目标是**一阶续延**（修复 `dynamic-wind` 重入、把 `windtests.sps` 重新纳入）——那是独立里程碑。

若将来真要写 CPS pass：放在宏展开（`front.sls`）之后，作为 L0→L0 的变换。需要注意的相互作用：原语统一包装与现有 `allow-tail-call` 原语路径冲突；`clr-*` 互操作调用是叶子但 **CLR 回调进 Scheme 的每个边界都需要 driver**；MultipleValues 按遗留笔记处理；`eval` 产出的代码必须与运行时形态一致；async 的 L0 节点（`escape-frame`/`label`/`jump`）已经是 CPS 风格，可以复用基础设施。

## 8. 建议（决策）

**A⁺（采纳）**：

- 保持 `tail.` 前缀作为**唯一**机制；不要为 try 区域引入新的调用约定。
- 加固：补 iron-003 未覆盖的尾调用形态测试（跨程序集 `tail. callvirt`、经 `ApplyArgs` 的 `tail. callvirt InvokeN`、同一方法内同时有 EH 区域与 depth-0 `tail.`、`VariadicProcedure::InvokeN` 尾链）；Scheme 深度探针（互递归/未知目标/`apply` 千万层；**wind 体内循环千万层**；穿过 `dynamic-wind`/`guard` 的递归——在 256 MB 线程上记录实际深度作为文档下限，不断言无界）；CI 用 `DOTNET_JITMinOpts=1` / `DOTNET_TieredCompilation=0` 跑矩阵，挡住未来 .NET 升级带来的 CoreCLR 尾调用行为变化。
- 精确措辞（`designs/03` §5、`designs/06` §1、README）："除跨越挂起的 finally/handler 恢复义务（`$try/finally`、`dynamic-wind`、`parameterize`、`with-exception-handler`、`guard`）外均为真尾调用；wind 体内的循环是真尾调用；每个活跃义务占一帧。" 并注明 `callvirt` 的可移植性警告。

**winders 路线（若 wind 开销在实践中真成问题）**：

- 把基于 CIL try 的 `dynamic-wind` 换成堆上的 winders 表，照 Chez `s/4.ss` / Ikarus `ikarus.control.ss` 的形状：进入时压 `(in,out)`，正常返回时经 `call-with-values` 消费者弹出并跑 `out`，逃逸边界（escape-frame 捕获点、REPL/Task 顶层）跑 `after`。这样 `(proc)` 恢复成真尾调用，穿过 wind 的递归从每轮一帧降为零。
- 范围：`boot/exceptions.sls` + `Control.cs` 逃逸路径 + 边界捕获点。天级工作量。**不修重入**；不动调用约定。

**帧机（完整 call/cc）**：仅当 `windtests.sps` 重新纳入时。持久化帧链用一个机制同时给出 TCO、可重入 `call/cc` 与正确的 winders 重入，并能吞掉 async 的 `AsyncFrame` 设计。月级工作量，会作废 Lcil 不动点纪律；保持为独立里程碑、单独开设计文档。任何时候都不做纯 trampoline（被支配）或"为 TCO 而 CPS"（退步）。

**JVM 后端（仅当 `designs/11` 需要时）**：见 §2.5——裸 `jmp` 不可复刻；路线排序 GraalVM Truffle > 方法级 trampoline > 单方法标签分派；Java 互操作的帧边界与 CLR 互操作问题同构。

## 9. 待实验/待核对清单

1. 深度探针：256 MB 线程上，穿过 `dynamic-wind`/`guard` 的递归实际深度（优化 vs MinOpts）。（`.sps` 探针，一小时。）
2. 用测试验证"wind 体内循环是常量栈"——若为假，说明 `codegen.sls` 把 wind 意外内联进了循环所在方法，是个小 bug，先修。
3. 跨程序集 `tail. callvirt` 与 `InvokeN` 路径在当前 .NET 10 上的表现。
4. 定稿 `designs/06` 措辞前，直接引 R6RS §11.20 / R7RS §3.5 原文（SRFI 157/255 只是二手证据）。
5. 核对 CLHS 3.5 是否确实含 "required"（调研期间页面未取到，社区说法冲突）。
6. 若 iron-052（async codegen）改变 `escape-frame` 的内联形态，针对 `guard` 密集代码重跑深度探针。

## 主要来源

- ECMA-335 Partition III §2.4（`tail.`）、§III.3.35（`jmp`）
- dotnet/runtime：`docs/design/features/tailcalls-with-helpers.md`；issue #2191、#58622；PR #50806；clr-interp 尾调用提交 c6af44d
- iron-003 探针结论（`designs/03-compiler.md` §5）
- R7RS-small corrected：§4.2.6、§6.10、Appendix A；概览（"required to be properly tail-recursive"）
- Clojure TCO 讨论串（groups.google.com/g/clojure/c/Oi2mpxoiE74）；cjfrisz/clojure-tco 的 README 与 `src/ctco/core.clj`；Danvy & Nielsen 2007
- CLHS：`unwind-protect`（3.6.4）、§5.2 unwind 次序；LispWorks tail merging 文档；SBCL 手册 5.3.4；0branch.com 的 TCO 调查
- Chez：`IMPLEMENTATION.md`；`s/4.ss`（`dwind`/`$do-wind`）；`s/np-languages.ss`；backend wiki；Hieb/Dybvig/Bruggeman PLDI 1990；Dybvig 学位论文 1987
- Ikarus：`scheme/ikarus.control.ss`
- Danvy 1999（BRICS-RS-99-51）：二阶/一阶续延的零开销分裂
- Clinger/Hartheimer/Ost 1999：续延实现策略分类
- Clinger PLDI 1998：Proper Tail Recursion and Space Efficiency
- OpenJDK mlvm wiki：TailCalls（`tailc.patch` 原型说明）
- John Rose：《tail calls in the VM》（web.archive 存档）；`cr.openjdk.org/~jrose/draft/vm-tailcall-jep.html`（JEP 草案）
- JDK-6804517（"Some languages need to be able to perform tail calls"，至今 Unresolved）
- mlvm-dev 邮件列表 2009-01（Arnold Schwaighofer 原型进度与保护域限制说明）

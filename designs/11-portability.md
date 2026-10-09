# 11 可移植性：宿主互操作的分层，与把"托管运行时"当作目标机器

> 起因：`(ironscheme clr)` 的名字是否该改成中性的，以及将来若有 JVM 实现，能否像 Chez 把 x86_64 / arm64 / pb 当作可替换的目标机器那样对待 CLR 与 JVM。
> 结论先行：**名字不改**，互操作库诚实地叫 `clr`；可移植性靠**分层**而不是改名；Chez 的"机器描述"思路能用，但要把"机器"定义在**托管运行时**这一层，而不是指令集。
> 本文只定原则和边界，不安排 JVM 移植本身；决定按 **D<n>** 编号。

## §0 事实（2026-10-09）

**源码树里 `clr-*` 的分布**（`src/scheme`）

| 层 | 用到 `clr-*` 的文件 | 说明 |
|---|---|---|
| boot 源码 `boot/` | **28 个**，约 1000 处 `clr-call` / `clr-new` / `clr-is` / `clr-static-call`，集中在 `io/ports`（145）、`bytevectors`（63）、`numbers`（43）、`hashtables`（31）、`base`（28） | 语言核心直接耦合宿主 |
| 平台库 `lib/ironscheme/*.sls` | 29 个（files、threading、process、datetime、web、regex …） | 本来就是宿主功能的包装 |
| 标准库 `lib/ironscheme/std/` | 6 个（time、system、localization、generators、syntax、private/hashtables-126） | 应收敛 |
| 编译器 `lib/ironscheme/compiler/` | 6 个：L0 有 `clr-call` 等互操作节点（[03 §7](03-compiler.md)） | 前端带着 CLR 形状 |

**管线的目标相关程度**（[03](03-compiler.md)、[04](04-lcil-and-emitter.md)）
- parse-core → analyze → simplify-letrec → cp0-lite → convert-assignments → uncover-free（L0 ~ L3）：除互操作节点外与目标无关。
- codegen（L3 → Lcil）：按托管对象模型生成——lambda → `Procedure` 子类、自由变量 → 字段、库变量 → 静态字段、`$try/finally` → 结构化 try、尾调用 → `tail.`。类名与原语的内联模板是 CLR 的。
- Lcil → DLL：`IronScheme.Emit`（C#），`PersistedAssemblyBuilder`。
- 运行时 `IronScheme.Core`（C#）：原语用 `[Primitive]` 标注，`primitives.ss` 由 PrimGen 从属性生成，是编译器与运行时之间的契约。
- 自举：stage0（C# 解释器）跑文本种子 → 编译器编译自己 → 不动点（[05](05-bootstrap.md)）。

**Chez 的做法**（`~/workspace/ChezScheme`）
- 每个目标一个机器描述文件 `s/x86_64.ss`、`s/arm64.ss`、`s/pb.ss`，由 `machine-type` 选择（`s/build.zuo:128`）：`define-registers`、一组固定抽象指令的 `define-instruction`、汇编器；常量来自 `*.def`，编译器用 `(constant …)` 取目标值。
- `cpnanopass.ss` 的几十个 pass 与机器无关，降到**寄存器机 IR**（显式栈帧、寄存器分配、调用即跳转、GC 栈图）后才进入机器文件（`(architecture assembler)`，`cpnanopass.ss:8625`）。
- pb 是 load-store 寄存器机，由 `c/pb.c` 解释，仍依赖 C 内核（GC、分段栈、续延）；用途是一套 boot 文件到处能跑。
- 交叉编译：宿主 Chez 加载目标机的 `xpatch` 后产出目标机的 boot 文件（`IMPLEMENTATION.md` "target-machine constants"）。

**CIL 与 JVM 字节码的异同**
- 相同：类 / 字段 / 方法、虚调用、带类型局部变量 + 操作数栈、分支与 `switch`、结构化异常、装箱、字符串为 UTF-16。
- 不同：尾调用（CIL `tail.`，JVM 无）；泛型（实化 / 擦除）；finally（原生 / 由编译器复制或 catch-all 再抛）；验证（ILVerify 可选 / JVM 必须有 StackMapTable）；方法大小（无限制 / 64 KB）；值类型（`int` 装箱 / `Integer` 缓存）。

**GC 不在抽象范围内**：两个宿主都自己拥有内存与栈。Chez 为 GC 做的事——对象布局与标签编码、内联分配序列、安全点与栈图、写屏障、分段栈与栈复制、`collect` 系列过程——IronScheme 一项都没有，JVM 移植同样一项都不用做，所以 §2 的机器描述表里没有 GC 一项。仍要关注的只是 GC **可观察的行为**：
- 分配量是性能的主要变量（fixnum 装箱、`MultipleValues`、闭包、async 帧、`RestList`），iron-033 / 034 的工作本质是减少分配，不是管 GC；
- 栈归运行时：.NET 的栈溢出不可捕获、直接杀进程，JVM 的可捕获——尾调用（`tail.` / 蹦床）与 async 深递归（续延链在堆上）才是要设计的地方；
- 非托管资源（端口、句柄、套接字）不能靠回收关闭，平台库不得假定"无引用即释放"；
- 弱引用与终结（.NET `WeakReference` / `ConditionalWeakTable` / 终结器，JVM `WeakReference` / `Cleaner`）若要提供，语义按两者交集在可移植包装层定义；
- FFI 把字节向量交给本机代码时的固定（`fixed` / `GCHandle`）是 C# 运行时内部的事，Scheme 侧不可见。

## §1 互操作库与分层

**D1 名字不改**：`(ironscheme clr)` 不是抽象层，是 CLR 对象模型的直接绑定：类型名、属性与字段之分、重载解析、`clr-using` 的命名空间、`(Task Object)` 这种泛型写法都是 CLR 的概念。改叫 `host` / `interop` 不会让 `(host-static-call System.IO.File …)` 在 JVM 上跑起来，只会制造"看起来可移植"的假象（ClojureCLR 与 Clojure 互操作语法完全相同，代码照样靠 `#?(:clj … :cljr …)` 分开写）。将来 JVM 实现提供 `(ironscheme jvm)`，形式为 `jvm-call` 等，同样诚实命名。

**D2 三层**：
1. **宿主绑定**：`(ironscheme clr)`、将来的 `(ironscheme jvm)`。明说的逃生口，用了就不可移植。
2. **可移植包装库**：`(ironscheme files)`、`(ironscheme threading)`、`(ironscheme async)`、`(ironscheme process)`、`(ironscheme datetime)` … 接口是 Scheme 风格、不暴露宿主类型，实现按宿主各写一份（同一库名，不同文件，由库搜索路径或 `cond-expand` 选）。用户想写可移植代码只用这一层。
3. **语言核心与标准库**：`boot/` 与 `(ironscheme std …)` **不直接用 `clr-*`**，只用原语。原语表（§2 D7）就是宿主接口。

**D3 boot 去 `clr-*`**：把 §0 那约 1000 处收进 C# 原语。每处都是机械改写（`(clr-call X M a b)` → `($x-m a b)`），按文件分批做，先 `io/ports`、`bytevectors`、`numbers`、`hashtables`。同时是性能改进：原语调用是静态 `call`，`clr-call` 经发射器静态解析时也是，但原语可带 `pure` / 内联模板。std 的 6 个文件同样处理。这是后续任务，不阻塞其他工作。

**D4 `cond-expand` 特性**：`(ironscheme std syntax)` 的 `cond-expand` 识别特性 `clr`、`jvm`（以及 `ironscheme`、`r6rs`、os、arch），供必须同时写两种实现的少数代码用；特性的来源见 D5。

**D5 宿主与机器侦测**：`(ironscheme)` 核心提供三个过程（C# 原语实现，boot 里不用 `clr-*`），对应 Chez 的 `(machine-type)`：

| 过程 | 值 | 例 |
|---|---|---|
| `(host-type)` | 宿主运行时，符号 | `clr`、将来 `jvm` |
| `(host-version)` | 宿主运行时版本，字符串 | `".NET 10.0.12"` |
| `(machine-type)` | `宿主-体系结构-操作系统`，符号；分量与 `(ironscheme std system)` 的 `cpu-architecture`、`os-name` 一致 | `clr-x86-64-linux`、`clr-arm64-osx`、`jvm-x86-64-windows` |

体系结构名：`x86-64` `i386` `arm64` `arm`（其余为宿主名字的小写）；操作系统名：`linux` `windows` `osx` `freebsd`（其余为小写的描述）。
- **编译期**另有 `(target-host-type)`：编译器 `target` 参数（§2 D6）的值，不交叉编译时等于 `(host-type)`。`cond-expand`（`(ironscheme std syntax)`）的特性由它和运行时的 os / arch 过程给出：`clr` / `jvm`、`x86-64` …、`linux` / `windows` / `posix` …、`ironscheme`、`r6rs`。
- **注意**：`cond-expand` 在展开期求值，os / arch 特性会被烤进 `.fasl`；托管代码本身跨 os，所以需要按 os 分支的**运行时**行为应当用 `(os-name)` / `(machine-type)` 在运行时判断，`cond-expand` 的 os 特性只用于源码级的条件定义。宿主特性（`clr` / `jvm`）没有这个问题——`.fasl` 本来就只属于一个宿主。
- `(ironscheme std system)` 与 `(ironscheme std syntax)` 现有的 `clr-*` 查询改为调用这些原语（归入 D3 的 std 批次）。

## §2 编译器：把托管运行时当作目标机器

**D6 Chez 思路的正确层次**：Chez 后端的契约是"一台我完全拥有内存、栈、GC、调用约定和代码布局的寄存器机"，CLR / JVM 给的恰恰相反（栈机、固定对象布局、运行时的 GC、方法是边界、要过验证器）。所以 Chez 从寄存器分配往下的 pass 这里都用不上；IronScheme 已经把"机器"换成了托管对象模型，这就是管线在 L3 之后直接 codegen 的原因。能借的是**结构**：一个与目标无关的管线 + 每个目标一份机器描述 + 每个目标一个发射器，"机器"定义为**托管运行时**：

| 层 | 现状 | 目标形态 |
|---|---|---|
| L0 ~ L3 | 互操作节点是 `clr-call` 等 | 节点改为宿主中性的 `host-call` / `host-new` / `host-is` …（源码层的 `clr-call` 宏展开到它们），由后端按目标解析；其余不变 |
| codegen | CLR 类名与内联模板写死 | 接受 `target` 参数查**机器描述表**：运行时类名、是否发 `tail.`、原语内联模板、装箱方式、方法大小限制。对应 Chez 的 `(constant …)` |
| Lcil | CIL 的文本形式 | 即"托管机"的 IR：指令集按两者交集定义，目标特有的（`tail.`）由机器描述决定是否出现 |
| 发射器 | Lcil → DLL（C#） | 每个目标一个：Lcil → DLL、Lcil → `.class`。发射器只是序列化器，可以用 Scheme 写，让 IronScheme 自己产出类文件 |

**D7 运行时契约 = 原语表**：`IronScheme.Core` 按目标重写（Java 版），`[Primitive]` 对应注解，`primitives.ss` 从两边都能生成，签名、`pure` / `unsafe` / `allow-tail-call` 标志与内联模板名必须一致。这是移植里最大的一块，和 Chez 的 C 内核一样没法共享。

**D8 自举靠交叉编译**：不写 Java 版 stage0。.NET 上的 IronScheme 以 `target = jvm` 编译 boot 源码与系统库，直接产出 JVM 的 boot 镜像与 `.fasl`；JVM 侧只需要运行时和一个加载器。与 Chez 用宿主机产出目标机 boot 文件相同，也是整个移植里最省力的一点。不动点检验改为"JVM 上的 IronScheme 编译自己得到的镜像与交叉编译的镜像一致"。

**D9 JVM 的已知难点**（按难度排序，供评估用，不在本文解决）：
1. 尾调用：JVM 没有。自尾调用仍是循环；互相尾递归要蹦床（返回 thunk 由调用方循环），影响 `Procedure` 的调用约定，可能只对标记为"可能深尾递归"的调用启用。
2. StackMapTable：发射器要在每个分支汇合点给出局部变量与栈的类型；Lcil 已检查汇合点栈形状，再加类型即可。
3. 64 KB 方法限制：大模块的 `Init` 切分（现在每个顶层形式一个 `Init<k>`，已接近）、巨大的常量表拆分。
4. finally 复制、泛型擦除（生成代码几乎不用泛型）、`Integer` 缓存与 `long` 的 fixnum 表示。

## §3 现在做什么、不做什么

| 做 | 不做 |
|---|---|
| D3：boot 与 std 去 `clr-*`（后续任务，分批） | 改 `(ironscheme clr)` 的名字 |
| D6 第一行：L0 互操作节点改 `host-*`，codegen 加 `target` 参数与机器描述表（现在只有一个表项 `clr`；空转成本低，但把 CLR 形状赶出前端） | 现在写 JVM 发射器或 Java 运行时 |
| 新库遵守 D2（例如 [10](10-async.md) 的 `(ironscheme async)`：`task-*` 接口中性，`Task<object>` 只是 CLR 后端的表示） | 为了假想的目标改动 Lcil 指令集 |

## §4 与其他文档的关系

- [00](00-overview.md) 关键决策：加"互操作三层、原语表是宿主契约"。
- [02 §9](02-runtime.md)、[03 §7](03-compiler.md)：互操作节点改名后更新。
- [05](05-bootstrap.md)：D8 的交叉编译作为第二种自举路径（需要时再写）。
- [10 §1](10-async.md) D3：`Task<object>` 是后端表示，可移植契约只是"task 对象"。

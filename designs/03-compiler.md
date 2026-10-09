# 03 nanopass 编译器

## 1. 位置与组织

| 项 | 决定 |
|---|---|
| nanopass 框架 | **第三方依赖**：git 子模块 `src/scheme/lib/nanopass-framework-scheme`（固定提交 `c14d3924`；iron-002 已在旧系统上验证可直接运行）（上游 https://github.com/nanopass/nanopass-framework-scheme，MIT 许可）。该目录加入库搜索路径，使 `(nanopass)` 解析到其中的 `nanopass.ss`。用其 `implementation-helpers.ironscheme.sls` 适配；需要的修改以补丁或覆盖库的形式放在子模块之外，不改子模块内容 |
| 编译器源码 | `Console/lib/ironscheme/compiler/*.sls`，库名 `(ironscheme compiler …)`：放在标准库目录下，经库路径（`-I lib`）直接解析（iron-020 调整）。`Console/compiler/` 只放原语表等数据文件与编译器测试（`tests/compiler/`） |
| 原语表 | `src/scheme/boot/primitives.ss`，由 `IronScheme.PrimGen` 生成（02 §5） |
| 进入 boot 镜像 | 是。新系统运行时 `eval` 需要编译器，所以编译器库与 nanopass 一起编进 boot 镜像 |
| 纯函数原则 | 编译器**不读运行时状态**：不调 `symbol-value` 查绑定，不执行目标原语，不反射目标程序集。它的全部输入是 Lcore 数据、原语表数据和编译选项 |

## 2. 输入语言 Lcore

即展开器 `rewrite`（`boot/expander/internal.sls:37-113`）的输出。以下是**固定文法**，`parse-core` 只接受这些形式，其余报错。

```
e ::= x                                  ; 符号（见 §3 分类）
    | (quote d)                          ; 展开器对所有字面量都加 quote
    | (if e e e) | (if e e)
    | (begin e ...)
    | (set! x e)
    | (case-lambda [fmls body] ...)
    | (annotated-case-lambda ann [fmls body] ...)
    | (typed-case-lambda [fmls tspec body] ...)
    | (annotated-typed-case-lambda ann [fmls tspec body] ...)
    | (lambda fmls body)                 ; 少见，保留
    | (async-lambda fmls body)           ; 体编译成状态机（10 §1）；(await e) 以原语调用的形式出现
    | (letrec ((x e) ...) body)
    | (letrec* ((x e) ...) body)
    | (library-letrec* name ((x loc e) ...) body)
    | (annotated-call ann . X)           ; X 为 符号 | (quote d) | (set! …) | (f arg …)
    | (clr-…-internal …)                 ; 互操作形式，见 §7
    | (ffi-callout-internal …) | (ffi-callback-internal …) | (pinvoke-call-internal …)
    | (e e ...)                          ; 应用
fmls ::= (x ...) | (x x ... . x) | x
body ::= e ...                           ; 展开器实际只生成一个
```

- `$try/finally`、`$throw`、`$break`、`$and?`、`$or?`、`await` 等以**原语调用**的形式出现（`($try/finally e1 e2)`），由编译器按原语表中的"特殊原语"处理。
- `typed-…-lambda` 第一版**按无类型处理**：忽略类型说明，参数和返回值按 `object` 编译；以后再利用类型做拆箱。
- `annotated-*` 中的注解只取源位置，供调试信息使用。

## 3. 符号分类（parse-core 时决定，不查运行时）

| 类别 | 判定 | 编译结果 |
|---|---|---|
| 词法变量 | 被外层 binder 绑定 | 局部变量 / 参数 / 闭包字段 / Box |
| 原语 | 不是词法变量，且在原语表中 | 原语调用（内联 IL、静态调用、或特殊处理） |
| 全局位置 | 其余所有符号（loc gensym 或顶层名字） | 读写该符号的 `Value` 值槽 |

`library-letrec*` 中的 `(x loc e)`：`x` 是库内词法名，`loc` 是对外的位置符号。编译为：库体内用局部或静态字段访问 `x`，同时把值写入 `loc` 的值槽。`library-letrec*` 也可以出现在非顶层位置（`compile-library` 把库的 invoke 代码包在 lambda 里），此时与顶层形式编译方式相同。

常量表按 `Equals` 去重（同一单元中相同的常量只占一项）；含 `-0.0` 分量的非精确数（`-0.0`、`-1.0-0.0i` 等）不去重，否则会与 `0.0`、`-1.0+0.0i` 合并（iron-031）。

## 4. pass 链

与研究笔记 `chez-on-clr-feasibility.md` 6.3 的 22 步对应，按 IronScheme 的输入做了合并。语言名为草图，实现时以 `define-language` 为准。

| # | pass | 输入 → 输出 | 做什么 | Chez 对应 |
|---|---|---|---|---|
| 1 | `parse-core` | Lcore（S 表达式）→ L0 | 解析固定文法；符号分类；`case-lambda` 规范化；剥离注解保留源位置 | 展开器之后的解析 |
| 2 | `recognize-let` | L0 → L1 | `((case-lambda [fmls body]) args)` → `let`；单子句 `case-lambda` → `lambda` | `np-recognize-let` |
| 3 | `simplify-letrec` | L1 → L1 | `letrec`/`letrec*` 按依赖拆成强连通分量；右边不是 lambda 的变成 `let` + `set!` | `cpletrec`、`np-identify-scc` |
| 4 | `cp0-lite` | L1 → L1 | 常量折叠（只对原语表标为 `Pure` 的 fixnum/flonum/谓词原语）、`if` 常量测试、死代码、单次使用的 `let` 内联 | `cp0`（大幅简化） |
| 5 | `convert-assignments` | L1 → L2 | 被 `set!` 且被闭包捕获的词法变量改为 `Box`；L2 中没有对这类变量的 `set!` | `np-convert-assignments` |
| 6 | `uncover-free` | L2 → L3 | 计算每个 lambda 的自由变量 | `np-convert-closures` 前半 |
| 7 | `convert-closures` | L3 → L4 | lambda → 过程类（自由变量为字段）+ 构造；无自由变量的提升为静态方法 + 单例；已知调用改为直接调用 | `np-convert-closures`、`np-optimize-direct-call` |
| 8 | `lift-to-classes` | L4 → L5 | 所有代码体变成类上的方法；模块入口 `Initialize`；程序 = 类定义列表 | `np-lift` |
| 9 | `lower-loops` | L5 → L6 | 自尾调用、命名 let 循环 → 重新赋参数 + 跳回标签；标记其余尾调用 | `np-recognize-loops` |
| 10 | `lower-calls` | L6 → L7 | 应用 → 直接静态调用 / `InvokeK` / `InvokeN`；原语 → 内联 IL 模板或静态调用（§6）；全局读写 → 值槽访问；`call-with-values` 遇到字面 lambda 消费者时内联 | — |
| 11 | `lower-interop` | L7 → L7 | `clr-*-internal` → Lcil 互操作指令（符号化成员引用，交给发射器决议，§7） | — |
| 12 | `normalize-context` | L7 → L8 | 区分值/副作用/谓词上下文；谓词上下文中的比较原语直接生成分支 | `np-simplify-if`、`np-normalize-context` |
| 13 | `lift-try` | L8 → L9 | `$try/finally`、逃逸续延帧等出现在表达式位置时提升为语句，结果存入临时变量（CIL 要求进入 try 时求值栈为空） | — |
| 14 | `linearize` | L9 → Lcil | 表达式树 → 带标签的栈式指令；分配局部变量；计算 `.maxstack`；检查分支汇合点栈形状；决定 `tail.` | `np-remove-complex-opera*` + 代码生成 |
| 15 | `emit-lcil` | Lcil → 文本 | 输出 Lcil 文本（04） | — |

第一版不做的：类型推断与拆箱（fixnum/flonum 局部变量）、跨库直接调用、内联非原语过程。留到 M6。

### 4.1 第一版的实际实现（M4，iron-022 ~ 027）

库位于 `Console/lib/ironscheme/compiler/`，驱动为 `(ironscheme compiler)`（`lib/ironscheme/compiler.sls`）。中间语言见 `languages.sls`：

| 语言 | 内容 |
|---|---|
| L0 | parse-core 输出；词法变量 `x`、全局位置 `(gref s)`、库变量 `(mref x)`、原语 `(prim pr)`/`(primcall pr e …)`；`(lambda 名字 (clause (x …) 剩余 体) …)`、`(async-lambda 名字 (clause …))`；`(library 名字 ([x loc e] …) 体)`；特殊原语为 `and` `or` `throw` `break` `try-finally` `await`；互操作 `clr-…`。`let` 与异步节点 `(label f (x …) 体 循环体)` `(jump f e …)` `(escape-frame k 体)` 只由 lower-async 产生（iron-051） |
| L1 | `letrec` 只绑定 lambda（`let` 自 iron-051 起已在 L0 中） |
| L2 | 增加 `box` `unbox` `set-box!` |
| L3 | lambda 带自由变量表 |

| 步骤 | 实现 |
|---|---|
| 1 parse-core | `parse.sls`，L0 |
| — lower-async | `async.sls`，L0 → L0（iron-051，[10 §3.2](10-async.md)）：只改 `async-lambda` 的体——命名 let / `do` 的单绑定 letrec 变 `label`/`jump`，立即调用的 lambda 与 `dynamic-wind` / `with-exception-handler` / `call-with-values` / `call/cc` 的字面 lambda 实参内联，`await` 拆到语句位置，剩余不合法的 `await` 报错；没有 `async-lambda` 的单元原样返回 |
| — analyze | `front.sls`：一遍分析得出被赋值、被捕获的词法变量，letrec 右边引用的同组变量，被 `mset!` 的库变量 |
| 2、3 recognize-let + simplify-letrec | 合为一个 pass（`front.sls`，L0 → L1）：连续的、未被赋值的 lambda 绑定成一组 `letrec`；其余为 `let`；右边引用了此后（不在同一组）才绑定的变量时，该变量先绑定为未指定值再按序 `set!` |
| 4 cp0-lite | `if` 常量测试、`begin` 中的常量、少量纯原语（`$fx+` 等、`not`、`null?`、`pair?`、`eq?`）的常量折叠 |
| 5 convert-assignments | 既被赋值又被捕获的变量改为 Box（形参在子句入口装箱） |
| 6 uncover-free | `closures.sls`，L2 → L3 |
| 7 ~ 14 | 合在 `codegen.sls` 的一遍按上下文（value / effect / test / tail）生成栈式代码中：lambda → Procedure 子类（无自由变量者静态方法 + 单例）；库变量 → 模块静态字段；库中无自由变量且不被再赋值的 lambda 为"已知过程"，入口先预链接（创建并写入字段与位置，等同旧系统的静态链接，支持跨库前向调用），参数个数相符的调用直接 `call` 静态子句方法；自尾调用 → 重新赋参数并跳回方法开头；其余尾调用加 `tail.`（try 内不加）；尾位置的 `apply` 展开后 `tail. callvirt InvokeN`；谓词原语在 test 上下文直接生成比较；后面的操作数含 try 时先把全部操作数存入临时变量（lift-try）；`.maxstack` 由发射器计算 |
| 15 emit-lcil | `lcil.sls`，块状结构逐行写出 |

与 ChezScheme 的对照（`~/workspace/ChezScheme/s`）：
- **原语数据**：Chez 的 `primdata.ss` 用 `define-symbol-flags*` 声明每个原语的签名（参数类型 → 结果类型，如 `[sig [(fixnum fixnum) -> (boolean)]]`）、谓词信息与细分标志（`pure`、`mifoldable`、`discard`、`unrestricted`、`safeongoodargs`、`arith-op`、`cp02` …），按库分组。我们的 `primitives.ss` 由 C# 特性生成，只有重载、`pure`/`unsafe`/`allow-tail-call` 与内联模板名，没有类型签名。M6 做类型推断与拆箱（iron-033）时应仿照 Chez 加入签名与"可折叠 / 可丢弃"的区分。
- **内联**：Chez 的 `cpprim.ss` 用 `define-inline 级别 名字 [子句 …]` 表驱动地写了 600 多个内联处理器，安全级别（2）先做类型检查、失败时退回库调用（`build-libcall`）。我们的内联模板写在代码生成的 `case` 中，带检查的 `car`/`cdr` 等仍是静态调用。以后宜把模板移到独立的表驱动模块，并加入"检查 + 退回"的安全内联。
- **pass 粒度**：Chez 的 `np-languages.ss` 定义了 L1 ~ L16 等二十多个语言，`cpnanopass.ss` 中 `np-recognize-let`、`np-convert-assignments`、`np-recognize-loops`、`np-convert-closures`、`np-optimize-direct-call`、`np-simplify-if` 等几十个小 pass 各做一件事。我们第一版把第 7 ~ 14 步合在一个代码生成过程里；M6 优化时宜按 Chez 的方式拆成独立 pass（循环识别、闭包转换、直接调用优化、if 化简各一个语言层次）。

内联模板：`void` `$car` `$cdr` `cons` `eq?` `not` `null?` `pair?`、`$fx` 算术 / 位运算 / 比较 / 零与符号判断、`$fl` 算术与比较（`<=`、`>=` 对 NaN 为假）；其余原语静态调用。`call/cc`、`call-with-values`、`values` 用原语表中的后备实现（静态调用）；`ffi-*`、`pinvoke-call-internal`、`define-clr-class-internal` 编译为运行时报"尚不支持"。第一版不生成序列点（注解在 parse-core 剥离）。

## 5. 尾调用

- **自尾调用**（含命名 let、`do`）：pass 9 改写成循环，不占栈。
- **其余尾位置调用**：发射 CIL `tail.` 前缀，作用于 `callvirt Procedure::InvokeK` 与对静态方法的 `call`。
- **async 体内没有尾调用**（iron-052，[10 §3.3](10-async.md) D13）：`async-lambda` 的体是状态机的 `MoveNext`，结果经 `Complete` 交出，`tail-ok?` 恒假，也没有自尾调用循环（命名 let / `do` 由 `lower-async` 变成 `label`/`jump`）。
- **不能加 `tail.` 的位置**：try/catch/finally 区域内（CIL 禁止）。`$try/finally`、逃逸续延帧内部的尾调用因此不是真尾调用，这与 R6RS 对 `dynamic-wind` 的规定一致（thunk 调用本来就不在尾位置）。
- 依据：iron-003 在 .NET 10（Linux x64）实测：经虚调用的相互尾递归、参数个数变化的尾调用、调用静态方法、被调方需栈传参的尾调用，一千万层全部通过，关闭 JIT 优化（`DOTNET_JITMinOpts=1`）时依然成立；不加前缀的对照在关优化时约一万层栈溢出。栈传参情形走运行时辅助路径，约慢 8 倍，参数多的调用本来就走 `InvokeN`，影响有限。

## 6. 原语的编译

原语表（`src/scheme/boot/primitives.ss`，由 `IronScheme.PrimGen` 生成，iron-012）格式：

```scheme
(primitive-table 1
  (primitive car
    (overload "IronScheme.Core.Builtins" "Car" 1 #f () car))           ; 类型 方法 固定参数个数 剩余参数? (标志…) 内联模板
  (primitive $fx-
    (overload "IronScheme.Core.Unsafe" "FxNeg" 1 #f (pure unsafe) $fx-)
    (overload "IronScheme.Core.Unsafe" "FxSub" 2 #f (pure unsafe) $fx-))
  (special $try/finally try-finally)                                    ; 编译器专门处理
  …)
```

标志为 `pure`（可常量折叠）、`unsafe`（不检查类型）、`allow-tail-call`。`special` 条目有 10 个：`$and?` `$or?` `$break` `$throw` `$try/finally`（作用于未求值的参数表达式）、`call/cc` 与 `call-with-current-continuation`（逃逸帧）、`call-with-values`、`apply`、`values`；其中有同名 `primitive` 条目的，该条目是非内联时的后备实现。

| 种类 | 编译方式 |
|---|---|
| 内联 IL 模板 | 编译器内置模板，如 `car`：类型检查后 `ldfld Cons::car`；`$car`：不检查直接取；`$fx+`：拆箱、`add`、装箱；`eq?`：`ceq` 后转布尔对象 |
| 静态调用 | `call` 对应的 C# 静态方法 |
| 特殊原语 | `$try/finally`、`$throw`、`$break`、`$and?`、`$or?`、`call/cc`（逃逸帧）、`values`、`call-with-values`、`apply`：编译器专门处理 |
| 作为值使用 | 原语名出现在非调用位置时，读其名字符号的值槽，得到登记的 `Procedure` |

装箱的 fixnum：第一版沿用现状，`int` 每次装箱。可以加一个小整数装箱缓存（现有 `Int32ToObject` 的做法）。

## 7. CLR 互操作形式

| 形式 | 编译结果（Lcil 指令，详见 04） |
|---|---|
| `clr-call-internal 'T 'member inst arg…` | `(clr-call T member static? argc)`，参数按 `object` 压栈 |
| `clr-field-get/set!-internal` | `(clr-field-get T name static?)` / `(clr-field-set …)` |
| `clr-new-internal` / `clr-new-array-internal` | `(clr-new T argc)` / `(clr-new-array T)` |
| `clr-cast-internal` / `clr-is-internal` / `clr-type-of-internal` | `(clr-cast T)` / `(clr-is T)` / `(clr-type T)` |
| `clr-using-internal` / `clr-reference-internal` | **编译期上下文**：命名空间与程序集列表作为 Lcil 方法的元数据传给发射器，由发射器做类型查找；本身编译为未指定值 |
| `clr-namespaces-internal` | 当前命名空间列表常量 |
| `ffi-*`、`pinvoke-call-internal` | 第一版编译为对运行时辅助方法的调用（运行时构造委托 / DllImport 包装）；以后再做静态生成 |

类型名 `'T` 若是符号且不是类型名，现状会在编译期 `symbol-value` 取类型对象。新编译器不这样做：只接受字面类型名，其他情况编译为运行时 `Interop` 调用。

## 8. 编译驱动

| 入口 | 新实现 |
|---|---|
| `compile-core`（eval） | Lcore → Lcil（S 表达式直接交给发射器，不经文本，iron-033）→ 发射器内存模式 → 调用入口方法 |
| `compile-library` | 13 元素列表（id、name、ver、imp*、vis*、inv*、subst、env、visit、invoke、guard、guard-req*、visible?）→ 一个 dll，入口 `Initialize` 返回该列表 |
| `compile-bootfile` | 36 个源文件展开后的核心形式列表 → `ironscheme.boot.dll` |

三个入口都替换 `IS/Runtime/Builtins.cs` 中的同名 C# 内建函数。`compile-library` 也直接把 S 表达式交给发射器（`SaveData`）；只有自举构建脚本写 Lcil 文本，用于比较各阶段产物。

codegen 在 `clr-new`/`clr-call` 的实参都是 `(clr-cast T e)` 时，把这些 `T` 作为实参类型提示写进 Lcil（04 §2），发射器据此静态选择重载（iron-033）。

## 9. 验证手段

- 每个 pass 后可以 `unparse` 打印中间语言；为典型输入建立快照测试。
- Lcil 文本可直接 diff，用于比较 stage0 编译与自举各阶段的输出。
- 不变量由 nanopass 文法检查；注意 nanopass 笔记中记录的陷阱：不带关键字的应用产生式会吞掉同形形式，L1 之后的应用产生式一律带关键字（如 `(call e e …)`）。

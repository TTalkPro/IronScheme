# 13 guard 与宿主异常（.NET/JVM）的互通

状态：设计提案（未实施）。记录"guard 能否/如何直接捕获宿主异常"的论证与选定方向。

## 1. 问题

`guard` 只接 Scheme 条件（`raise` 抛出的东西），接不到 CLR 异常。用户互操作代码（`clr-call` 等）抛出的 `IOException` 之类会作为 CLR 异常直接穿过 Scheme 帧。目标：让 `guard` 能统一处理两类异常，同时不破坏 R6RS 异常语义。

## 2. 为什么不能把 guard/dynamic-wind 统一为 try/catch/finally

结论：**finally 可以借，catch 不能借**。"借"的范围由控制流是否单向决定。

| 机制 | 映射到宿主异常？ | 条件 |
|---|---|---|
| `dynamic-wind` | ✅ `$try/finally`（编译器核心形式 → CIL try/finally） | 承诺永远只要逃逸型 call/cc；一旦支持重入续延就必须退回 Chez 式 winder 链（`$do-wind` 在续延跳转时对账 in/out） |
| `guard` / `raise` / handler 链 | ❌ 保持 handler 链表 + Scheme 层实现 | 无条件——R6RS 语义要求 |
| 与宿主异常互通 | ✅ 边界适配层 | 原语转换 + `with-clr-exception-handler` / `clr-guard` 桥 |

guard 不能落在 catch 上的三个原因：

1. **handler 的运行位置**：R6RS 要求 handler 在抛异常的动态环境中运行（栈未回卷，可检查现场）；CLR/JVM 的 catch 执行时栈已回卷到 try 点。CLR 的 exception filter 在回卷前运行但无法把值还给 throw 点。
2. **`raise-continuable`**：其实现是"handler 作为普通函数调用，返回值即 raise 的返回值"（`boot/exceptions.sls:90`），要求 handler 与抛出点共享同一条栈。try/catch 模型无法表达。
3. **无匹配时的重抛**：guard 无 clause 匹配时必须在原动态环境中 `raise-continuable`，外层 handler 要看到原始 handler 栈（`06-r6rs-and-testing.md` 记录保留此语义）。

### 分层澄清：guard 的 call/cc 只负责"送货"，不负责"接警"

guard 展开为 `call/cc` + `with-exception-handler`（psyntax `guard-macro`），call/cc 的 `escape-frame` 最终确实是 CIL try/catch——但它只承担**结果送达**（handler 匹配后跳回 guard 帧的一次性定向跳转）。真正的异常语义全部在"接警"阶段：handler 链是数据结构（`$current-handlers`），`raise` 在事故现场把 handler 当普通函数调用，**此刻没有任何 try/catch 参与**。底层基质（CLR 异常）提供能力，分层规定哪里可以用它；两者不构成"guard 等于 try/catch"。

## 3. 现状的适配点

- **IO 原语**：`R6RS/IO.cs` 显式 catch CLR 异常，翻译为 R6RS 条件（`FileNotFoundViolation` 等）经钩子 `raise`——`guard` 对内置 IO 错误已经可用。
- **通用互操作**：`Interop.cs` 的 `InvokeUnwrapped` 只拆包 `TargetInvocationException` 后原样重抛，原始 CLR 异常不进条件系统。
- **桥接原语**：`with-clr-exception-handler`（`R6RS/Exceptions.cs`）是真 CIL try/catch，捕获任意 CLR 异常交给 Scheme handler；`(ironscheme clr)` 提供 `clr-guard` 宏。
- **放行规则**：所有 catch 都必须 `catch (ContinuationException) { throw; }`，续延逃逸永远不被异常处理吞掉。

## 4. 方案与裁决

核心矛盾：CLR/JVM 异常抛出时 guard 不在场（只挂在 handler 链上）。所有方案都是"在某个点把宿主异常引渡进条件系统"，区别在引渡点。

| 方案 | 做法 | guard 改动 | 事故现场语义 | 实现成本 | 性能 |
|---|---|---|---|---|---|
| **A 源头转换**（选定） | 互操作层出口统一 try/catch，把 CLR 异常包成 `clr-condition` 走 `raise`（IO 原语已有模式的推广） | 无 | ✅ 完整：转换后 raise 时 Scheme 栈完好 | 低 | 不抛时 ≈ 0（仅 EH 表项） |
| B 混合 guard | codegen 让 guard 同时注册 handler 链 + 生成 CIL try/catch，catch 里包成条件喂给同一份 clause 逻辑 | codegen | ⚠️ 双轨：Scheme 条件在事故现场、CLR 异常在 guard 点 | 中 | 最优 |
| C 用户宏 | `guard*` = `with-clr-exception-handler` 转条件 + 内层 guard | 无（新宏） | ❌ 弱：转换点栈已回卷 | 极低 | 同 A |

**裁决：方案 A**。与"边界适配而非语义统一"的既有哲学一致；guard 保持纯洁的 R6RS 语义，宿主异常在进入 Scheme 世界的那一刻变成条件对象。

### 4.1 方案 A 要点

```csharp
// Interop 调用出口（InvokeUnwrapped 推广到所有 clr-* 入口）
try { return f(); }
catch (ContinuationException) { throw; }          // 永远放行
catch (Exception ex)
{ return Errors.RaiseClrCondition(ex); }          // 包成 clr-condition，经 RuntimeHooks.Raise
```

```scheme
(define-record-type clr-condition (parent &condition) (fields exception))
(define (clr-exception-of? type)
  (lambda (e) (and (clr-condition? e)
                   (clr-is? type (clr-condition-exception e)))))

;; 用户代码 guard 零改动：
(guard (e [((clr-exception-of? System.IO.IOException) e) (handle e)])
  (clr-static-call File (ReadAllText String) "x"))
```

### 4.2 延伸（可选）

把 `clr-condition` 做进条件层次（继承 `&error` 或 `&violation`），让 `error?`、`violation?` 等标准谓词对 CLR 异常也成立，达到真正无缝。

## 5. 表面语法：Clojure 风格 `try`（提案）

参照 Clojure 的 `(try body ... (catch IOException e ...) (finally ...))`，为互操作代码提供宿主异常的专用入口。定位：与 `guard`（条件世界，R6RS 语义）并列，**不取代** `guard`、`dynamic-wind`（R6RS 契约）或 `clr-guard`。

```scheme
(try
  body ...
  (catch (System.IO.IOException e) (handle-io e))   ; CLR 类型分派，clr-is? 子类匹配，顺序优先
  (catch (System.Exception e) (fallback e))
  (catch e (last-resort e))                          ; 裸标识符 = 捕获所有 CLR 异常
  (finally (cleanup)))                               ; 可选
```

展开（纯宏 + 已有零件，不动编译器）：

```scheme
($try/finally                                       ; finally → 已有核心形式
  (with-clr-exception-handler                       ; catch → 已有原语
    (lambda (ex)
      (cond [(clr-is? T1 ex) (let ((e1 ex)) c1 ...)]
            [else (clr-rethrow ex)]))               ; 无匹配：原样重抛
    (lambda () body ...))
  (lambda () f ...))
```

语义规则（对齐 Clojure，不发明新东西）：

1. catch 子句按书写顺序测试，第一个命中生效；catch 体在**回卷后**运行（CLR 异常天然语义）。
2. `ContinuationException` 永不进入分派（原语已保证放行）。
3. finally 总是执行（正常返回 / catch 命中 / 异常穿透）。
4. `try` 的值 = body 的值或被命中 catch 子句的值。
5. 配套原语 `clr-throw`（对称 Clojure 的 `throw`）。

**唯一新增运行时零件**：`clr-rethrow`（`ExceptionDispatchInfo.Capture(ex).Throw()`，保留原始栈轨迹）。其余全是现成组件的宏组装。

分工：

| 语法 | 处理对象 | handler 运行位置 | 用途 |
|---|---|---|---|
| `guard` | Scheme 条件 | 事故现场（R6RS 语义） | 标准 R6RS 代码 |
| `try`（本提案） | CLR 异常 | 回卷后（Clojure 语义） | 互操作代码 |
| `clr-guard` | CLR 异常 | 回卷后 | 保留，`try` 落地后可视作其子集 |

与方案 A 的关系：互补。方案 A 让 CLR 异常**也能进** `guard`；`try` 给互操作重的代码更直接、更合宿主习惯的写法。方案 A 落地后可考虑给 catch 子句扩展条件谓词形态 `(catch (i/o-error? e) ...)`，但那会引入 §2 的双轨语义，初版不做。

## 6. 可移植性注记

JVM 同理（见 `11-portability.md`）：try/catch 不抛时零成本，catch 里翻译成条件再 raise；续延逃逸的等价物永远放行。该方案不引入新的宿主依赖，只要求宿主异常类型可包装为条件负载。

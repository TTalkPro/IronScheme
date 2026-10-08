# 05 自举

## 1. 原则

- **只依靠 .NET 与本仓库**：不引入 ClojureCLR、Chez 或其他语言实现。
- **精简 stage0**：写一个 C# 的核心形式（Lcore）解释器，跑在新运行时 `IronScheme.Core` 上。它的唯一任务是把 psyntax、R6RS 库、nanopass 和新编译器运行起来，完成第一次编译。
- **种子是文本**：种子是 boot 源码**展开后的核心形式**（`boot-seed.core`），可以审阅、可以 diff，不是二进制 dll。
- **可验证**：以 Lcil 文本和二进制的不动点作为自举成功的判据。

## 2. 组成

| 组成 | 是什么 | 由谁产生 |
|---|---|---|
| `boot-seed.core` | boot 源文件（`build/*.sls`、`psyntax/*.sls`，37 个）经 psyntax 展开、`rewrite` 后的核心形式列表，文本 S 表达式 | 首次：旧 IronScheme 展开（它本来就做这一步，只是改为把结果写成文本而不编译）。之后：新系统或 stage0 自己重新生成 |
| `IronScheme.Stage0` | C# 的 Lcore 解释器 + 启动器，引用 `IronScheme.Core` | 本仓库源码 |
| nanopass | 第三方依赖，git 子模块 `nanopass-framework-scheme` | 上游仓库 |
| 新编译器 | `Console/lib/ironscheme/compiler/*.sls` | 本仓库源码 |

## 3. 流程

```
 第 0 步（一次性）：生成种子
   旧 IronScheme（DLR）运行 seed 构建脚本
     → psyntax 展开 37 个 boot 源文件 → 核心形式 → 写成 boot-seed.core
   （只展开，不执行；旧系统不需要认识新运行时，也不需要运行 nanopass）

 Phase A：stage0 编译出新 boot 镜像
 ┌──────────────────────────────────────────────────────────────────┐
 │ IronScheme.Stage0（C# 解释器，运行在 IronScheme.Core 上）            │
 │  1. 解释执行 boot-seed.core → 得到可用的 psyntax 与 (rnrs …) 库       │
 │  2. 用解释执行的 psyntax 从源码展开并运行 nanopass 与新编译器           │
 │     （nanopass 的 define-language / define-pass 宏在这里执行）       │
 │  3. 展开 boot 源文件 + 编译器 + nanopass → 核心形式                   │
 │  4. 新编译器（解释执行）：核心形式 → Lcil 文本                          │
 └──────────────────────────────┬───────────────────────────────────┘
                                ▼  boot.lcil
                   IronScheme.Emit（C#）→ ironscheme.boot.dll（stage1）

 Phase B：新系统自举
   stage1 运行构建脚本 → stage2（Lcil + dll）
   stage2 运行构建脚本 → stage3（Lcil + dll）
   判据：stage2 与 stage3 的 Lcil 文本一致，dll 逐字节一致
```

## 4. stage0 解释器

| 项 | 决定 |
|---|---|
| 输入 | Lcore 文本（与编译器的输入文法相同，03 §2） |
| 实现方式 | 先把核心形式分析成闭包树（"编译成闭包"式解释器）：变量预先解析为词法地址或符号值槽，执行时不再查名字 |
| 值与原语 | 直接使用 `IronScheme.Core` 的值表示、原语与 `Interop`（`clr-*` 形式经 `Interop` 反射执行） |
| 过程 | 解释器生成的闭包是 `Procedure` 子类，可以和原语、编译后代码互相调用 |
| 尾调用 | 用蹦床保证真尾调用（解释器内部循环），不依赖 CIL `tail.`；尾位置的 `apply` 也在循环中展开 |
| 预链接 | 执行种子时先为每个顶层 `library-letrec*` 建帧、创建全部库级过程并写入位置，再按顺序执行其余初始化。旧 boot 编译器把库级过程静态链接，种子中因此有跨库前向引用（如 exceptions 初始化时调用 compat 的 `make-parameter`） |
| `compile-core` | 由 stage0 提供：`(compile-core e)` 返回执行 `e` 的无参过程，psyntax 的 `eval` 经它执行展开结果 |
| 命令行 | `stage0 [--time] [--deterministic] [-I 目录] <种子> <脚本.sps> 参数…`（种子执行后以 `(load/program 脚本)` 运行）；`stage0 --core <文件>…` 直接解释 Lcore |
| 逃逸续延、`$try/finally`、多值 | 与编译后代码同样的运行时机制（02 §6） |
| 规模目标 | 一两千行 C#；只追求正确，不追求速度（每次自举只跑一次）。实现约 1000 行；种子执行约 0.3 s，加载 nanopass 约 4.5 s（旧系统编译执行约 2.5 s） |
| 额外用途 | 以后可以作为 NativeAOT 环境下 `eval` 的后备（不在首批范围） |

stage0 不实现展开器：展开器（psyntax）本身就在种子里，以核心形式的形式被解释执行。

## 5. 种子的生成与再生成

1. **首次**：旧系统（`legacy-stage0/` 中的快照）运行 `seed-buildscript.sps`（由现有 `ironscheme-buildscript.sps` 改写：保留展开部分，最后一步把 `(map compile-core-expr core*)` 写成文本，而不是调用 `compile-bootfile`）。命令为 `tools/gen-seed.sh`：旧系统会优先加载当前目录与脚本目录下的 `psyntax/*.sls` 源码，所以脚本复制到临时目录、在快照目录下运行，源码根目录作为参数。
   - 文本格式：核心形式与其中的常量都是标准 S 表达式，写出器自己实现（不用宿主 `write`），按新 reader 能逐值读回的写法输出 ASCII：符号中的非法字符用 `\xHH;`，字符串中的代理项对合成码点，flonum 检查往返，`-0.0` 单独处理。非调试模式下种子中没有注解、记录或语法对象。
2. 生成前，boot 源码已经改为面向新运行时（iron-013）。展开是纯数据处理，旧系统不执行这些代码。
3. **之后**：stage0 或新系统运行同一脚本即可重新生成种子。种子本身也有不动点：用种子在 stage0 上重新展开得到的种子应与原种子一致（确定性 gensym 前提下，见 §7）。
4. 种子文件放在 `IronScheme/IronScheme.Console/boot-seed.core`。

## 6. 交叉编译纪律

Phase A 中编译器跑在解释器上、宿主就是新运行时，比原先"跑在旧系统上"的方案简单得多：宿主对象和目标对象是同一套类型。仍需遵守：

| 规则 | 原因 |
|---|---|
| 编译器不读运行时状态（03 §1） | 保证编译结果只取决于输入，Phase A 与 Phase B 输出一致 |
| 原语信息只来自 `primitives.ss` | 同上 |
| 常量只经中立编码输出（04 §3） | 同上；也避免把解释器内部对象写进程序集 |

## 7. 确定性

| 来源 | 处理 |
|---|---|
| **gensym 名字含时间戳**（`g$name$N$TICKS`） | 构建模式（`deterministic-gensym?`）下 TICKS 换成 gensym 作用域名、计数在作用域内从 1 开始：psyntax 的 `library-expander` 在以库名为名的作用域（`$gensym-scope`）中展开整个库，作用域外为 `%top`，跨库唯一、可复现。文本种子由旧系统生成，写出时把本进程的 `$TICKS` 后缀改为 `$%seed`。后备：比较前对 Lcil 做 gensym α 重命名 |
| 哈希表遍历顺序 | 编译器与展开器中需要稳定顺序处一律按插入顺序或排序 |
| MVID、时间戳 | 发射器按内容哈希生成（04 §4） |

## 8. 种子管理

| 阶段 | 种子 |
|---|---|
| 现在 | 旧系统的可运行快照 `legacy-stage0/`（含原始 DLR 格式种子），只用于第 0 步生成文本种子。BuildTools 已删除，旧系统不能再从源码构建 |
| M2 完成后 | `boot-seed.core`（文本） |
| M6 完成后 | stage3 的 boot dll 作为二进制缓存放入工作区；从源码重建的路径是 `boot-seed.core` + stage0 |
| M7 删除旧系统后 | 旧 DLR 系统不再需要。从零重建只要 .NET SDK、本仓库（含 nanopass 子模块）与文本种子 |

## 9. 新系统中的构建脚本（Phase B）

- 编译器在 boot 镜像内；发射器以库 API 形式同进程调用（`LcilEmitter.Emit`），也可继续用命令行。
- `compile-bootfile`、`compile-library` 等由编译驱动实现（03 §8），不再是 C# 内建函数。
- 测试 `BootstrapTests` 改为：种子 → stage0 → stage1 → stage2 → stage3，比较 Lcil 与 dll，再做 ILVerify。

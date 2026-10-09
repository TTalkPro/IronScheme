# 05 自举

## 1. 原则

- **只依靠 .NET 与本仓库**：不引入 ClojureCLR、Chez 或其他语言实现。
- **精简 stage0**：写一个 C# 的核心形式（Lcore）解释器，跑在新运行时 `IronScheme.Core` 上。它的唯一任务是把展开器、R6RS 库、nanopass 和新编译器运行起来，完成第一次编译。
- **种子是文本**：种子是 boot 源码**展开后的核心形式**（`boot-seed.core`），可以审阅、可以 diff，不是二进制 dll。
- **可验证**：以 Lcil 文本和二进制的不动点作为自举成功的判据。

## 2. 组成

| 组成 | 是什么 | 由谁产生 |
|---|---|---|
| `boot-seed.core` | boot 源文件（`boot/` 下的 `*.sls` 与 `boot/expander/*.sls`，37 个）经展开器展开、`rewrite` 后的核心形式列表，文本 S 表达式 | 首次：旧 IronScheme 展开（它本来就做这一步，只是改为把结果写成文本而不编译）。之后：新系统或 stage0 自己重新生成 |
| `IronScheme.Stage0` | C# 的 Lcore 解释器 + 启动器，引用 `IronScheme.Core` | 本仓库源码 |
| nanopass | 第三方依赖，git 子模块 `nanopass-framework-scheme` | 上游仓库 |
| 新编译器 | `Console/lib/ironscheme/compiler/*.sls` | 本仓库源码 |

## 3. 流程

```
 第 0 步（一次性，已完成）：生成种子；之后由新系统或 stage0 再生成（§5）
   旧 IronScheme（DLR）运行 seed 构建脚本
     → 展开器展开 37 个 boot 源文件 → 核心形式 → 写成 boot-seed.core
   （只展开，不执行；旧系统不需要认识新运行时，也不需要运行 nanopass）

 Phase A：stage0 编译出新 boot 镜像
 ┌──────────────────────────────────────────────────────────────────┐
 │ IronScheme.Stage0（C# 解释器，运行在 IronScheme.Core 上）            │
 │  1. 解释执行 boot-seed.core → 得到可用的展开器与 (rnrs …) 库       │
 │  2. 用解释执行的展开器从源码展开并运行 nanopass 与新编译器           │
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

### 3.1 Phase A 的实际做法（iron-028）

`dotnet build`（`IronScheme.Host` 的 `GenerateBootImage` 目标；输出到其他目录用 `tools/build.cs stage1 <目录>`）→ stage0 执行种子后运行 `ironscheme-buildscript-nano.sps`：

1. 在 bootstrap 库集合中展开 37 个 boot 源文件；
2. 求出新 boot 的导出位置，并在构建进程中把它们绑定到同名值（展开器导出取脚本所用的源码副本，其余取运行中系统），使 nanopass 宏能在构建进程中执行；
3. 在 bootstrap 集合中加载 `(ironscheme compiler)`（连同 nanopass），经 `serialize-all` 取得 24 个库的 invoke 代码放进 boot；编译器的 `compile-core` 等经图例导出；
4. 用新编译器编译全部 62 个形式。确定性模式下 bootstrap 展开使用 gensym 领域 `boot:`，避免与运行中系统同名库的 gensym 冲突。

nanopass 的宏不随 boot 安装（boot 只含其运行时代码）；用户程序 `(import (nanopass))` 时从源码加载另一份。新宿主 `IronScheme.Host` 加载 stage1，`eval` 走镜像内的新编译器（内存模式常量传活对象，04 §3）。

## 4. stage0 解释器

| 项 | 决定 |
|---|---|
| 输入 | Lcore 文本（与编译器的输入文法相同，03 §2） |
| 实现方式 | 先把核心形式分析成闭包树（"编译成闭包"式解释器）：变量预先解析为词法地址或符号值槽，执行时不再查名字 |
| 值与原语 | 直接使用 `IronScheme.Core` 的值表示、原语与 `Interop`（`clr-*` 形式经 `Interop` 反射执行） |
| 过程 | 解释器生成的闭包是 `Procedure` 子类，可以和原语、编译后代码互相调用 |
| 尾调用 | 用蹦床保证真尾调用（解释器内部循环），不依赖 CIL `tail.`；尾位置的 `apply` 也在循环中展开 |
| 预链接 | 执行种子时先为每个顶层 `library-letrec*` 建帧、创建全部库级过程并写入位置，再按顺序执行其余初始化。旧 boot 编译器把库级过程静态链接，种子中因此有跨库前向引用（如 exceptions 初始化时调用 compat 的 `make-parameter`） |
| `compile-core` | 由 stage0 提供：`(compile-core e)` 返回执行 `e` 的无参过程，展开器的 `eval` 经它执行展开结果 |
| 命令行 | `stage0 [--time] [--deterministic] [-I 目录] <种子> <脚本.sps> 参数…`（种子执行后以 `(load/program 脚本)` 运行）；`stage0 --core <文件>…` 直接解释 Lcore |
| 逃逸续延、`$try/finally`、多值 | 与编译后代码同样的运行时机制（02 §6） |
| 规模目标 | 一两千行 C#；只追求正确，不追求速度（每次自举只跑一次）。实现约 1000 行；种子执行约 0.3 s，加载 nanopass 约 4.5 s（旧系统编译执行约 2.5 s） |
| 额外用途 | 以后可以作为 NativeAOT 环境下 `eval` 的后备（不在首批范围） |

stage0 不实现展开器：展开器本身就在种子里，以核心形式的形式被解释执行。

## 5. 种子的生成与再生成

1. **首次**：旧系统（`legacy-stage0/` 中的快照）运行 `seed-buildscript.sps`（由现有 `ironscheme-buildscript.sps` 改写：保留展开部分，最后一步把 `(map compile-core-expr core*)` 写成文本，而不是调用 `compile-bootfile`）。当时的命令（旧版 `tools/gen-seed.sh`）：旧系统会优先加载当前目录与脚本目录下的 `psyntax/*.sls` 源码，所以脚本复制到临时目录、在快照目录下运行，源码根目录作为参数。
   - 文本格式：核心形式与其中的常量都是标准 S 表达式，写出器自己实现（不用宿主 `write`），按新 reader 能逐值读回的写法输出 ASCII：符号中的非法字符用 `\xHH;`，字符串中的代理项对合成码点，flonum 检查往返，`-0.0` 单独处理。非调试模式下种子中没有注解、记录或语法对象。
2. 生成前，boot 源码已经改为面向新运行时（iron-013）。展开是纯数据处理，旧系统不执行这些代码。
3. **之后**（iron-032 实测）：新系统或 stage0 运行同一脚本重新生成种子，命令为 `dotnet run tools/build.cs -- seed`（默认用新宿主与 `boot/ironscheme.boot.dll`，约 16 秒；`--stage0` 由 stage0 执行现有种子来运行，约 40 秒，不需要 boot 镜像）。脚本在 `src/scheme` 目录下运行，源码根目录参数为 `./`，种子写回原处。与旧系统生成时相比，脚本只改了一处：`clr-call-internal`、`clr-cast-internal` 在 stage0 中是特殊形式，不作为原语取值（与 `ironscheme-buildscript-nano.sps` 相同）。
   - 种子不动点成立：新宿主与 stage0 生成的种子逐字节相同，两次生成结果相同；用重新生成的种子经 stage0 构建的 stage1 与原先的 stage1 逐字节相同。
   - 与旧系统生成的种子相比，gensym 计数的起点不同（新系统展开前已生成的 gensym 数不同），其余由 boot 源码的改动决定。boot 源码改动后可以随时再生成；不再生成也不影响构建——种子只用来在 stage0 上运行编译器，stage1 总是从当前源码编译。
   - **例外：展开器的四个文件用到新原语时必须再生成**（iron-050 实测）。构建脚本自己 `(import (boot expander compat) …)`，这四个库由运行中的种子系统从源码加载，它们 import 的 `(ironscheme unsafe)` 等是种子里的旧表，新名字会报 "cannot find identifier"。做法分两步：先让该文件临时用 `clr-static-call` 调同一个 C# 方法，构建并 `build.cs seed`；再换回原语写法，构建并再次 `seed`。其他 boot 文件没有这个限制（它们只在 bootstrap 库集合里展开，库表来自脚本的 `identifier->library-map`）。
4. 种子文件放在 `src/scheme/boot/boot-seed.core`。

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
| **gensym 名字含时间戳**（`g$name$N$TICKS`） | **自举构建采用规范改名**（iron-030）：构建过程用普通（带进程时间戳的）gensym，编译器写常量表时把本进程生成的 gensym 按首次出现顺序改名为 `g$名字$序号$%b`（`canonical-gensyms`）。确定性 gensym（`deterministic-gensym?`，库名作用域 + 计数，iron-014）用于单独编译库；它不适合自举构建——上一级镜像中固化的名字会与本次构建过程中生成的同名 gensym 冲突。文本种子写出时把 `$TICKS` 改为 `$%seed` |
| 符号的哈希值 | `Symbol.GetHashCode` 为名字的 FNV-1a 哈希：eq 哈希表按符号的遍历顺序（展开器合并 import 时用到）与对象分配顺序无关，产物不随宿主（stage0 解释器或编译后的系统）变化 |
| 哈希表遍历顺序 | 编译器与展开器中需要稳定顺序处一律按插入顺序或排序 |
| MVID、时间戳 | 发射器按内容哈希生成（04 §4） |

## 8. 种子管理

| 阶段 | 种子 |
|---|---|
| M2 之前 | 旧系统的可运行快照 `legacy-stage0/`（含原始 DLR 格式种子），只用于第 0 步生成文本种子。iron-032 确认新系统能自行再生成种子后已删除 |
| M2 完成后 | `boot-seed.core`（文本） |
| M6 完成后 | stage3 的 boot dll 作为二进制缓存放入工作区（`src/scheme/boot/ironscheme.boot.dll`，不提交）；从源码重建的路径是 `boot-seed.core` + stage0。实测 stage0 编译出的 stage1 与 stage2、stage3 逐字节相同（iron-030） |
| M7 删除旧系统后（iron-032） | 旧 DLR 系统不再需要。从零重建只要 .NET SDK、本仓库（含 nanopass 子模块）与文本种子：仓库根目录 `dotnet build`（C# 项目 + boot 镜像）。仓库不再跟踪旧格式的 `ironscheme.boot.dll`；新 boot 生成在 `boot/`（忽略；iron-047 前为 `build/`），宿主从 `src/scheme` 启动时自动复制到宿主目录 |

## 9. 新系统中的构建脚本（Phase B）

- 编译器在 boot 镜像内；发射器以库 API 形式同进程调用（`LcilEmitter.Emit`），也可继续用命令行。
- `compile-bootfile`、`compile-library` 等由编译驱动实现（03 §8），不再是 C# 内建函数。
- 测试 `BootstrapTests` 改为：种子 → stage0 → stage1 → stage2 → stage3，比较 Lcil 与 dll，再做 ILVerify。

# iron-030 Phase B：自举不动点

- 里程碑：M6　依赖：iron-028、iron-029　状态：完成
- 设计依据：[05 §2、§3、§6](../designs/05-bootstrap.md)

## 目标
新系统自己编译自己，达到不动点。

## 工作内容
1. 新系统上的构建脚本形态（编译器在镜像内、发射器同进程调用）。
2. stage1 → stage2 → stage3（另验证：stage0 编译出的 stage1 与 stage2 的 Lcil 是否一致，不一致时分析原因）；比较 stage2 与 stage3 的 Lcil 文本与 dll 字节。
3. 不一致时定位来源（gensym、遍历顺序、浮点格式等）并修复。
4. 改写 `BootstrapTests` 为新流程。
5. 用 stage3 替换工作区中的种子文件（不提交）。

## 验收标准
- stage2 与 stage3 的 Lcil 一致、dll 逐字节一致；ILVerify 通过。

## 从 M5（iron-028、029）转来

- stage1：`tools/build-stage1.sh`（确定性，两次构建逐字节相同），宿主 `IronScheme.Host`。在新系统上运行构建脚本：`IronScheme.Host --deterministic -I lib -I lib/nanopass-framework-scheme ironscheme-buildscript-nano.sps <输出目录>`——脚本目前假定运行在 stage0 上（从 `boot-seed.core` 取运行中系统的原语位置表）；在新系统上运行时要改为从 boot 镜像取（例如在新系统中直接用 `(psyntax internal)` 的位置表，或由宿主提供）。
- 注意 bootstrap 展开与运行中系统加载同名库时的 gensym 领域（`$gensym-realm`）。
- 新系统中 `import` 编译器或 nanopass 会从源码加载另一份（boot 中只有其运行时代码，没有宏）；构建脚本本身导入 `(ironscheme compiler)`，会在新系统中从源码展开并编译一遍（较慢）。

## 结论（2026-10-08）

完成。**stage1、stage2、stage3 的 Lcil 文本与 dll 全部逐字节相同**（SHA-256 前缀 `0880de20843b9935`），包括 stage0 编译出的 stage1；ILVerify 通过。

### 新系统上的构建

同一个 `ironscheme-buildscript-nano.sps` 既可在 stage0 上运行（Phase A），也可在新宿主上运行（Phase B）：
`IronScheme.Host --boot <上一级镜像> -I lib -I lib/nanopass-framework-scheme ironscheme-buildscript-nano.sps <输出目录>`，约 37 秒（stage0 上约 72 秒）。编译器在镜像内，发射器同进程调用。
- 运行中系统的原语位置表：psyntax main 把 `current-primitive-locations` 参数登记在同名符号上，脚本优先用它；stage0（种子中没有这一登记）时回退为从种子文本中查找。

### 不一致的来源与修正

| 现象 | 原因 | 修正 |
|---|---|---|
| stage1 上运行构建脚本，加载 nanopass 时编译器报"unbound variable make-clause" | simplify-letrec 计算前向变量时用的是标记前向变量之前的"可并组"状态；前向的 lambda 被排除出组后拆开了原先连续的 lambda 段，产生新的跨组前向引用。Phase A 中这段代码（nanopass 宏的 visit 代码）只在 stage0 里解释执行，没经过新编译器 | 前向变量反复计算直到不再变化；compile-small 增加对应用例 |
| 确定性模式下 stage2 构建中运行中系统的 label 绑定被覆盖（"not a record of type library"） | 上一级镜像中固化的图例 label（构建末尾在 `%top` 作用域生成）与本次构建过程中较早生成的临时 gensym 同名而所指不同 | 构建过程**不再用确定性 gensym**（名字带进程时间戳，与上一级镜像的名字不会冲突），改为编译时由 `canonical-gensyms` 把常量表中本进程生成的 gensym 按首次出现顺序规范改名为 `g$名字$序号$%b`（05 §7 的后备方案） |
| stage1 与 stage2 的 Lcil 有 2 字节差异（nanopass 嵌入代码的语法对象中，rib 的符号顺序不同） | psyntax 处理 import 时经 eq 哈希表合并导出名，遍历顺序取决于符号的哈希值；`Symbol` 原用对象身份哈希，随分配顺序变化，解释器（stage0）与编译代码（stage1）分配顺序不同 | `Symbol.GetHashCode` 改为名字的 FNV-1a 哈希（相等仍是引用相等），产物与运行它的宿主无关 |

其余：`compile-core` 失败时可经环境变量 `IRONSCHEME_DUMP_FAILED_CORE=文件` 以 fasl 写出输入，`IRONSCHEME_DUMP_PASSES=前缀` 写出各阶段中间语言（用于比较解释执行与编译后的编译器）；Core 在设置 `IRONSCHEME_TRACE_ERRORS` 时为 C# 侧断言违例打印 CLR 栈。`gensym` 领域（`$gensym-realm`）保留，`%top` 作用域也按领域区分，但构建脚本不再使用它。

### 测试

`IronScheme.Tests` 改为 net10.0，以进程方式驱动新宿主与 stage0（工作目录 `IronScheme.Console`，已加入 `IronSchemeNext.slnx`）。`Bootstrap` 类别（6 项，约 4 分钟）：stage0 → stage1 → stage2 → stage3，断言 stage2 / stage3 的 Lcil 与 dll 一致、stage1 与 stage2 的 dll 一致，ILVerify stage3，最后把 stage3 装为工作区的 boot 镜像 `IronScheme.Console/build/ironscheme.boot.dll`（不提交，已在 .gitignore 中）。

### 种子

`boot-seed.core` 仍是旧系统生成的文本种子，作为"从零重建"的起点；现在的工作区二进制缓存是 stage3（与 stage1 相同）。由于 stage0 编译出的 stage1 已与 stage2、stage3 逐字节相同，从种子重建与新系统自我重建得到同一产物。

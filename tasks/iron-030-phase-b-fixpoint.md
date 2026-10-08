# iron-030 Phase B：自举不动点

- 里程碑：M6　依赖：iron-028、iron-029　状态：未开始
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

# 任务索引

本文件只做索引。任务详情见 `tasks/` 目录，设计见 [designs/](designs/README.md)。
状态：未开始 / 进行中 / 完成 / 搁置。工作约定：本仓库只开发、不提交。

| ID | 标题 | 里程碑 | 依赖 | 状态 |
|----|------|--------|------|------|
| [iron-001](tasks/iron-001-build-legacy-baseline.md) | 构建旧系统并记录测试基线 | M0 | 无 | 完成 |
| [iron-002](tasks/iron-002-nanopass-submodule.md) | 以第三方依赖引入 nanopass-framework-scheme | M0 | 无 | 完成 |
| [iron-003](tasks/iron-003-spike-dotnet-capabilities.md) | 验证 .NET 10 的关键能力 | M0 | 无 | 完成 |
| [iron-004](tasks/iron-004-core-project-skeleton.md) | 建立 IronScheme.Core 项目骨架 | M1 | iron-003 | 完成 |
| [iron-005](tasks/iron-005-values-and-symbols.md) | 值表示与符号值槽 | M1 | iron-004 | 完成 |
| [iron-006](tasks/iron-006-procedure-model.md) | 过程模型与控制原语 | M1 | iron-005 | 完成 |
| [iron-007](tasks/iron-007-runtime-hooks.md) | 运行时钩子取代 Glue.il | M1 | iron-006 | 完成 |
| [iron-008](tasks/iron-008-port-runtime-library.md) | 迁移运行时库 | M1 | iron-005、iron-006、iron-007 | 完成 |
| [iron-009](tasks/iron-009-records.md) | 记录的统一表示 | M1 | iron-005 | 完成 |
| [iron-010](tasks/iron-010-reader.md) | 手写 reader | M1 | iron-005、iron-007 | 完成 |
| [iron-011](tasks/iron-011-interop-runtime.md) | CLR 互操作运行时 | M1 | iron-006 | 完成 |
| [iron-012](tasks/iron-012-primgen.md) | 原语表生成工具 PrimGen | M1 | iron-008（以及 iron-009 ~ iron-011 完成后再生成完整版） | 完成 |
| [iron-013](tasks/iron-013-adapt-scheme-sources.md) | Scheme 源码适配新运行时 | M2 | iron-008、iron-009、iron-010、iron-011、iron-007 | 完成 |
| [iron-014](tasks/iron-014-deterministic-gensym.md) | 构建模式下的确定性 gensym | M2 | iron-001 | 完成 |
| [iron-015](tasks/iron-015-generate-text-seed.md) | 生成文本种子 boot-seed.core | M2 | iron-001、iron-013、iron-014 | 完成 |
| [iron-016](tasks/iron-016-stage0-interpreter.md) | stage0：C# 核心形式解释器 | M2 | iron-008、iron-009、iron-010、iron-011 | 完成 |
| [iron-017](tasks/iron-017-run-psyntax-and-nanopass-on-stage0.md) | 在 stage0 上跑通 psyntax 与 nanopass | M2 | iron-015、iron-016、iron-002 | 完成 |
| [iron-018](tasks/iron-018-lcil-spec-and-reader.md) | Lcil 规格与文本读取器 | M3 | iron-003 | 完成 |
| [iron-019](tasks/iron-019-emitter-core.md) | 发射器：类型、方法、指令与异常块 | M3 | iron-018 | 完成 |
| [iron-020](tasks/iron-020-constants-fasl.md) | 常量编码与 fasl | M3 | iron-018、iron-005、iron-009 | 完成 |
| [iron-021](tasks/iron-021-module-loader.md) | 程序集入口约定与加载器 | M3 | iron-019、iron-020、iron-004 | 完成 |
| [iron-022](tasks/iron-022-nanopass-and-parse-core.md) | 引入 nanopass 与 parse-core | M4 | iron-017、iron-012 | 完成 |
| [iron-023](tasks/iron-023-frontend-passes.md) | 前中端 pass | M4 | iron-022 | 完成 |
| [iron-024](tasks/iron-024-closures-and-loops.md) | 闭包转换、类提升与循环降级 | M4 | iron-023 | 完成 |
| [iron-025](tasks/iron-025-lower-calls-prims-interop.md) | 调用、原语与互操作降级 | M4 | iron-024、iron-012 | 完成 |
| [iron-026](tasks/iron-026-normalize-and-linearize.md) | 上下文规范化、try 提升与线性化 | M4 | iron-025 | 完成 |
| [iron-027](tasks/iron-027-compiler-driver.md) | 编译驱动 | M4 | iron-026、iron-021 | 完成 |
| [iron-028](tasks/iron-028-phase-a-stage0-build.md) | Phase A：stage0 编译出新 boot 镜像 | M5 | iron-027、iron-021、iron-017 | 完成 |
| [iron-029](tasks/iron-029-host-and-repl.md) | 新宿主 IronScheme.Host 与 REPL | M5 | iron-021、iron-010、iron-008 | 完成 |
| [iron-030](tasks/iron-030-phase-b-fixpoint.md) | Phase B：自举不动点 | M6 | iron-028、iron-029 | 完成 |
| [iron-031](tasks/iron-031-r6rs-and-system-libraries.md) | R6RS 测试与系统库编译达标 | M6 | iron-030 | 完成 |
| [iron-032](tasks/iron-032-remove-legacy.md) | 删除 DLR、旧编译器与旧目标框架 | M7 | iron-031 | 完成 |
| [iron-033](tasks/iron-033-performance.md) | 性能优化（后续） | M7 | iron-031 | 完成 |
| [iron-034](tasks/iron-034-compiler-optimizations.md) | 编译器深度优化（034a 基准 → 034b 循环降级 → 034c 拆箱 → 034d 共享类 → 034e 跨库直接调用） | 后续 | iron-033、iron-057 | 未开始，设计已定 |
| [iron-035](tasks/iron-035-repository-layout.md) | 目录结构调整 | M8 | iron-032 | 完成 |
| [iron-036](tasks/iron-036-self-contained-publish.md) | 自包含发布 | M8 | iron-037 | 完成 |
| [iron-037](tasks/iron-037-compile-file.md) | compile-file 与 .fasl | M8 | iron-035 | 完成 |
| [iron-038](tasks/iron-038-repl-line-editing.md) | REPL：行编辑、补全与提示 | M8 | iron-035 | 完成 |
| [iron-039](tasks/iron-039-hosting-and-examples.md) | 嵌入 API 与 Web 服务器示例 | M8 | iron-035 | 完成 |
| [iron-040](tasks/iron-040-vendor-srfi-pfds.md) | srfi 与 pfds 纳入仓库 | M8 | iron-035 | 完成 |
| [iron-041](tasks/iron-041-std-foundation.md) | std 基础：目录、约定与语法类库 | M9 | iron-040 | 完成 |
| [iron-042](tasks/iron-042-std-lists-strings.md) | std：表、字符串与字符 | M9 | iron-041 | 完成 |
| [iron-043](tasks/iron-043-std-collections-arithmetic.md) | std：向量、散列表、比较、排序与算术 | M9 | iron-041 | 完成 |
| [iron-044](tasks/iron-044-std-misc.md) | std：惰性序列、记录、时间、测试等 | M9 | iron-041 | 完成 |
| [iron-045](tasks/iron-045-std-persistent.md) | std：持久数据结构 | M9 | iron-041 | 完成 |
| [iron-046](tasks/iron-046-remove-srfi-pfds.md) | 删除 srfi 与 pfds，迁移依赖方 | M9 | iron-042 ~ iron-045 | 完成 |
| [iron-047](tasks/iron-047-scheme-tree-layout.md) | Scheme 源码树整理 | M8 | iron-035 | 完成 |
| [iron-054](tasks/iron-054-base-library-fixes.md) | 基础库问题修复 | M9 | iron-041 ~ iron-046 | 完成 |
| [iron-055](tasks/iron-055-scheme-strings.md) | 字符串表示：按码点的窄/宽字符串 | M9 | iron-054 | 完成 |
| [iron-058](tasks/iron-058-csharp-style.md) | C# 代码按 09 规范落地（4 空格、字段命名等） | M9 | — | 完成 |
| [iron-059](tasks/iron-059-system-numerics-bignum.md) | 大整数改用 `System.Numerics.BigInteger`，删除 Oyster.IntX；进制转换与位运算改由宿主完成 | M9 | — | 完成 |
| [iron-048](tasks/iron-048-spike-runtime-async.md) | 验证 Runtime Async 能否做 async-lambda 的后端 | 后续 | iron-003 | 完成 |
| [iron-049](tasks/iron-049-spike-async-frame.md) | 验证 AsyncFrame 状态机能否做 async-lambda 的后端 | 后续 | iron-048 | 完成 |
| [iron-050](tasks/iron-050-async-runtime.md) | 异步：运行时支持 | 后续 | iron-049 | 完成 |
| [iron-051](tasks/iron-051-async-frontend.md) | 异步：展开器、parse-core 与 lower-async | 后续 | iron-050 | 完成 |
| [iron-052](tasks/iron-052-async-codegen.md) | 异步：codegen 生成状态机 | 后续 | iron-051 | 完成 |
| [iron-053](tasks/iron-053-async-library-and-tests.md) | 异步：库、测试与文档 | 后续 | iron-052 | 完成 |
| [iron-056](tasks/iron-056-boot-std-without-clr.md) | boot 与 std 去 `clr-*` | 后续 | 无 | 完成 |
| [iron-057](tasks/iron-057-host-neutral-interop-nodes.md) | 互操作节点改 `host-*`，codegen 加 `target` 参数 | 后续 | iron-056 | 完成 |

## 里程碑

| 里程碑 | 任务 |
|--------|------|
| M0 准备与验证 | iron-001 ~ iron-003 |
| M1 新运行时 | iron-004 ~ iron-012 |
| M2 stage0 | iron-013 ~ iron-017 |
| M3 Lcil 与发射器 | iron-018 ~ iron-021 |
| M4 编译器 | iron-022 ~ iron-027 |
| M5 首次自举 | iron-028 ~ iron-029 |
| M6 自举闭合 | iron-030 ~ iron-031 |
| M7 清理与优化 | iron-032 ~ iron-033 |
| M8 工程与示例 | iron-035 ~ iron-040、iron-047 |
| M9 标准库 | iron-041 ~ iron-046、iron-054、iron-055、iron-058、iron-059 |
| 后续 | iron-034、iron-048 ~ iron-053、iron-056 ~ iron-057 |

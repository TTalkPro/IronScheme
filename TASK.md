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
| [iron-028](tasks/iron-028-phase-a-stage0-build.md) | Phase A：stage0 编译出新 boot 镜像 | M5 | iron-027、iron-021、iron-017 | 未开始 |
| [iron-029](tasks/iron-029-host-and-repl.md) | 新宿主 IronScheme.Host 与 REPL | M5 | iron-021、iron-010、iron-008 | 未开始 |
| [iron-030](tasks/iron-030-phase-b-fixpoint.md) | Phase B：自举不动点 | M6 | iron-028、iron-029 | 未开始 |
| [iron-031](tasks/iron-031-r6rs-and-system-libraries.md) | R6RS 测试与系统库编译达标 | M6 | iron-030 | 未开始 |
| [iron-032](tasks/iron-032-remove-legacy.md) | 删除 DLR、旧编译器与旧目标框架 | M7 | iron-031 | 未开始 |
| [iron-033](tasks/iron-033-performance.md) | 性能优化（后续） | M7 | iron-031 | 未开始 |

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

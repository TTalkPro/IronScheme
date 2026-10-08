# 设计文档索引

IronScheme 派生改造：去掉 DLR，用 nanopass 编译器把 Scheme 直接编译到 CIL，只依靠 .NET 自身完成自举，服务 R6RS 但不支持完整 call/cc。

| 文档 | 内容 |
|------|------|
| [00-overview.md](00-overview.md) | 目标、约束、总体架构、关键决策、里程碑、风险 |
| [01-current-state.md](01-current-state.md) | 现状分析：构建与自举、编译管线、DLR 依赖面、Scheme 侧依赖 |
| [02-runtime.md](02-runtime.md) | 新运行时 `IronScheme.Core`：值表示、过程模型、全局与库绑定、异常与逃逸续延、记录、reader、宿主 |
| [03-compiler.md](03-compiler.md) | nanopass 编译器：输入语言 Lcore、pass 链、原语表、尾调用、互操作 |
| [04-lcil-and-emitter.md](04-lcil-and-emitter.md) | 中间语言 Lcil 的文本格式、常量编码、C# 发射器、程序集结构与加载 |
| [05-bootstrap.md](05-bootstrap.md) | 自举：以旧 IronScheme 为 stage0 交叉编译，自举不动点，种子管理 |
| [06-r6rs-and-testing.md](06-r6rs-and-testing.md) | R6RS 符合性与偏离项（call/cc），测试策略与验收基线 |

任务索引见仓库根目录 [TASK.md](../TASK.md)。

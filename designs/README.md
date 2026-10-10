# 设计文档索引

IronScheme 派生改造：去掉 DLR，用 nanopass 编译器把 Scheme 直接编译到 CIL，只依靠 .NET 自身完成自举，服务 R6RS 但不支持完整 call/cc。

| 文档 | 内容 |
|------|------|
| [00-overview.md](00-overview.md) | 目标、约束、总体架构、关键决策、里程碑、风险 |
| [01-current-state.md](01-current-state.md) | 现状分析：构建与自举、编译管线、DLR 依赖面、Scheme 侧依赖 |
| [02-runtime.md](02-runtime.md) | 新运行时 `IronScheme.Core`：值表示、过程模型、全局与库绑定、异常与逃逸续延、记录、reader、宿主 |
| [03-compiler.md](03-compiler.md) | nanopass 编译器：输入语言 Lcore、pass 链、原语表、尾调用、互操作 |
| [04-lcil-and-emitter.md](04-lcil-and-emitter.md) | 中间语言 Lcil 的文本格式、常量编码、C# 发射器、程序集结构与加载 |
| [05-bootstrap.md](05-bootstrap.md) | 自举：文本种子 + C# 解释器 stage0，自举不动点，种子管理 |
| [06-r6rs-and-testing.md](06-r6rs-and-testing.md) | R6RS 符合性与偏离项（call/cc），测试策略与验收基线 |
| [07-tooling-and-embedding.md](07-tooling-and-embedding.md) | M8：目录结构、compile-file 与 .fasl、自包含发布、REPL 行编辑、嵌入 API 与示例 |
| [08-std-library.md](08-std-library.md) | M9：把 SRFI 与 pfds 改写为按用途命名的 `(ironscheme std …)`，逐个 SRFI 的裁决与迁移 |
| [09-csharp-style.md](09-csharp-style.md) | C# 代码规范：以微软规范为主的 `.editorconfig`（已落地，iron-058） |
| [10-async.md](10-async.md) | 异步：`async-lambda` / `await` 的语言表面、`AsyncFrame` 状态机后端、`lower-async` pass、参数对象改 `AsyncLocal`、偏离与任务拆分 |
| [11-portability.md](11-portability.md) | 可移植性：`(ironscheme clr)` 名字不改、互操作三层（宿主绑定 / 可移植包装 / 核心只用原语）、把托管运行时当作目标机器、JVM 靠交叉编译自举 |
| [12-strings.md](12-strings.md) | 字符串表示：按码点的窄/宽字符串（iron-055） |
| [13-clr-exceptions.md](13-clr-exceptions.md) | guard 与宿主异常（.NET/JVM）的互通：为何不能统一为 try/catch、分层澄清、源头转换方案（提案） |

任务索引见仓库根目录 [TASK.md](../TASK.md)。

# iron-039 嵌入 API 与 Web 服务器示例

- 里程碑：M8　依赖：iron-035　状态：完成
- 设计依据：[07 §5](../designs/07-tooling-and-embedding.md)

## 目标
C# 程序可以方便地调用 IronScheme 代码；用一个 Web 服务器示例展示 C# 调用 Scheme、Scheme 使用 .NET 的 SQLite 库。

## 工作内容
1. `src/IronScheme.Hosting`：初始化、求值、取得库导出的过程并调用；宿主改用它。
2. `examples/WebServer`：ASP.NET Core 最小 API，路由调用 Scheme 库中的过程；Scheme 通过 `Microsoft.Data.Sqlite` 建库、插入、查询。
3. 测试：Hosting 单元测试；示例服务启动后请求各接口检查结果（类别 Examples）。

## 验收标准
- `dotnet run --project examples/WebServer` 启动后，接口返回由 Scheme 从 SQLite 查询得到的数据。

## 结论（2026-10-09）

完成，见 07 §5。

**嵌入 API（`src/IronScheme.Hosting`）**

`SchemeRuntime` 提供：
- `Initialize(选项)`：库路径、boot 镜像、命令行；
- `Eval(代码)`：在交互环境中求值；`Eval(表达式, 导入…)`：在指定导入的环境中求值；
- `Import`、`GetProcedure`、`GetFunction<T>`（强类型委托）、`Call`、`ToSchemeString`。

Scheme 条件转为 `SchemeError`（消息为 Scheme 打印器的输出），委托调用也会转换。宿主改用它初始化。boot 镜像的生成目标移到 Hosting 项目，在复制输出前执行；镜像与 `lib/ironscheme` 随项目引用复制到应用输出目录，应用目录下的 `lib/` 总在库搜索路径中。

**示例 `examples/WebServer`**
- ASP.NET Core 最小 API（SDK 自带的共享框架），路由 `/api/books`（含搜索）、`/api/books/{id}`、`POST /api/books`、`/api/stats` 与首页；
- 业务逻辑在 Scheme 库 `(bookstore)` 中，经 CLR 互操作使用 `Microsoft.Data.Sqlite`（NuGet 10.0.12）：建表、写入示例数据、参数化查询，结果以关联表返回；统计（按年代分组）在 Scheme 中完成；
- C# 把关联表转成 JSON；Scheme 的断言违例（如标题为空）作为 400 返回；
- 对 Scheme 的调用用锁串行（交互环境与展开器不是线程安全的）。

**实现示例时修正的运行时问题**
- **CLR 数值转换**：互操作对 long、short、byte、uint、ulong、float 等返回值原先不转换，Scheme 拿到的是装箱的 CLR 值，`number?`、`zero?` 不认。现在转为 Scheme 数；声明为 `object` 的返回值与字段值按运行时类型同样转换（例如 `ExecuteScalar` 返回的 Int64）。`clr-cast` 的结果保留指定的 CLR 类型，不做转换。
- **`clr-reference` 的探测**：简单名字在默认探测失败后，再查当前目录、库搜索路径与应用目录中的 `名字.dll`。
- `Builtins.ApplicationDirectory` 在程序集没有文件位置时（单文件发布）改用 `AppContext.BaseDirectory`。

**测试**
- 类别 Hosting 5 项，进程内运行：求值、导入、库过程与强类型委托、条件转换、CLR 数值转换；
- 类别 Examples 4 项：启动示例服务（随机端口、临时数据库），检查示例数据与统计、搜索、新增与查询、错误返回 400。
- 全部测试通过：Core.Tests 229/229，IronScheme.Tests 55/55。

示例首次构建需要从 NuGet 还原 Microsoft.Data.Sqlite（及其依赖 SQLitePCLRaw）。这是示例要展示的第三方库，运行时与构建系统本身仍只依赖 .NET SDK。

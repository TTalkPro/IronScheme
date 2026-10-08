# iron-004 建立 IronScheme.Core 项目骨架

- 里程碑：M1　依赖：iron-003　状态：完成
- 设计依据：[02 §1](../designs/02-runtime.md)

## 目标
建立新运行时、发射器、宿主、测试四个 net10.0 项目，与旧项目并存。

## 工作内容
1. 新建 `IronScheme/IronScheme.Core`（类库）、`IronScheme/IronScheme.Emit`（类库 + 命令行入口）、`IronScheme/IronScheme.Host`（控制台）、`IronScheme/IronScheme.Core.Tests`（单元测试）。
2. 将 `Oyster.IntX` 改为多目标或复制为 net10.0 版本供 Core 引用。
3. 新建独立解决方案 `IronScheme/IronSchemeNext.sln`，不依赖 BuildTools 子模块与 `Directory.Build.props` 中的导入（必要时在新项目目录放置自己的 `Directory.Build.props` 截断继承）。
4. 根命名空间 `IronScheme.Core`，确保与旧程序集同进程加载不冲突。

## 验收标准
- `dotnet build IronSchemeNext.sln` 只需 .NET SDK 即可成功。
- 空测试项目可运行。

## 结论（2026-10-08）

| 项 | 结果 |
|---|---|
| 解决方案 | `IronScheme/IronSchemeNext.slnx`（SDK 10 默认的 slnx 格式），包含下列 5 个项目 |
| `IronScheme.Core` | 类库，net10.0，根命名空间 `IronScheme.Core`；目前只有 `CoreInfo` 占位 |
| `IronScheme.Emit` | 可执行程序（同时可作为库引用），net10.0；**不引用** Core，运行时类型按名字解析（04 §4）；`Main` 为占位 |
| `IronScheme.Host` | 控制台，net10.0，引用 Core 与 Emit；`Main` 为占位 |
| `IronScheme.Core.Tests` | NUnit 4 测试，net10.0；冒烟测试 2 项（Core 可加载、不引用旧程序集 `IronScheme`/`IronScheme.Closures`/`IronScheme.Scripting`） |
| `Oyster.IntX` | 由 `net20` 改为 `net20;net10.0` 多目标；Core 以 `SetTargetFramework=net10.0` 引用 |
| `Directory.Build.props` 截断 | 不需要：BuildTools 导入已在删除子模块时去掉 |

验证：`dotnet build IronSchemeNext.slnx -c Release` 0 错误 0 警告；`dotnet test` 2/2 通过；只需 .NET SDK。

stage0 项目（`IronScheme.Stage0`）与原语表生成工具（`IronScheme.PrimGen`）分别在 iron-016、iron-012 中建立。

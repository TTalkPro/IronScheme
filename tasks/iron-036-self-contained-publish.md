# iron-036 自包含发布

- 里程碑：M8　依赖：iron-037　状态：完成
- 设计依据：[07 §3](../designs/07-tooling-and-embedding.md)

## 目标
不需要安装 .NET 即可运行：自包含单文件的 IronScheme 宿主，以及把一个程序做成独立可执行文件。

## 工作内容
1. 宿主支持从嵌入资源加载 boot 镜像与 `.fasl`。
2. `tools/build.cs publish [-r RID] [-o 目录]`：发布宿主；`publish app.sps`：编译程序及其引用的库，嵌入后发布。
3. 测试：发布当前平台的宿主与示例程序，运行冒烟脚本。

## 验收标准
- 发布产物在没有 `dotnet` 的环境变量（不经 `dotnet` 启动）下直接运行：REPL、脚本、独立程序。

## 结论（2026-10-09）

完成，见 07 §3。

命令：`dotnet run tools/build.cs -- publish [app.sps] [-r RID] [-o 目录] [-n 名字] [-I 库目录]…`，自包含、单文件发布。

**发布宿主**
- 得到 `IronScheme.Host`（约 76 MB），boot 镜像嵌入其中，`lib/` 作为目录放在旁边；
- 在没有 dotnet 的环境（`env -i PATH=/usr/bin:/bin`）中实测：脚本、REPL、导入 `lib/` 中的库、`compile-library` 都正常。

**发布应用**
- 新增 Scheme 过程 `compile-whole-program`：把程序与它用到的每个库编译为 `.fasl` 并生成清单；
- 发布时这些文件嵌入可执行文件，宿主进入应用模式，经钩子 `load-fasl-content` 安装库、运行程序；
- 结果只有一个文件。示例 `examples/WordCount/wordcount.sps` 用到了 `(srfi :1 lists)`。

**其他修改**
- `SchemeRuntime` 在可执行文件旁没有镜像时，从入口程序集的嵌入资源加载；
- `Builtins.ApplicationDirectory` 在单文件中改用 `AppContext.BaseDirectory`；
- `load-fasl-file` 拆出 `load-fasl-content`；
- `tools/build.cs` 在输出被重定向时给 `dotnet build`/`publish` 加 `-nodeReuse:false`。原因是常驻的 MSBuild 节点会继承输出管道，测试因此一直等不到输出结束，这次实际遇到过。

**测试**
- 类别 Publish 2 项：发布宿主，运行脚本与 REPL；发布 WordCount 应用，确认输出目录只有一个文件，检查运行结果和失败时的退出码。
- 首次运行时 SelfContainedHost 有一次退出码为 1，之后单独运行与整类运行均通过，未能复现原因。
- 补记：之后 StandaloneApplication 也偶发失败，查明原因。发布应用时，`tools/build.cs` 在命令行上以全局属性传入 `IntermediateOutputPath`/`OutputPath`，被引用的可执行项目（Emit、stage0）于是在两组全局属性下各构建一次，并发写同一个 `obj/app-<名字>/apphost`。改为在 `IronScheme.Host.csproj` 中按 `IronSchemeAppName` 设置这两个路径，`build.cs` 不再传入；之后 Publish 类别连续两轮 2/2 通过。
- 再补记（iron-047 期间）：StandaloneApplication 又一次失败，并发写 `IronScheme.Emit/bin/Release/net10.0/linux-x64/IronScheme.Emit.runtimeconfig.json`。用 binlog 核对 Emit 的构建配置：宿主经传递引用构建 Emit 时传入 `RuntimeIdentifier`/`SelfContained`，IronScheme.Hosting（与平台无关的库）构建它时不传，同一次发布出现两种配置；全局属性 `PublishSingleFile=true` 又使无 RID 的那份推断出当前 RID，两者输出到同一目录。Emit 声明 `IsRidAgnostic=true` 后只剩一种配置。
- 全部测试通过：Core.Tests 229/229，IronScheme.Tests 57/57。种子已按当前源码再生成，达到不动点。

**限制**
- 只在 linux-x64 上实测；其他 RID 需要相应的运行时包（首次从 NuGet 获取）。
- 不裁剪（trimming）。

# iron-003 验证 .NET 10 的关键能力

- 里程碑：M0　依赖：无　状态：完成
- 设计依据：[03 §5](../designs/03-compiler.md)、[04 §4](../designs/04-lcil-and-emitter.md)

## 目标
在写运行时和发射器之前，用一个独立的 C# 实验程序确认设计依赖的 .NET 能力。

## 工作内容
1. **`tail.` 前缀**：用 Reflection.Emit 生成 `Procedure` 风格的类，测试
   - 经 `callvirt` 的相互尾递归一百万层；
   - 参数个数不同（Invoke1 → Invoke3）的尾调用；
   - 尾调用静态方法；
   在 Debug 与 Release、x64 上是否都不溢出。
2. **PersistedAssemblyBuilder**：生成带类型、静态字段、托管资源、try/finally 的程序集并保存；另一进程 `Assembly.LoadFrom` 后运行。
3. **内存程序集**：`AssemblyBuilder.DefineDynamicAssembly(RunAndCollect)` 生成并调用，引用持久化程序集中的类型。
4. **确定性**：同一输入两次保存的 dll 是否逐字节相同；MVID 能否指定，不能的话保存后改写的方案。
5. **Portable PDB**：PersistedAssemblyBuilder 生成序列点的方式（可选）。

## 验收标准
- 每项给出"可行 / 不可行 / 有条件"的结论和最小复现代码，记录在本任务文件末尾。
- 若 `tail.` 有不可靠的情况，在 `designs/03-compiler.md` §5 补充退路（蹦床）。

## 结论（2026-10-08，.NET 10.0.x，Linux x64）

验证程序：`spikes/iron-003/`（`dotnet run -c Release -- <tail|notail|save|load|dynamic|determinism>`）。所有递归测试深度一千万层，在 1MB 栈的线程上运行。

| 项 | 结论 | 说明 |
|---|---|---|
| `tail.` 经虚调用的相互尾递归 | **可行** | `Invoke1 ↔ Invoke1`，一千万层通过 |
| `tail.` 参数个数变化 | **可行** | `Invoke1 → Invoke3 → Invoke1` 通过 |
| `tail.` 调用静态方法 | **可行** | 1 参 → 2 参通过 |
| `tail.` 被调方需要栈传参 | **可行，较慢** | 1 参 → 8 参（超出 SysV 寄存器传参）通过；走运行时尾调用辅助路径，一千万次约 300 ms，寄存器传参约 35 ms |
| 关闭 JIT 优化时 | **仍然可行** | `DOTNET_JITMinOpts=1`、`DOTNET_JitDebuggable=1`、`DOTNET_TieredCompilation=0` 下全部通过 |
| 对照：不加 `tail.` | 关优化时**栈溢出**（约一万层） | 开优化时 JIT 会自行把"调用后紧跟 ret"做成尾调用，所以对照必须在 `DOTNET_JITMinOpts=1`（注意 Linux 上变量名区分大小写）下做 |
| try/finally 区域 | **可行** | 区域内调用、结果存局部变量、`leave` 后返回；finally 执行一次 |
| PersistedAssemblyBuilder 保存 | **可行** | `Save()` 与 `GenerateMetadata` + `ManagedPEBuilder` 两条路都可以；后者可加托管资源与 Portable PDB |
| 另一进程加载已保存程序集 | **可行** | `Assembly.LoadFrom` 后全部测试通过（关优化下） |
| 内存程序集引用已保存程序集 | **可行** | `RunAndCollect` 程序集中的方法带 `tail.` 调用已保存程序集里的类型 |
| Portable PDB | **可行** | `DefineDocument` + `MarkSequencePoint`，`GenerateMetadata` 给出 PDB 元数据，`PortablePdbBuilder` 序列化 |
| 确定性 | **需要后处理** | 两条保存路径两次输出都不同：差异只在 COFF 时间戳（偏移 0x88）和 **MVID**（随机 GUID）。`deterministicIdProvider` 无济于事，因为它的输入包含随机 MVID。**解决办法**：保存后把 MVID 与时间戳清零，算 SHA256，用哈希回填；处理后两次输出逐字节相同，且仍可正常加载 |

### 对设计的影响

1. 尾调用方案（03 §5）成立，不需要蹦床退路；栈传参情形较慢，固定参数上限取 4（02 §4）合适，参数多的调用本来就走 `InvokeN(object[])`。
2. 发射器的确定性（04 §4）采用"保存后回填 MVID 与时间戳"。若同时生成 PDB，PDB ID 也来自含随机 MVID 的内容，需要一并处理（或自举构建时不生成 PDB）。
3. fasl 常量以托管资源嵌入的方式可行（`AddManifestResource` + `managedResources`）。

# iron-008 迁移运行时库

- 里程碑：M1　依赖：iron-005、iron-006、iron-007　状态：未开始
- 设计依据：[02 §5、§10](../designs/02-runtime.md)

## 目标
把旧运行时中 R6RS 所需的 C# 部分复制改写到 IronScheme.Core，去掉 DLR 依赖。

## 工作内容
1. 数值：`Numbers`、`BigFraction`、`ComplexFraction`、`Complex64`（从 DLR 移入）。
2. 列表、向量、字节向量、字符串与 Unicode、哈希表（含 `HashtableEx` 等）、相等性、条件、I/O 与端口（`R6RS/IO.cs` 等）、环境相关原语。
3. `[Builtin]` → `[Primitive]`，补充 `Pure`、`AllowTailCall`、`Inline` 元数据；`[InlineEmitter]` 只保留非内联后备方法。
4. `PrimitiveRegistry`：启动时登记全部原语到符号值槽（不在运行时生成 IL）。
5. 删去 BinaryFormatter 序列化与调试钩子相关代码（另有任务）。

## 验收标准
- Core 中不出现 `Microsoft.Scripting` 与 `IronScheme.Runtime` 命名空间的引用。
- 原语数量与旧系统 `[Builtin]` 对照表一致（差异逐项说明）。
- 数值、字符串、哈希表、端口的单元测试通过。

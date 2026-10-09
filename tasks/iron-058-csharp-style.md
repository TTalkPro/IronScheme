# iron-058 C# 代码按 09 规范落地

- 里程碑：M9　依赖：—　状态：完成
- 设计依据：[09](../designs/09-csharp-style.md)

## 目标
按 09 的建议（以微软规范为主）统一 C# 代码：用户决定采纳，缩进改为 4 空格，私有字段改名。

## 工作内容（09 §4 的五步）
1. 换上 09 §2 的 `.editorconfig`。
2. 空白与文件格式：4 空格、LF、去 BOM、末尾换行。
3. 文件范围命名空间（IDE0161）、显式访问修饰符（IDE0040）、`String` → `string`（IDE0049）、常量 PascalCase。
4. 私有/内部字段 `_camelCase`、静态字段 `s_camelCase`，去掉随之多余的 `this.`。
5. 构建时检查代码样式（`EnforceCodeStyleInBuild`），CI 加 `dotnet format --verify-no-changes`。

## 验收标准
- `dotnet format --verify-no-changes --severity warning` 无报告；全部测试通过；种子不变、达到不动点。

## 结论（2026-10-09）

完成。共改动 97 个 C# 文件（`src/`、`tests/`、`examples/WebServer`、`tools/build.cs`）。第三方的 `src/Oyster.IntX` 标为 `generated_code`，未改动；`spikes/` 是试验代码，其中 iron-048/049 属于另一个会话，未纳入。

| 步 | 结果 |
|---|---|
| ① | 根目录 `.editorconfig` 换为 09 §2 的配置（`root = true`；C# 4 空格，Scheme 源码、Lcil、种子与项目文件保持 2 空格） |
| ② | `dotnet format whitespace`：4 空格、LF、去掉 3 个文件的 BOM、补末尾换行。多行字符串字面量中的缩进保持原样 |
| ③ | `dotnet format style --diagnostics IDE0161 IDE0040 IDE0049`：92 个文件改为文件范围命名空间；`Runtime/Strings.cs` 有两个命名空间块，手工合并为一个；补全显式访问修饰符；`String` → `string` |
| ④ | 字段命名：`dotnet format` 的命名修复不支持整个解决方案的批量修复，改用基于 Roslyn `Renamer` 的临时工具（按语义改名，引用一并更新），342 个字段：私有/内部实例字段 → `_camelCase`，静态字段 → `s_camelCase`，snake_case 与全大写的名字一并转为 camelCase（如 `get_pos` → `_getPos`、`MANTISSA` → `s_mantissa`）；3 个局部常量手工改为 PascalCase；随后用 IDE0003 去掉改名后多余的 114 处 `this.`（剩下 18 处为公开字段与同名参数等必要情形） |
| ⑤ | `Directory.Build.props` 打开 `EnforceCodeStyleInBuild`；CI（`.github/workflows/build.yml`）在 ubuntu 上加 `dotnet format IronScheme.slnx --verify-no-changes --severity warning` |

**改名前的安全核对**：Scheme 源码经 `clr-field-get/set!` 访问的字段、编译器生成代码 `ldfld`/`ldsfld` 引用的字段都是公开字段（09 §0 列为例外，不改名）；`Interop` 的成员解析只查公开成员。Emit 解析 Lcil 成员引用时虽带 `NonPublic`，但被引用的都是公开成员。

**验证**：`dotnet format --verify-no-changes --severity warning` 无报告；全量重建（`--no-incremental`，含 boot 镜像）无样式警告；种子与改动前逐字节相同，`seed --stage0` 也相同；完整测试 Core.Tests 229/229、IronScheme.Tests 81/81。

**提交时的建议**：这次改动几乎覆盖全部 C# 行。提交后可把该提交的哈希写进 `.git-blame-ignore-revs`，并执行 `git config blame.ignoreRevsFile .git-blame-ignore-revs`，这样 `git blame` 会跳过这次机械改动。

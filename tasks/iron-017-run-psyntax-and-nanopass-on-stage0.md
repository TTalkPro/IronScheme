# iron-017 在 stage0 上跑通 psyntax 与 nanopass

- 里程碑：M2　依赖：iron-015、iron-016、iron-002　状态：完成
- 设计依据：[05 §3](../designs/05-bootstrap.md)、[00 §6 风险](../designs/00-overview.md)

## 目标
stage0 解释执行文本种子，得到可用的 R6RS 环境，并在其上加载运行 nanopass。

## 工作内容
1. stage0 执行 `boot-seed.core`：登记钩子、安装 `(rnrs …)` 与 psyntax 库。
2. 跑 R6RS 冒烟测试（`(import (rnrs))` 下的常用操作、`syntax-case` 宏、`eval`）。
3. 把 nanopass 子模块目录加入库搜索路径，`(import (nanopass))`，跑通研究笔记 `nanopass.md` §8 的 `remove-when` 与 `to-cil` 示例。
4. nanopass 需要而运行时或 stage0 缺失的功能（iron-002 的清单），逐项补齐；适配文件的修改放在子模块之外。
5. 记录耗时：种子执行时间、nanopass 加载时间。

## 验收标准
- 两个 nanopass 示例在 stage0 上的输出与 Chez 上一致。
- 补齐与修改的清单记录在本任务文件末尾。

## 从 iron-016 转来

- 运行方式：`cd IronScheme/IronScheme.Console && dotnet ../IronScheme.Stage0/bin/Release/net10.0/stage0.dll --time boot-seed.core <脚本.sps>`。种子执行约 0.3 秒，简单 R6RS 程序已能运行。
- 已知问题：程序出错时 `with-guard` 打印条件的过程中又出错（打印 `#\nul` 等字符时），输出重复。需要查打印器。
- 库搜索路径来自 `get-library-paths`（`.`、`<应用目录>/lib`、应用目录）；stage0 的应用目录是 `IronScheme.Stage0/bin/...`，加载 `lib/` 下的库需要把 `IronScheme.Console/lib` 加入路径（`Builtins.AddIncludePath` 或命令行选项）。

## 结论（2026-10-08）

完成。stage0 执行文本种子后得到完整可用的 R6RS 环境，nanopass 可直接加载运行，适配文件与子模块都无需修改。

### 运行方式

```
cd IronScheme/IronScheme.Console
dotnet ../IronScheme.Stage0/bin/Release/net10.0/stage0.dll [--time] [--deterministic] -I lib -I lib/nanopass-framework-scheme boot-seed.core <脚本.sps> [参数 …]
```

示例脚本放在 `spikes/iron-017-nanopass/`：`remove-when.sps`、`to-cil.sps`（研究笔记 `nanopass.md` §2、§8.2）、`smoke.sps`（R6RS 冒烟）、`deterministic.sps`（iron-014 验证）。

### 结果

| 项目 | stage0 | 旧系统基线 |
|---|---|---|
| `tests/r6rs/run.sps` | 3 of 8971 failed（与基线是同样 3 项：重入续延、`output-port-buffer-mode`、`get-line` 的 `\r`），约 6.4 s | 3 of 8971 |
| `tests/trigtest.sps` | Failed 8 of 17707，约 17.5 s | 8 of 17707 |
| `tests/clisp-number-tests.sps` | Failed 3 of 2476，约 6 s | 3 of 2476 |
| `smoke.sps` | `eval`、`syntax-case` 宏（卫生）、`guard`、逃逸续延穿过 `dynamic-wind`、哈希表、Unicode、bignum、复数、`format` 均正确 | — |
| `remove-when.sps` | `(lambda (a) (call f (if a '1 '#<unspecified>)))`，与旧系统逐字相同，约 4.8 s（含加载 nanopass） | 旧系统 2.7 s |
| `to-cil.sps` | 与旧系统输出逐字相同，约 5.3 s | — |

与 Chez 对比（本机 Chez 10.x + `~/workspace/ChezScheme/nanopass`）：
- remove-when：结构相同，只是打印差异（Chez 写 `(quote 1)`、`#<void>`；IronScheme 写 `'1`、`(void)` 为 `#<unspecified>`）。
- to-cil：Lcil 与方法体文本在交换标签 `L1`/`L2` 后完全相同。差异来自 `(let ([else-l (fresh-label)] [end-l (fresh-label)]) …)` 的求值顺序：Chez 从右到左，IronScheme 从左到右，R6RS 未规定，两者都正确。
- 脚本改动：导入 `(rnrs)` 与 `(ironscheme)` 中的 `void`/`format`/`pretty-print`（Chez 的 `--script` 默认导入 `(chezscheme)`）；IronScheme 的 `format` 不支持 `~{…~}`，`to-cil.sps` 用一个拼接函数代替。

耗时：种子执行约 0.3 s；加载并展开 nanopass 约 4.5 s（解释执行，旧系统编译执行约 2.5 s）。

### 补齐与修改清单

| 位置 | 修改 | 原因 |
|---|---|---|
| `Core/Interop/TypeResolver.cs` | 别名 `IronScheme.Runtime.Builtins` → `IronScheme.Core.Builtins` | nanopass 适配文件写死旧类型名调用 `SourceLocation`；不改子模块、不复制源码。发射器按名字解析类型时须使用同一别名表 |
| `Core/Interop/Interop.cs` | `Cast`：整数类型（含 `char`）之间不检查溢出、截断取低位 | 旧编译器对 `clr-cast` 生成 IL `conv`（`ports.sls` 的 `(clr-cast Byte (clr-cast Int32 k))`，k 可为负） |
| `Core/R6RS/IO.cs` | `ToFileOptions` 从 enum 记录的 `value` 字段读位掩码 | 旧实现按 CLR 字段反射读取；新运行时记录字段在数组中（iron-009） |
| `Stage0` | `letrec`/`library-letrec*` 绑定的变量在初始化前读取报 `&assertion` | R6RS letrec 限制；R6RS 测试中的一项 |
| `Stage0` | 顶层程序经 `eval-embedded` 执行 `(load/program …)` | `eval-r6rs` 用 `clr-guard` 吞掉 CLR 异常，`ProgramFailedException` 传不出来，退出码总是 0 |
| `Stage0` | 选项 `-I <目录>`、`--deterministic` | 库搜索路径；构建模式 gensym |

iron-016 中已列的 Interop 修改（params 数组整体传入、字符与整数转换）也是在跑种子时发现的。

### iron-014 在新系统上的验证

`deterministic.sps` 在以库名为名的 gensym 作用域中展开一个含记录、命名 let 与宏的库，打印核心形式与导出表。两个进程分别运行：加 `--deterministic` 时输出逐字相同（gensym 形如 `g$gen1$5$det.test`）；不加时因 TICKS 不同而不同。确定性模式下加载 nanopass 运行 remove-when 也正常。

### 留给后续任务

- M3（iron-018 起）：发射器解析类型名时复用 `TypeResolver` 的别名表（含上述旧类型名映射）。
- 解释执行比旧系统的编译执行慢约 2 倍，对一次性的 Phase A 可以接受；新编译器运行在 stage0 上编译 boot 时如果太慢，再考虑优化解释器（变量访问特化、减少参数数组分配）。

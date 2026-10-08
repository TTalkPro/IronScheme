# iron-027 编译驱动

- 里程碑：M4　依赖：iron-026、iron-021　状态：完成
- 设计依据：[03 §8](../designs/03-compiler.md)

## 目标
实现 `compile-core`、`compile-library`、`compile-bootfile` 的新版本。

## 工作内容
1. `compile-core`：Lcore → Lcil → 发射器内存模式 → 调用入口；在 stage0 上运行时同样可用（stage0 进程内加载发射器），也可只输出 Lcil 文本。
2. `compile-library`：13 元素列表 → 库 dll。
3. `compile-bootfile`：核心形式列表 → boot 镜像 Lcil / dll。
4. 编译选项：调试信息、确定性 gensym 模式（配合 iron-014）。

## 验收标准
- 在 stage0 上用新编译器编译 `build/` 中的单个库（如 `lists.sls`）得到 Lcil，经 iron-emit 生成 dll。

## 从 iron-008 转来

- 原语 `compile-core`、`compile-library`、`compile-bootfile` 的新实现（旧版在 `IronScheme/Runtime/Builtins.cs:464-743`）。

## 从 M3（iron-018～021）转来

- `compile-core`（eval）：Lcil → `LcilEmitter.EmitInMemory` → `IronScheme.Core.ModuleLoader.Run(asm)`。
- `compile-library`：生成带 `(entry …)` 的库 dll，入口返回 13 元素列表；加载走原语 `load-library-dll`（`ModuleLoader.LoadModule`）。
- `serialize-port`/`deserialize-port` 已改为 fasl（iron-020），psyntax 的 fasl 路径可直接使用。

## 结论（2026-10-08）

完成（`lib/ironscheme/compiler.sls`，库 `(ironscheme compiler)`）。

| 入口 | 实现 |
|---|---|
| `front-end`、`compile-forms->lcil`、`compile->lcil-text` | Lcore → L3 → Lcil S 表达式 / 文本；库变量的再赋值信息跨形式合并 |
| `compile-core` | Lcil → `LcilEmitter.EmitInMemory` → 返回调用 `ModuleLoader.Run` 的无参过程；在 stage0 上可直接使用（stage0 引用了 Emit） |
| `compile-library 文件 e` | e 求值得到 13 元素库描述；生成库 dll，入口返回该列表，`load-library-dll` 读回 |
| `compile-bootfile forms [文件]` | 核心形式列表 → boot 镜像 dll，入口 `#Module::Initialize` |

编译选项：确定性 gensym 由运行时开关提供（stage0 `--deterministic`，iron-014）；编译器本身的输出只取决于输入（同一输入在不同进程中得到逐字相同的 Lcil）。**调试信息（序列点）第一版不生成**：parse-core 剥离注解，留给 M6（04 §4 规定第一版可选）。

### 验收与超出验收的验证

1. `compiler/tests/compile-library.sps`：在 stage0 上编译种子中的 `(ironscheme lists)`（约 0.4 秒，Lcil 14 万字符），发射为 dll，在 stage0 进程中加载执行；之后经 `eval` 使用的 `filter`、`fold-left` 等 15 个过程确认来自编译后的程序集，各项结果正确（含十万元素的表、错误条件）。另测 `compile-library` 与 `compile-bootfile` 两个入口。ILVerify 通过。
2. `compiler/tests/slow-compile-seed.sps`（Slow 类别）：把**整个文本种子（38 个形式）编译成一个 boot 镜像**——前中端 + 代码生成约 4 秒、文本写出约 5 秒、发射约 1 秒；Lcil 760 万字符。ILVerify 全部通过；两个进程分别编译得到的 Lcil 逐字相同，进程内发射与命令行 `iron-emit` 得到的 dll 逐字节相同。
3. **用编译出的 boot 镜像代替文本种子启动**（新增 stage0 选项 `--boot <dll>`；eval 仍由 stage0 解释）：`tests/r6rs/run.sps` 3/8971、`trigtest` 8/17707、`clisp-number-tests` 3/2476，与旧系统基线完全一致，且比解释执行快（trigtest 7 秒对 17.5 秒）。

### 其他修改

- 发射器加载被引用程序集的依赖（命令行发射时 Core 引用的 Oyster.IntX 才能被互操作类型查找找到）。
- `Stage0ScriptTests` 增加 nanopass 库路径；`slow-` 开头的脚本归入 Slow 类别。全部 207 项测试通过（含 8 个编译器脚本，约 2 分 20 秒）。

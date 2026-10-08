# iron-029 新宿主 IronScheme.Host 与 REPL

- 里程碑：M5　依赖：iron-021、iron-010、iron-008　状态：完成
- 设计依据：[02 §11](../designs/02-runtime.md)

## 目标
新控制台宿主能加载 stage1 boot 镜像，运行脚本与简单 REPL。

## 工作内容
1. 启动流程：初始化运行时 → 登记原语 → 加载 boot → 解析命令行。
2. 脚本模式：以 R6RS 顶层程序运行参数中的文件。
3. REPL：逐行读入、`eval-r6rs`、打印结果；错误时打印条件信息。
4. 库搜索路径与旧系统一致（`lib/` 等）。
5. 冒烟测试：`(display "hello")`、定义与调用过程、`(import (rnrs))` 下的常用操作。

## 验收标准
- 用 stage1 boot 运行冒烟测试全部通过。

## 从 iron-021 转来

- boot 镜像经 `ModuleLoader.LoadModule("~/ironscheme.boot.dll")` 加载并执行入口。旧 `Ports.Load` 中"启动时若 `build/ironscheme.boot.dll` 较新则替换 `ironscheme.boot.dll`（旧文件改名为 `.old.dll`，连同 pdb）"的逻辑由宿主实现。
- `ModuleLoader.ShowImports` 对应旧的 `-show-imports` 类开关。

## 结论（2026-10-08）

完成（`IronScheme/IronScheme.Host`）。

- **启动**：在 256 MB 栈的线程上运行；设置命令行（脚本及参数；REPL 为空串）→ 登记原语 → 加载 boot 镜像（默认 `~/ironscheme.boot.dll`；宿主构建时若 `IronScheme.Console/build/ironscheme.boot.dll` 存在则复制到输出目录）。旧系统的"当前目录下 `build/ironscheme.boot.dll` 较新时替换镜像（旧的改名 `.old.dll`，pdb 一并移动）"保留，只对默认路径生效。
- **选项**：`-I <目录>`（库路径；默认路径同旧系统：`.`、`<宿主目录>/lib`、宿主目录）、`--boot <dll>`、`--show-imports`、`--deterministic`。
- **脚本模式**：`(load/program 脚本)`（经 `eval-embedded`，`ProgramFailedException` 时退出码 1）。
- **REPL**（`Repl.cs`）：用 Core 的 reader 从标准输入读数据（可跨行）→ `eval-r6rs` → `pretty-print` 打印（未指定值不打印，多值逐个打印）；出错后继续；输入结束时退出。

### 验收

- `IronScheme.Console/tests/host-smoke.sps`：`display`、定义与调用过程、bignum、百万次循环、记录、syntax-case 宏、`eval`、逃逸续延、guard、字符串 / 有理数 / 排序 / 哈希表 / 字符串端口、互操作、`command-line`，并确认 `eval` 得到的过程来自新编译器生成的内存程序集，**全部通过**。
- 测试 `HostTests`（Stage1 类别，需先运行 `tools/build-stage1.sh`，否则跳过）：冒烟脚本、失败脚本退出码 1、REPL（多行定义、出错后继续），3 项通过。全部 210 项测试通过。
- 经新宿主运行三个测试套件：R6RS 3/8971（13 s）、trigtest 8/17707（52 s）、clisp-number-tests 3/2476（7 s），与基线一致。trigtest 较慢：大量逐条 `eval`，每次都经新编译器（nanopass 各 pass + 发射）——转给 iron-033。

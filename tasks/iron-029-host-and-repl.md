# iron-029 新宿主 IronScheme.Host 与 REPL

- 里程碑：M5　依赖：iron-021、iron-010、iron-008　状态：未开始
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

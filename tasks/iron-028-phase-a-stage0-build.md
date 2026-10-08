# iron-028 Phase A：stage0 编译出新 boot 镜像

- 里程碑：M5　依赖：iron-027、iron-021、iron-017　状态：未开始
- 设计依据：[05 §3](../designs/05-bootstrap.md)

## 目标
在 stage0 上运行新编译器，产出只引用 IronScheme.Core 的 stage1 boot 镜像。

## 工作内容
1. 构建脚本 `ironscheme-buildscript-nano.sps`：在 `seed-buildscript.sps` 基础上，`scheme-library-files` 加入编译器与 nanopass 的库（它们要进入 boot 镜像），`library-legend` / `identifier->library-map` 相应补充；最后一步调用新编译器生成 Lcil。
2. stage0 执行：种子 → 展开 boot 源文件、编译器、nanopass → 编译成 `boot.lcil`。
3. `iron-emit boot.lcil -o ironscheme.boot.dll`；ILVerify。
4. 检查产物的程序集引用中不含 `IronScheme.Scripting`、旧 `IronScheme`、`IronScheme.Closures`。
5. 记录耗时与 Lcil / dll 规模。

## 验收标准
- stage1 boot dll 生成且 ILVerify 通过；引用检查通过。

## 从 iron-017 转来

- stage0 命令行与选项见 iron-016、iron-017 结论；构建时加 `--deterministic`。种子由 `tools/gen-seed.sh` 生成。
- stage0 执行 `boot-seed.core` 时对顶层 `library-letrec*` 做了预链接（旧 boot 编译器静态链接造成的跨库前向引用）。新编译器编译 boot 镜像时会遇到同样的前向引用：库级过程须在任何库初始化代码运行之前就可用（例如先创建全部库级过程对象并写入位置，或编译为静态方法直接调用）。
- 解释执行比旧系统编译执行慢约 2 倍（nanopass 加载约 4.5 s）。

## 从 M4（iron-022～027）转来

- 编译器 `(ironscheme compiler)` 已能在 stage0 上把整个文本种子编译成 boot 镜像（`compiler/tests/slow-compile-seed.sps`，约 10 秒），ILVerify 通过，用它启动（stage0 `--boot`）三个测试套件与基线一致。
- Phase A 尚缺：把 nanopass 与编译器库本身也编进 boot 镜像（需要先用 psyntax 展开这些库得到核心形式，再与种子形式一起编译）；新系统中 `compile-core`、`compile-library`、`compile-bootfile` 要绑定到编译器（目前 boot 中这些名字没有定义，stage0 的 `compile-core` 是解释器）；构建脚本（seed-buildscript 的展开部分 + 编译器）在 stage0 上运行生成 stage1。
- 生成的 boot 镜像入口会预链接全部已知过程（对应 stage0 的预链接）。

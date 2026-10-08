# iron-028 Phase A：stage0 编译出新 boot 镜像

- 里程碑：M5　依赖：iron-027、iron-021、iron-017　状态：完成
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

## 结论（2026-10-08）

完成。命令：`tools/build-stage1.sh [输出目录]`（默认 `IronScheme/IronScheme.Console/build/`），即
`stage0 --deterministic -I lib -I lib/nanopass-framework-scheme boot-seed.core ironscheme-buildscript-nano.sps <输出目录>`。

### 构建脚本 `ironscheme-buildscript-nano.sps`

以 `seed-buildscript.sps` 的展开部分为基础（任务描述中"把编译器与 nanopass 加入 scheme-library-files"的做法不可行：nanopass 导出宏，不能像 boot 库那样只经图例导出原语）：

1. **展开 boot 源文件**（37 个）到 bootstrap 库集合，同旧脚本。
2. **新位置绑定**：由 `make-system-data` 得出新 boot 中各导出名的位置（loc），把它们绑定到构建进程中的同名值，并让 `rewrite` 使用新位置——这样 nanopass 的宏才能在构建进程里执行。值的来源：psyntax 四个库（compat、internal、library-manager、expander）的导出取脚本导入的**源码副本**（bootstrap 展开用的就是它，宏处理的语法对象是它的记录类型）；其余取运行中系统的值（运行中系统的原语位置表从种子中 `(psyntax internal)` 的 `current-primitive-locations` 位置取得）。
3. **在 bootstrap 集合中加载 `(ironscheme compiler)`**（连同 nanopass，共 24 个库），用 psyntax 的 `serialize-all` 取出新装入库的 invoke 代码（依赖在前），插入 boot 形式列表。编译器导出的 `compile-core`、`compile-library`、`compile-bootfile` 经图例导出，于是 psyntax 的 `eval` 在新系统中走新编译器。
4. **编译**：形式顺序为 boot 库（除 psyntax main）、nanopass 与编译器、primlocs、psyntax main，共 62 个；由运行中系统里的新编译器编成 Lcil，发射为 dll。

### 过程中解决的问题

| 问题 | 处理 |
|---|---|
| 确定性模式下，同一库在运行中系统与 bootstrap 集合中各展开一次，得到同名 gensym，后者覆盖前者的 label 绑定 | gensym "领域"：`Symbol.GensymRealm` 与原语 `$gensym-realm`；bootstrap 展开期间设为 `boot:` |
| 脚本导入的 `(psyntax …)` 是源码副本，其 `current-primitive-locations` 为空 | 见第 2 步：从种子取运行中系统的位置表 |
| 源码副本的 library-manager 缺 `.ironscheme.sls` 扩展名 | 在 parameterize 中补上 |
| `define-prims` 把 `clr-call-internal` 当值（在 stage0 中是特殊形式） | 这类名字保持裸符号 |
| nanopass 把展开时创建的 RCD 作为常量写进代码 | 常量编码增加 `(rcd rtd 父)`（只支持无 protocol 的，04 §3） |
| **eval 中语法对象常量经编码再解码成副本**，mark（靠 `eq?`）与 rib 失效，宏输出的标识符解析不到 | 内存模式改为传活对象：Lcil `(live-constants n)`，`LcilEmitter.EmitInMemory(text, file, object[])`，Core `ConstantPool`（04 §3） |
| 编译代码不检查 letrec 限制 | `check-forward` pass：前向变量初值 `($uninitialized)`，引用经 `$check-initialized` |
| 原语表在 boot 中依赖当前目录 | 展开 `(ironscheme compiler primitives)` 时把原语表作为常量烘进编译器 |
| `GetCaller` 遇到多个 `[Primitive]` 别名时抛 `AmbiguousMatchException` | 取第一个 |
| stage0 在执行种子之后才设置命令行，psyntax 已在初始化时读取 | 启动前设置 |

### 验收

- **stage1 boot dll 生成**：62 个形式，Lcil 1482 万字符，dll 约 5.0 MB；总耗时约 46 秒（展开 boot 7 s、展开编译器与 nanopass 17 s、编译 9 s、写 Lcil 10 s、发射 2 s）。
- **ILVerify 全部通过**（`tools/ilverify.sh`，已加入 Emit 引用）。
- **引用检查**（新增 `iron-emit --references <dll>`）：IronScheme.Core、System.Private.CoreLib、System.Console、Oyster.IntX、System.Text.RegularExpressions、IronScheme.Emit；**不含** IronScheme.Scripting、旧 IronScheme、IronScheme.Closures。
- **确定性**：两次构建的 Lcil 与 dll 逐字节相同。
- 超出验收：stage1 上（`eval` 全由镜像内的新编译器编译）`tests/r6rs/run.sps` 3/8971、`trigtest` 8/17707、`clisp-number-tests` 3/2476，与旧系统基线一致。

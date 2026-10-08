# iron-026 上下文规范化、try 提升与线性化

- 里程碑：M4　依赖：iron-025　状态：完成
- 设计依据：[03 §4](../designs/03-compiler.md) 第 12 ~ 15 步、§5

## 目标
生成 Lcil 文本。

## 工作内容
1. `normalize-context`：值 / 副作用 / 谓词上下文。
2. `lift-try`：表达式位置的 try 提升为语句。
3. `linearize`：栈式指令、局部变量分配、`.maxstack` 计算、分支汇合点栈形状检查、`tail.` 决定（try 区域内不加）。
4. 常量收集为常量表（调用 iron-020 的编码器）。
5. `emit-lcil`：输出文本。

## 验收标准
- 对若干小程序端到端：Lcore → Lcil → iron-emit → 运行，结果正确。

## 从 M3（iron-018～021）转来

- Lcil 第 1 版规格见 `designs/04-lcil-and-emitter.md` §2：普通 CIL 指令按 `OpCodes` 名字书写，短格式由发射器选择；`(tail)` 前缀须紧接 `call`/`callvirt` 且其后为 `ret`；结构化 `try` 各块末尾的 `leave`/`endfinally` 由发射器加入，进入 try 时求值栈须为空；互操作指令与 `clr-namespaces` 见 §2.5。
- 常量：用 `(ironscheme compiler constants)` 的 `encode-constants` 对整张常量表编码（共享编号全表统一），`write-lcil-datum` 写出；方法中用 `(ldconst k)`。类型名 `$Constants` 保留。
- 入口：`(assembly … (entry "类型" "方法"))`，入口为 `public static object 方法()`；boot 镜像约定 `#Module::Initialize`，库 dll 的入口返回 13 元素列表。
- 发射器以库 API 调用：`IronScheme.Emit.LcilEmitter.Save(lcil文本, 文件名, 输出路径)` / `EmitInMemory(lcil文本, 文件名)`；stage0 已引用 Emit。手写样例在 `IronScheme.Emit/samples/`，可作为生成代码的参照。
- 编译器库位于 `Console/lib/ironscheme/compiler/`，测试脚本放 `Console/compiler/tests/*.sps`（`Stage0ScriptTests` 自动在 stage0 上运行，退出码 0 为通过）。

## 结论（2026-10-08）

完成。normalize-context、lift-try、linearize 合在 `codegen.sls` 按上下文生成代码的过程中；emit-lcil 为 `lcil.sls`。

- **上下文**：value（结果留栈）、effect（不留）、test（留 CLR bool）、tail（返回）。`if` 测试在 test 上下文生成；`throw` 之后在 value / test 上下文补一个值保持分支汇合处的栈形状。
- **lift-try**：多操作数的形式（调用、原语、互操作、`gset!`、`set-box!`）中，若排在后面的操作数含 try，先把全部操作数依次存入临时变量再载入，保证进入 try 时求值栈为空。try 体在 value 上下文求值后存临时变量。
- **linearize**：局部变量按绑定分配（object）；标签按方法编号；`tail.` 只在尾上下文且不在 try 内；`.maxstack` 交给发射器（ILGenerator 计算）。
- **常量**：fixnum（`ldc.i4` + `RT.Box`）、布尔、`'()`、unspecified、BMP 字符、不含落单代理项的不可变字符串直接生成；其余进常量表，用 iron-020 的 `encode-constants` 编码。
- **emit-lcil**：块状结构（lcil / constants / type / method / body / try …）的子项逐行写出；字符串中的代理项对合成码点；纯 ASCII 字符串整段写出（文本写出从约 30 秒降到 5 秒）。

验收：
1. `compiler/tests/compile-small.sps`：39 个小程序经 psyntax 展开 → 新编译器 → 内存发射 → 运行，全部与期望一致，包括一百万次的命名 let 循环、相互尾递归、经 `apply` 的尾递归三十万层、一万层非尾递归、case-lambda / 剩余参数 / 6 参数调用、内部 define 的前向引用与被捕获变量的赋值、逃逸续延穿过 dynamic-wind、guard、多值、记录、syntax-rules、互操作。
2. 快照 `compiler/tests/snapshots.sps`：5 个手写 Lcore 的 L0、L2、L3、Lcil 共 20 个快照，并检查同一输入两次编译的 Lcil 逐字相同。
3. 生成的程序集 ILVerify 全部通过（含整个 boot 镜像）。

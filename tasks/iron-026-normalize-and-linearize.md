# iron-026 上下文规范化、try 提升与线性化

- 里程碑：M4　依赖：iron-025　状态：未开始
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

# iron-025 调用、原语与互操作降级

- 里程碑：M4　依赖：iron-024、iron-012　状态：完成
- 设计依据：[03 §4](../designs/03-compiler.md) 第 10 ~ 11 步、§6、§7

## 目标
把应用、原语、全局访问、互操作形式降成接近 Lcil 的调用形式。

## 工作内容
1. 应用 → 静态调用 / `InvokeK` / `InvokeN`；全局读写 → 值槽访问与未绑定检查。
2. 原语：内联 IL 模板库（对应旧系统 56 个内联发射器）、静态调用、特殊原语（`$try/finally`、`$throw`、`call/cc` 逃逸帧、`values`、`call-with-values` 内联、`apply`）。
3. `clr-*-internal` → Lcil 互操作指令；`clr-using`/`clr-reference` 收集为方法级上下文。
4. `ffi-*`、`pinvoke-call-internal` → 运行时辅助调用。

## 验收标准
- 快照测试；对每个内联模板有对照用例。

## 从 iron-009 转来

- 已知 RTD 的访问器与修改器可以内联为"类型检查 + 取 / 写 `Record.Fields[FieldDescriptor.Index]`"。

## 从 iron-011 转来

- FFI 形式生成的代码调用 `Helpers.FFIConvertTo<T>`、`FFIConvertFrom<T>`、`FFIDelegate<T>`、`FFIFunctionPointer(Delegate)`（新签名，不再传 CodeContext）。

## 结论（2026-10-08）

完成（`codegen.sls`）。

- **应用**：自尾调用 → 循环；已知过程 → `call` 静态子句方法；其余 → `Calls.Proc`（不是过程时报 assertion-violation）+ `callvirt InvokeK`（K ≤ 4）或打包后 `InvokeN`。尾位置加 `tail.`（try 内不加）。
- **全局**：读 `Calls.Global(符号)`（未绑定报 undefined-error），写 `Calls.SetGlobal`；符号经常量表。库变量为静态字段。原语作为值时读其名字符号的值槽。
- **原语**：内联模板 `void` `$car` `$cdr` `cons` `eq?` `not` `null?` `pair?`、`$fx+ $fx- $fx* $fxand $fxior $fxxor $fxnot`、`$fx=? <? >? <=? >=?`、`$fxzero? $fxnegative? $fxpositive?`、`$fl+ $fl- $fl* $fl/`、`$fl=? <? >? <=? >=?`；谓词在 test 上下文直接留 CLR bool 供分支；fixnum 常量操作数直接 `ldc.i4`。其余（含 `car`/`cdr` 的带检查版本、`$vector-ref` 等）静态调用原语表中的重载（剩余参数打包为 `object[]`；`allow-tail-call` 的加 `tail.`）。参数个数没有匹配重载时经值槽调用，运行时报错。
- **特殊原语**：`$try/finally` → 结构化 try（结果存临时变量）；`$throw` → `throw`；`$break` → `Calls.Break`；`$and?`/`$or?` 短路；**尾位置的 `apply`** 用 `Calls.ApplyArgs` 展开后 `tail. callvirt InvokeN`（经 apply 的尾递归不增长栈）；`call/cc`、`call-with-values`、`values` 用原语表中的后备实现（静态调用）。
- **互操作**：`clr-*-internal` 一一对应到 Lcil 互操作指令（类型、成员说明原样交给发射器决议）；`clr-using` 收集为单元的命名空间列表写到每个方法的 `clr-namespaces`，`clr-reference` 加入程序集引用。
- **FFI**：`ffi-callout-internal`、`ffi-callback-internal`、`pinvoke-call-internal`、`define-clr-class-internal` 第一版编译为 `Calls.Unsupported`（执行时报"尚不支持"）；boot 源码不使用它们。转给 iron-031（lib/ 中的 FFI 库）。
- 未做：已知 RTD 的访问器内联（iron-009 转来），留到 M6。

验收：`compiler/tests/inline-templates.sps`——每个内联模板（及几个静态调用的原语）在值上下文与谓词上下文中与 C# 原语实现对照，含溢出回绕、NaN、`-0.0`，**156 项检查全部通过**。快照 `*.lcil`。

Core 新增 `IronScheme.Core.Calls`（`Proc`、`Global`、`SetGlobal`、`ApplyArgs`、`Unsupported`、`Break`、`Uninitialized`）。

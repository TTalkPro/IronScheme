# iron-016 stage0：C# 核心形式解释器

- 里程碑：M2　依赖：iron-008、iron-009、iron-010、iron-011　状态：未开始
- 设计依据：[05 §4](../designs/05-bootstrap.md)、[03 §2](../designs/03-compiler.md)

## 目标
实现精简的 Lcore 解释器 `IronScheme.Stage0`，在新运行时上执行核心形式。

## 工作内容
1. 项目 `IronScheme/IronScheme.Stage0`（net10.0，引用 IronScheme.Core）。
2. 读取 Lcore 文本（含种子的中立编码数据）。
3. 预分析：核心形式 → 闭包树；变量解析为词法地址或符号值槽；原语按名字绑定到运行时登记的 `Procedure`。
4. 覆盖 03 §2 的全部形式：`quote`、`if`、`begin`、`set!`、各类 `case-lambda`、`letrec`、`letrec*`、`library-letrec*`、`annotated-call`、应用、`clr-*-internal`（经 `Interop` 反射执行）、`ffi-*`（可先报"不支持"）。
5. 解释器生成的过程是 `Procedure` 子类，可与原语互相调用。
6. 真尾调用：内部蹦床；`$try/finally`、逃逸续延、多值使用运行时机制。
7. 命令行：`stage0 <seed> <script.sps> [args]`。

## 验收标准
- 手写 Lcore 小程序（闭包、尾递归一百万层、多值、逃逸续延、try/finally、互操作调用）运行正确。
- 规模控制在一两千行 C#。

## 从 iron-011 转来

- `clr-*-internal` 形式直接调用 `Interop`：类型说明用 `TypeResolver.Resolve(说明, 当前命名空间列表)` 解析；`clr-using-internal` / `clr-reference-internal` 维护解释器中的命名空间列表与已加载程序集（编译期副作用，见 03 §7）。

## 从 iron-012 转来

- 原语表中的 `special` 条目 `$and?` `$or?` `$break` `$throw` `$try/finally` 作用于未求值的参数表达式，解释器需专门处理（`$and?`/`$or?` 短路、结果为布尔；`$try/finally` 第二个参数在 finally 中求值；`$throw` 抛出参数；`$break` 调用 `Debugger.Break`）。其余 `$` 原语可直接调用 `IronScheme.Core.Unsafe` 中的实现。

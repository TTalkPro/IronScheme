# iron-031 R6RS 测试与系统库编译达标

- 里程碑：M6　依赖：iron-030　状态：完成
- 设计依据：[06](../designs/06-r6rs-and-testing.md)

## 目标
新系统在符合性测试与系统库编译上达到 iron-001 记录的基线。

## 工作内容
1. `IronScheme.Tests` 改为 net10.0，宿主换成 `IronScheme.Host`。
2. 运行 `tests/r6rs/run.sps`、`trigtest.sps`、`clisp-number-tests.sps`、`fp-test.sps`，与基线逐项对比。
3. `compile-system-libraries`：全部库编译成 dll 并可独立加载（含 srfi、pfds）。
4. 对每个新增失败定位到运行时、编译器或发射器并修复；确属 call/cc 偏离的，记入 06 §1。

## 验收标准
- 失败数不超过基线；系统库数量与基线一致。

## 从 iron-010 转来

- `eqv?` 对 `0.0` 与 `-0.0` 返回 `#t`（旧系统与新运行时均如此：`IsEqualValue` 用 `Equals`，而 .NET 的 `double.Equals(0.0, -0.0)` 为真）。R6RS 要求返回 `#f`。
- 旧打印器把 `-0.0` 写成 `0.0`，把名为 `|` 的符号写成裸 `|`（无法读回）：打印器在 Scheme 中（`build/generic-writer.sls`），按需修正。

## 从 iron-025 转来

- `ffi-callout-internal`、`ffi-callback-internal`、`pinvoke-call-internal`、`define-clr-class-internal` 目前编译为运行时报"尚不支持"（`Calls.Unsupported`）；lib/ 中用到它们的库（如 `(ironscheme ffi)`）需要实现：运行时辅助调用 `Helpers.FFIConvertTo<T>` 等（iron-011）或静态生成。

## 结论（2026-10-08）

验收达标：失败数不超过基线，系统库数量与基线一致。

| 测试 | 基线 | 新系统 |
|---|---|---|
| `tests/r6rs/run.sps` | 3 of 8971 | 3 of 8973（同样 3 项：端口重入 `v`、`output-port-buffer-mode`、`get-line` 的 `\r`；多出的 2 项见下） |
| `tests/trigtest.sps` | 8 of 17707 | 8 of 17707 |
| `tests/clisp-number-tests.sps` | 3 of 2476 | 3 of 2476 |
| `tests/fp-test.sps` | 无输出 | 无输出 |
| SRFI 24 项、PFDS、MiniKanren | 通过 | 通过 |
| 系统库编译 | 232 | 232，只从 dll 加载可用，ILVerify 全部通过 |
| 自举 | — | stage1 == stage2 == stage3，6 项通过 |
| `IronScheme.Core.Tests` | — | 210/210（快照因新增 `get_Arity` 更新） |

修改：
- `IronScheme.Tests` 改为 net10.0、驱动 `IronScheme.Host`，加入 `IronSchemeNext.slnx`；新增 `SystemLibraryTests.cs`（类别 SystemLibraries：编译全部库写 `compiled.lst`、藏起 `lib/` 后只从 dll 加载、ILVerify）；`Setup.Cleanup` 删除 `compiled.lst` 列出的 dll 与 R6RS I/O 用例的 `tmp1`。
- 编译器：每个过程类生成 `get_Arity` 重写（stage0 的 Closure 同样实现）；支持非顶层 `library-letrec*`；常量表中含 `-0.0` 分量的非精确数不去重（03 §3）。
- 运行时：`eqv?` 区分 `0.0`/`-0.0`（按位比较，NaN 与自身相等）；reader 的直角复数保留 `-0.0` 虚部；`TypeResolver` 按惯例加载与类型全名/命名空间同名的程序集（02 §9）。
- 库：`(- x)` 改为 `(generic* -1 x)`（`(- 0.0)` 为 `-0.0`）；`flnumerator` 对 `±0.0` 原样返回；打印器写出 `-0.0`、复数的 `-0.0i`，符号中的 `|`、括号、引号、分号、控制字符等转义为 `\xHH;`；`lib/` 中 7 个文件改用新命名空间；`(ironscheme debugger)` 的 `step-into` 改为报不支持的桩。
- psyntax `compile-system-libraries`：当前目录有 `system-libraries.ss` 时在当前目录编译。
- 宿主替换 boot 镜像时复制 `build/ironscheme.boot.dll`，不再移动。

`eqv?` 修正后，`tests/r6rs/base.sls` 中 `(unless (eqv? 0.0 -0.0) …)` 保护的 2 个用例开始运行；它们与 `(- 0.0)`、`flnumerator` 的用例一起暴露出以前被常量表合并 `±0.0` 掩盖的问题，均已修正，06 §3 的期望相应改为 8973。

未实现：FFI（`ffi-callout-internal`、`ffi-callback-internal`、`pinvoke-call-internal`）与 `define-clr-class-internal` 仍编译为 `Calls.Unsupported`，记入 06 §1 的偏离；`(ironscheme ffi)` 等库能编译、加载，调用时报错。转 iron-032 决定去留。

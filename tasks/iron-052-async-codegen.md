# iron-052 异步：codegen 生成状态机

- 里程碑：后续　依赖：iron-051　状态：完成
- 设计依据：[10 §3.3](../designs/10-async.md) D12 ~ D14；形状见 [iron-049](iron-049-spike-async-frame.md) 的 spike

## 目标
`codegen.sls` 把 `async-lambda` 编成过程类 + 帧类，`MoveNext` 按 spike 验证过的形状生成：恢复点分派、finally 守卫、`label`/`jump`、`escape-frame`。完成后 `(await …)` 第一次真正不占线程地运行。

## 工作内容
1. **过程类**（D12）：`InvokeK` = 新建帧（自由变量副本 + 实参）→ `call AsyncFrame::Start` → 当 `object` 返回；无自由变量时仍是静态单例；剩余参数先打包；已知过程的直接调用规则不变。
2. **帧类**：基类 `IronScheme.Core.AsyncFrame`；字段 = 自由变量 + 形参 + 体内全部局部与临时变量；`override MoveNext`。
3. **async 方法上下文**（D13）：`mctx` 加 `async?`、恢复点计数与"当前 try 区域内的恢复点"栈；`vars` 一律 `(field . 名字)`，`new-local!` 分配字段；`tail-ok?` 恒假、无 loop-label；变量存储走临时变量再 `stfld`。
4. **生成规则**：
   - 体包在 `try … catch (Exception) { Fail }` 里，尾上下文的值 → `Complete; leave END`；
   - `await` → `Suspend` / `brtrue` / `leave END` / 恢复标签 / `Resume`；
   - 分派：方法开头与每个含恢复点的 try 区域入口各一段（`beq` 链或 `switch`）；
   - `try-finally` 的 finally 加 `state < 0` 守卫；
   - `escape-frame` → `new EscapeContinuation`、try/catch `ContinuationException`（不是自己的重新抛出）、守卫的 finally 里 `Invalidate`；
   - `label`/`jump`：参数字段并行赋值后 `br`；
   - `operands!` 的 lift-try 条件扩展为含恢复点（作为断言，D11 之后不应出现）。
5. **Lcil**：方法引用写 ``System.Threading.Tasks.Task`1[System.Object]``；确认发射器对 `IronScheme.Core.AsyncFrame` 基类与 `EscapeContinuation` 的引用无需新增。
6. 更新 [03 §5](../designs/03-compiler.md)（async 体内无尾调用）与 [02 §4、§6](../designs/02-runtime.md)。

## 验收标准
- iron-049 的测试矩阵改写成 Scheme 全部通过（见 iron-053 的 `tests/async`，本任务至少跑通快路径、挂起、循环、`dynamic-wind`、`guard` 跨 await、异常原样、深递归、100 × 300 ms < 1 s）。
- 生成的程序集过 ILVerify（`dotnet run tools/build.cs -- ilverify`）。
- 自举不动点不变；编译整个种子的统计输出不变。
- 同步完成的 `(await t)` 每次调用 ≤ 50 ns（基准脚本放在 `tests/async/bench.sps`）。

## 结论
- `codegen.sls`：`mctx` 加 `async` 字段（`aframe` 记录），`lambda-class!` 拆成 `procedure-class!` + `async-clause-method`（过程类的 `C0` 建帧并 `Start`，帧类 `名字$Frame : AsyncFrame` 带 `MoveNext`）；`cg` 新增 `async-lambda`、`await`、`label`、`jump`、`escape-frame` 子句，`try-finally` 与 `let` 子句扩展到 async 上下文；`bind-local!` / `store-var!` 支持帧字段；`finish-*` 的尾上下文在 async 下经 `Complete`；`collect-known!` 认 `async-lambda`（库级 async 过程也是已知过程，直接 `call C0`）。形状与细节写在 [10 §3.3](../designs/10-async.md) D14 后的实现说明。
- 运行时的两处改动（实测逼出来的）：**处理器栈不进入新 task / 新帧**——帧内的 `$current-handlers` 读写帧的 `handlers` 字段（线程静态 `AsyncFrame.Current`，`MoveNext` 开头 `Enter`、finally 里 `Exit`），`task-run` / `task-then` 的回调先清空处理器栈；原因是调用方的 `guard` 是逃逸续延，在 task 恢复到的线程上调用它只会抛 `ContinuationException`，条件就不是 `SchemeException` 了（见 10 §2 D7、§4）。**帧内的参数赋值不改创建线程的回退值**（`AsyncFrame.InFrame`），否则 `parameterize` 在别的线程上换出时主线程会留下换入的值。先试过在 `Start` 里改 AsyncLocal，一次调用 1 µs，改成线程静态后 Release 下 async 调用比同步调用只多 7 ns。
- 发射器：查实例构造函数时去掉 `Static`（`AsyncFrame` 有静态字段后 `.ctor` 与 `.cctor` 二义）；`EscapeContinuation.Invalidate` 改 public。
- 验收：`tests/async/basic.sps`（34 项：快路径不换线程、挂起恢复、命名 let / `do` 循环、`dynamic-wind`、`guard` / `with-exception-handler` / `parameterize` 跨 await、被等待 task 的 Scheme 条件与 .NET 异常、async 调 async、深递归一万层（同步与异步）、闭包、剩余参数、多值、操作数求值顺序、100 × 300 ms = 300 ms、TCS）与 `tests/async/interop.sps` 全过；编译成 `.fasl` 后 ILVerify 通过；`tests/async/bench.sps` Release 下同步调用 81 ns、async 调用 88 ns；`snapshots.sps` / `async-snapshots.sps` 不变；全部 C# 测试通过（含自举不动点）。种子编译统计比 iron-051 时多 7 个类、338 条指令，来自 iron-051 末尾重新生成的种子（展开器多了 `async-lambda` 的转换器），不是 codegen 的改动。

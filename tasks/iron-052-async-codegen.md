# iron-052 异步：codegen 生成状态机

- 里程碑：后续　依赖：iron-051　状态：未开始
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

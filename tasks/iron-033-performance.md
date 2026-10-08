# iron-033 性能优化（后续）

- 里程碑：M7　依赖：iron-031　状态：完成
- 设计依据：[03 §4 末尾](../designs/03-compiler.md)

## 目标
在正确性达标后，补回并超过旧编译器的优化。

## 候选工作
1. 跨库直接调用：对导入的不可变过程绑定直接调用其静态方法。
2. 类型推断与拆箱：fixnum/flonum 局部变量不装箱（对应研究笔记 6.3 第 10、11 步）。
3. `typed-lambda` 利用类型说明生成强类型方法。
4. 固定参数上限从 4 调整到实测最优值。
5. eval 快速路径：新系统内直接传递 Lcil 数据结构，跳过文本。
6. 基准：自举耗时、`tests/r6rs/run.sps` 耗时，与旧系统对比。

## 从 M4 转来

- 编译器第一版未做：类型推断与拆箱、已知 RTD 访问器内联、`call-with-values` 消费者内联、跨库直接调用、序列点（调试信息）。生成代码的统计见 iron-024 结论（2269 个过程类，62% 静态）。

## 从 M5 转来

- 新系统中每次 `eval` 都经新编译器（nanopass 各 pass + 发射），逐条 eval 很多的程序明显变慢：trigtest 在 stage1 上 52 秒（stage0 解释 eval 17 秒）。可考虑：简单表达式直接解释、缓存、减少 pass 开销、把编译器自身的 nanopass 代码优化。
- 与 ChezScheme 的对照与建议见 `designs/03-compiler.md` §4.1 末尾（原语签名、表驱动安全内联、pass 拆分）。

## 从 iron-031 转来

- `compile-system-libraries`（232 个库）约 55 秒；`eval`/`environment` 每次都要走完整编译管线，开销明显高于旧解释式求值，可考虑小表达式的快速路径。
- `(- x)` 现为 `(generic* -1 x)`，比原来的 `(generic- 0 x)` 稍慢，可在 `Numbers` 中加专门的取负原语。

## 结论（2026-10-09）

用 `dotnet-trace` 剖析，问题集中在运行时、发射器和 eval 路径，不在生成代码本身。逐项消除后结果如下（同一台机器，新宿主 + 最新 boot）：

| 测试 | iron-033 开始时 | 完成后 | 旧系统 |
|---|---|---|---|
| `tests/trigtest.sps` | 55 秒 | 15.7 秒 | — |
| `tests/r6rs/run.sps` | 12.6 秒 | 7.1 秒 | — |
| `tests/clisp-number-tests.sps` | 7.5 秒 | 4.1 秒 | — |
| 200 次 `(eval '(+ i 2) (environment '(rnrs)))` | 2.6 秒 | 0.6 秒 | — |
| `compile-system-libraries`（232 个库） | 29 秒（iron-031 时约 55 秒） | 18.2 秒 | 18 秒（iron-001） |
| 新系统自编译 boot（nano 构建脚本，含展开 nanopass 与编译器） | 23 秒 | 18 秒（仍为不动点） | 6 秒（只编译 boot，不含编译器） |
| stage0 → stage1 | 约 45 秒 | 约 44 秒 | — |

修改（按收益）：
1. **动态模块中类型过多**：同一动态模块里 `TypeBuilder.CreateType` 的开销随已有类型数增长，总耗时为平方级（16000 个类型约 8 秒）。内存模式下改为每 1000 个类型一个动态程序集（16000 个约 0.3 秒）。`Build()` 中按基类排序与查找的两处平方级循环改为字典（04 §4）。trigtest 有约 1.8 万个 thunk 类，主要靠这一项。
2. **索引器走运行时**：发射器把 `get_Item/set_Item` 一律交给运行时，`hashtable-ref/set!/update!` 每次都经反射并查 `DefaultMember` 特性，约占 eval 展开时间的 40%。改为按 `DefaultMember` 映射后静态决议，运行时侧的映射也按类型缓存（02 §9、04 §5）。
3. **eval 与 `compile-library` 不再经 Lcil 文本**：编译器产出的 S 表达式直接交给发射器（`EmitInMemoryData`、`SaveData`，`SchemeData` 把 Core 的 `Cons`/`Symbol` 转成发射器的树）。原先写文本和再解析约占 trigtest 的 27%。自举脚本仍写 `.lcil` 文本用于比对（03 §8、04 §4）。
4. **发射器的静态决议规则补全**：
   - 按参数个数过滤重载后再判断唯一（原先要求同名只有一个重载，与 04 §5 不符；如 `String.Substring`）；
   - 显式参数类型时允许 params 数组参数按数组整体传入（`string-append` 的 `(Concat String[])`）；
   - 实参都是 `clr-cast` 时，编译器在 Lcil 中给出实参类型提示，`clr-new`/`clr-call` 按完全匹配的重载静态调用（`make-string`、`values`，04 §2、§5）。
   
   boot 中仍由运行时决议的互操作调用点降到 31 处。
5. **运行时缓存**：
   - `Interop` 决议缓存键原先每次拼字符串（含 `AssemblyQualifiedName`），改为按类型比较的键；
   - `Interop.New` 原先每次重新选构造函数，现在也缓存；
   - 发射器缓存非动态程序集中的类型查找（原先每次遍历全部已加载程序集，而每次 eval 都新增程序集）；
   - 每个引用程序集的依赖只加载一次。
6. 小项：
   - Lcil 写出器的缩进不再 `make-string`；
   - `list->vector` 先数长度再填充；
   - `(- x)` 改为专门的原语 `generic-negate`（fixnum、flonum 直接取负，保留 `-0.0`）。

候选工作中第 5 项（eval 快速路径）与第 6 项（基准）已完成；第 1–4 项（跨库直接调用、类型推断与拆箱、`typed-lambda`、固定参数上限）属于生成代码质量，本任务未做，转入 iron-034。种子已按当前源码再生成（新宿主与 stage0 产物相同）。

测试：`./test.sh` 全部通过，IronScheme.Core.Tests 210/210，IronScheme.Tests 40/40（含 Bootstrap 不动点与 ILVerify）。

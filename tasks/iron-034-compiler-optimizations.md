# iron-034 编译器深度优化

- 里程碑：后续（M7 之后）　依赖：iron-033　状态：未开始
- 设计依据：[03 §4 末尾](../designs/03-compiler.md)、[02 §4](../designs/02-runtime.md)

## 目标
在 iron-033 消除运行时开销之后，提升生成代码本身的质量。

## 候选工作
1. 跨库直接调用：对导入的不可变过程绑定直接调用其静态方法（需要编译期知道被调库的类与方法，与"编译器不读运行时状态"（D4）的取舍）。
2. 类型推断与拆箱：fixnum/flonum 局部变量不装箱。
3. `typed-lambda` 利用类型说明生成强类型方法。
4. 固定参数上限从 4 调整到实测最优值。
5. 已知 RTD 访问器内联、`call-with-values` 消费者内联、序列点（调试信息）。
6. 没有自由变量的过程不再每个一个类（用共享类中的静态方法 + 委托包装），减少类型数与加载时间。

## 从 iron-033 转来

- iron-033 只做了运行时、发射器与 eval 路径上的优化（见其结论），上面的候选工作都未开始。
- 剖析方法：`dotnet tool install -g dotnet-trace`，`dotnet-trace collect --format speedscope -- dotnet IronScheme.Host.dll …`；注意 `tail.` 调用会抹掉中间帧，看到的调用者可能是更外层的过程。
- 剩余的运行时互操作决议点（boot 中 31 处，多为 `clr-new` 的重载构造函数，如 `make-hashtable`、`string`、编解码器）可按 `values` 的做法加 `clr-cast` 提示。

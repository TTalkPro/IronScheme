# iron-012 原语表生成工具 PrimGen

- 里程碑：M1　依赖：iron-008（以及 iron-009 ~ iron-011 完成后再生成完整版）　状态：未开始
- 设计依据：[02 §5](../designs/02-runtime.md)、[03 §6](../designs/03-compiler.md)

## 目标
从 IronScheme.Core 反射出全部原语，生成编译器使用的数据文件。

## 工作内容
1. 控制台工具 `IronScheme/IronScheme.PrimGen`：加载 `IronScheme.Core.dll`，输出 `IronScheme.Console/compiler/primitives.ss`。
2. 每项：名字、类型全名、方法名、参数个数（含剩余参数标记）、标志（`pure`、`unsafe`、`allow-tail-call`）、内联模板名（若有）。
3. 特殊原语（`$try/finally`、`$throw`、`$break`、`$and?`、`$or?`、`call/cc`、`values`、`call-with-values`、`apply`）以手写条目合并进来。
4. 输出排序稳定，便于 diff。

## 验收标准
- 生成文件可被 Scheme `read` 读入；与 iron-008 的原语对照表一致。

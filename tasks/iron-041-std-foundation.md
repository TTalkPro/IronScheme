# iron-041 std 基础：目录、约定与语法类库

- 里程碑：M9　依赖：iron-040　状态：未开始
- 设计依据：[08](../designs/08-std-library.md) §1、§5

## 目标
建立 `(ironscheme std …)` 的目录、许可证与测试约定，完成基础库 promise 改造（D7）与第一批库。

## 工作内容
1. `src/scheme/lib/ironscheme/std/`、`LICENSES/`；测试脚本目录 `src/scheme/tests/std/` 与测试类别 `Std`；检查 D2 的守卫脚本（每个 std 库与 `(ironscheme)` 无冲突、无转导出）。
2. 基础库 `delay`/`force` 改为迭代强制（SRFI-45 / R7RS 语义），重建 boot。
3. 库：`syntax` `procedures` `boxes` `lazy`，各带测试。

## 验收标准
- 新库测试通过、D2 守卫通过、全部原有测试通过。

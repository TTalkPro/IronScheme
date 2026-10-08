# iron-015 生成文本种子 boot-seed.core

- 里程碑：M2　依赖：iron-001、iron-013、iron-014　状态：未开始
- 设计依据：[05 §2、§5](../designs/05-bootstrap.md)

## 目标
用旧系统把 36 个 boot 源文件展开成核心形式，写成文本种子。

## 工作内容
0. 旧系统使用 `legacy-stage0/` 中的快照运行（BuildTools 已删除，不能重新构建）。修改后的 boot 源码需复制到快照目录的 `build/`、`psyntax/` 下，或让脚本从仓库源码目录读取；用完后恢复快照中的原始种子。
## 工作内容
1. 以 `ironscheme-buildscript.sps` 为基础写 `seed-buildscript.sps`：保留展开部分（`expand-all`、`library-legend`、`identifier->library-map`、`define-prims`），最后一步把 `(map compile-core-expr core*)` 写成文本，而不调用 `compile-bootfile`。
2. 文本格式：每个顶层核心形式一个 S 表达式；记录、gensym、注解等非标准数据用与 Lcil 常量相同的中立编码（04 §3）或约定的扩展语法表示，保证 stage0 能读回同一结构。
3. 构建模式开启确定性 gensym（iron-014）。
4. 输出到 `IronScheme/IronScheme.Console/boot-seed.core`，记录文件大小与形式数量。

## 验收标准
- 两次生成的种子逐字节一致。
- stage0 的 Lcore 读取器（iron-016）能完整读回种子。

# iron-027 编译驱动

- 里程碑：M4　依赖：iron-026、iron-021　状态：未开始
- 设计依据：[03 §8](../designs/03-compiler.md)

## 目标
实现 `compile-core`、`compile-library`、`compile-bootfile` 的新版本。

## 工作内容
1. `compile-core`：Lcore → Lcil → 发射器内存模式 → 调用入口；在 stage0 上运行时同样可用（stage0 进程内加载发射器），也可只输出 Lcil 文本。
2. `compile-library`：13 元素列表 → 库 dll。
3. `compile-bootfile`：核心形式列表 → boot 镜像 Lcil / dll。
4. 编译选项：调试信息、确定性 gensym 模式（配合 iron-014）。

## 验收标准
- 在 stage0 上用新编译器编译 `build/` 中的单个库（如 `lists.sls`）得到 Lcil，经 iron-emit 生成 dll。

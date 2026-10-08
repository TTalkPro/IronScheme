# iron-030 Phase B：自举不动点

- 里程碑：M6　依赖：iron-028、iron-029　状态：未开始
- 设计依据：[05 §2、§3、§6](../designs/05-bootstrap.md)

## 目标
新系统自己编译自己，达到不动点。

## 工作内容
1. 新系统上的构建脚本形态（编译器在镜像内、发射器同进程调用）。
2. stage1 → stage2 → stage3（另验证：stage0 编译出的 stage1 与 stage2 的 Lcil 是否一致，不一致时分析原因）；比较 stage2 与 stage3 的 Lcil 文本与 dll 字节。
3. 不一致时定位来源（gensym、遍历顺序、浮点格式等）并修复。
4. 改写 `BootstrapTests` 为新流程。
5. 用 stage3 替换工作区中的种子文件（不提交）。

## 验收标准
- stage2 与 stage3 的 Lcil 一致、dll 逐字节一致；ILVerify 通过。

# iron-020 常量编码与 fasl

- 里程碑：M3　依赖：iron-018、iron-005、iron-009　状态：未开始
- 设计依据：[04 §3](../designs/04-lcil-and-emitter.md)

## 目标
实现常量的中立编码（Scheme 侧写出）→ 二进制 fasl（发射器）→ 对象（运行时读回）全链路。

## 工作内容
1. Scheme 侧编码器（放在编译器中，iron-026 使用）：覆盖 04 §3 全部编码，含共享与环。
2. 发射器：编码 → 二进制 fasl，嵌入为托管资源；模块类型初始化读取到 `c$`。
3. 运行时 `Fasl.Read`：重建对象；符号按名字驻留；记录按 RTD uid 取回或登记。
4. 在 stage0 上运行编码器，确认能对 psyntax 语法对象等记录正确编码，并在加载后按 uid 重建。

## 验收标准
- 往返测试：各类常量、共享结构、环、嵌套记录。
- psyntax 语法对象在交叉编译场景下能重建（结合 iron-009 的结论）。

## 从 iron-008 转来

- 原语 `serialize-port`、`deserialize-port`（旧版用 BinaryFormatter，`psyntax/main.sls` 导入它们），改为基于 fasl 实现。
- 旧 `Helpers.DeserializeAssemblyConstants` 由 fasl 常量读取取代。

## 从 iron-009 转来

- 记录常量重建：非生成性 RTD 用 `Records.LookupNongenerative(名字, uid)` 取回；psyntax 的 `stx` 等记录的 uid 是展开时生成的 gensym 常量（见 iron-009 结论）。记录实例为 `Record`（`Rtd` + `Fields`），条件为 `Condition` / `CompoundCondition`。

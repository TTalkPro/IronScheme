# iron-020 常量编码与 fasl

- 里程碑：M3　依赖：iron-018、iron-005、iron-009　状态：完成
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

## 结论（2026-10-08）

完成。格式见更新后的 `designs/04-lcil-and-emitter.md` §3。

### 实现

| 位置 | 内容 |
|---|---|
| `Console/lib/ironscheme/compiler/constants.sls` | 库 `(ironscheme compiler constants)`：`encode-constants`（整张表统一 def/ref 编号；两遍：先统计 eq 共享，再编码；沿表尾循环不递归）、`encode-constant`、`write-lcil-datum`（按 Lcil 词法写出，字符串转义 `\xHH;`）。只检查常量对象本身（记录、注解等用 `clr-is`/`clr-field-get`），不读运行时全局状态 |
| `IronScheme.Emit/FaslEncoder.cs` | 中立编码 → fasl 字节，含格式校验（未知编码、操作数、未定义的 ref、flonum 位模式） |
| `IronScheme.Emit/EmitConstants.cs` | 保留类型 `$Constants`：字段 `c`，类型初始化器 `Fasl.ReadTable(base64)` |
| `IronScheme.Core/Fasl.cs` | `Read`/`ReadTable`/`Write`；原语 `serialize-port`、`deserialize-port`（取代 BinaryFormatter，iron-008 转来） |

与设计草案的差别：
- 增加 `(list …)`/`(dlist …)`（长表）、`(eof)`、`(cnd …)`（复合条件不是带 RTD 的记录）、`(ann …)`、`(eqht …)`（psyntax rib 的索引表）。
- 常量块用 base64 字符串而不是托管资源（内存模式不能带资源）。
- **编译器库的位置改为 `Console/lib/ironscheme/compiler/`**：`load` 只接受顶层程序，库必须经库路径解析，而 `(ironscheme compiler …)` 要求目录 `ironscheme/compiler/`。设计 03 §1、05 §2 与 iron-022 已同步；`Console/compiler/` 只放原语表与编译器测试（`compiler/tests/`）。
- `IronScheme.Stage0` 增加对 `IronScheme.Emit` 的项目引用（Phase A 本来就要同进程调用发射器）。

### 验收

1. 往返测试 `FaslTests`（9 项）：各类原子（含 bignum、有理数、精确 / 非精确复数、`-0.0`、NaN、补充平面字符、可变字符串、字节向量、eof、unspecified）；共享、环（表尾指回表头、向量包含自己、表中间被共享的序对）；20 万元素的长表不爆栈；非生成性记录按 uid 取回同一 RTD、生成性 RTD 在一次读取内共享、子类型、自引用记录；注解；eq 哈希表（含 `'()` 键、同内容同字节）与复合条件；`serialize-port`；经发射器两种模式的常量表（跨常量共享、环、记录、注解、常量只读一次）；编码错误。
2. `compiler/tests/constants-roundtrip.sps`（stage0 上运行，经 `Stage0ScriptTests` 纳入 NUnit）：用 Scheme 编码器编码 13 类常量、写成 Lcil、内存模式发射后读回，**46 项检查全部通过**，包括 psyntax 语法对象：`syntax->datum` 相同，`syntax-case` 能匹配，`free-identifier=?`（`lambda`、`car`）与 `bound-identifier=?` 为真，解码后的语法对象可 `eval`。
3. 全部 195 项测试通过；原语表 127 个原语、10 个特殊条目（新增 `serialize-port`、`deserialize-port`）。

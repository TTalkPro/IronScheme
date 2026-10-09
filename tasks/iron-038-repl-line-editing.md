# iron-038 REPL：行编辑、补全与提示

- 里程碑：M8　依赖：iron-035　状态：完成
- 设计依据：[07 §4](../designs/07-tooling-and-embedding.md)

## 目标
交互使用时提供行编辑、历史、Tab 补全与参数提示。

## 工作内容
1. 宿主中实现行编辑器（`System.Console`），标准输入重定向时退回逐行读取。
2. Scheme 侧提供补全候选与过程形参查询，经运行时钩子供宿主调用。
3. 测试：补全与提示的查询逻辑单元测试；重定向模式的 REPL 测试保持通过。

## 验收标准
- 终端中可编辑、浏览历史、Tab 补全名字与库名、看到过程形参提示；非终端输入行为不变。

## 结论（2026-10-09）

完成，见 07 §4。

**宿主（`LineEditor.cs`）**

终端交互时使用行编辑器，标准输入或输出被重定向时仍逐个读取数据，测试与管道用法不变。功能：
- 行内编辑：左右移动、Home/End、Ctrl+A/E/B/F/K/U/W、Ctrl+左右按词移动；
- 多行输入：括号未闭合时换行继续，续行提示为 `. `；
- 历史：上下键浏览，保存到 `~/.ironscheme_history`；
- Tab 补全：补全名字，`(import …)` 中补全库名（含 only/except 等修饰形式内）；有多个候选时补公共前缀，再按一次列出候选；
- 参数提示：在行尾以暗色显示；
- 右括号匹配：短暂跳到与之匹配的左括号；
- Ctrl+C 取消当前输入，空行上 Ctrl+D / Ctrl+Z 退出，Ctrl+L 清屏。

光标定位：
- Unix 上不查询光标位置，用 ANSI 相对移动。实测在不回应 `ESC[6n` 的伪终端里，查询会吞掉按键、使输入错乱。
- Windows 上用 `SetCursorPosition` 绝对定位。
- 终端不支持时退回逐个读取数据。

**Scheme 侧（psyntax main）**

登记钩子 `repl-complete`、`repl-describe`：
- 名字取自交互环境；
- 库名取自已安装的库，以及库搜索路径下的 `.sls`（反解 `%XX`）；
- 提示显示过程各子句的形参，多于两个子句时显示首尾两个；语法关键字不提示。

**形参来源（`procedure-form`）**
- 编译器为每个过程类生成 `get_Form`：各子句的 `(名字 . 形参)`，形参名由 psyntax 的 gensym 还原；
- C# 原语的 `Form`/`Arity` 取自方法签名；
- `procedure-form` 按子句以多值返回，与旧系统及 `linq.sls` 的用法一致。

**测试**
- 单元测试 `LineEditorTests` 19 项：括号平衡、字符串、字符字面量、注释、补全起点（符号与 import 中的库名）、提示的首符号。宿主为此对测试程序集开放内部成员，Core.Tests 改为引用 Host 程序集。
- 脚本测试 `Other.ReplHooks`：补全、库名、提示、`procedure-form`。
- 快照因 `get_Form` 更新。

交互部分用 Python 的 `pty` 驱动宿主做了手工验证：补全、提示、历史、多行、两次 Tab 列出候选、Ctrl+C、`(exit)` 均正常。

全部测试通过：Core.Tests 229/229，IronScheme.Tests 46/46。种子已按当前源码再生成，达到不动点。

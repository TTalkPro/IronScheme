# iron-054 基础库问题修复

- 里程碑：M9　依赖：iron-041 ~ iron-046　状态：完成
- 设计依据：[08](../designs/08-std-library.md)；R6RS

## 目标
修正 iron-041 ~ iron-046 实现 std 库时记录下来的基础库问题（用户要求"都修掉"）。

## 工作内容
| # | 问题 | 修正 |
|---|---|---|
| A | `string-copy` 返回不可变字符串（R6RS 要求新分配的副本可变） | 总是返回可变字符串 |
| C | Linux 上 `native-eol-style` 也是 `crlf` | Windows 为 `crlf`，其他为 `lf` |
| D | `format` 不认识 `~n@*`，未知指令原样输出不报错；`~d` `~x` `~b` `~o` 的结果带引号 | 支持 `~*`、`~n*`、`~@*`、`~n@*`；未知指令报错；数字指令用 display |
| E | 缺 `define-values`（R7RS）、`with-output-to-string` | 加入 `(ironscheme)` |
| F | `bitwise-copy-bit` 下标 31 报错 | fixnum 快速路径只用于下标 < 31 |
| G | eq/eqv 散列表的 `hashtable-hash-function` 应返回 #f（R6RS） | 返回 #f |
| H | `string-compare` 返回码点差 | 返回 -1 / 0 / 1 |
| I | `vector-binary-search` 用 .NET 默认比较器、找不到返回负数 | 按 SRFI 133：`(vector-binary-search vec value cmp [start end])`，找不到返回 #f |
| J | `string-hash`、`string-ci-hash` 可能为负，且每个进程不同（.NET 随机化） | 非负、确定的 FNV-1a |
| K | char-sets 标准字符集是 Unicode 5.x 数据 | 按 .NET 的 Unicode 数据重新生成 |
| B | BMP 之外的字符在字符串中占两个码元（字符串为 UTF-16） | 用户选定"自有字符串类型（窄/宽）"，另立 iron-055 |

## 验收标准
- 每项有测试；std 库中为绕开这些问题所做的处理改回直接使用基础库；全部测试通过，种子达到不动点。

## 结论（2026-10-09）

完成（B 项按用户的选择另立 iron-055）。

| # | 修改 |
|---|---|
| A | `boot/base.sls` 的 `string-copy` 对不可变字符串也返回可变的 `StringBuilder` |
| C | `boot/io/ports.sls` 的 `native-eol-style` 与 C# `Transcoder` 的缺省行尾：Windows 为 `crlf`，其他为 `lf` |
| D | `boot/format.sls` 重写指令解析：`~d ~x ~o ~b` 改用 display（原来 write 出带引号的字符串，如 `(format "~d" 5)` 得 `"\"5\""`）；新增 `~n`（换行）、`~n*`、`~n:*`、`~n@*`（SRFI 29 的位置参数）；未知指令、参数不足、数字指令遇到非数都报错（原来未知指令原样输出） |
| E | `define-values`（R7RS）作为展开器的系统宏加入 `(ironscheme)`（`boot/expander/core.sls` 的 `define-values-macro`，两份构建脚本的宏表与图例登记）；`with-output-to-string`、`with-input-from-string` 放在 `(ironscheme std ports)`：nanopass 子模块的测试辅助库 `(import (ironscheme))` 后自己定义了 `with-output-to-string`，基础库导出同名会使它无法加载，而子模块不能改 |
| F | `boot/arithmetic/bitwise.sls` 的 `bitwise-copy-bit`：fixnum 快速路径只用于下标 < 31 |
| G | `boot/hashtables.sls` 的 `hashtable-hash-function`：eqv 表（内部散列函数为 `eqv-hash`）与其只读副本返回 #f |
| H | `boot/unicode.sls` 的 `string-compare` 返回 -1 / 0 / 1 |
| I | `boot/misc.sls` 的 `vector-binary-search` 按 SRFI 133：`(vector-binary-search 向量 值 比较过程 [start end])`，找不到返回 #f；保留两参数形式（按实数、字符串、字符的自然序） |
| J | `string-hash`、`string-ci-hash` 改为 C# 的 FNV-1a（`Builtins.StringHash`、`StringCiHash`，取低 30 位）：非负，只取决于内容；`symbol-hash` 取低 30 位保证非负 |
| K | `(ironscheme std char-sets)` 的标准字符集按 .NET 的 Unicode 数据重新生成（各集合即 Unicode 一般类别，与 Scheme 48 生成原数据的规则相同）；char-sets 测试中写死的 Unicode 5 集合大小改为与 `char-general-category` 现场统计比较 |

**std 中为绕开这些问题所做的处理，已改回直接使用基础库**：strings 测试的 `mutable-string` → `string-copy`；arithmetic 的库内 `%bitwise-copy-bit` 删除；hashtables 测试恢复 eqv 表 `hashtable-hash-function` 为 #f 的原项；vectors 测试恢复 7 项 `vector-binary-search` 原项；comprehensions 测试恢复原生转码器；strings、vectors、compare-procedures、localization、generators 的文件头说明相应更新。

**测试**：新增 `tests/base-library.sps`（39 项，C# Other 类别的 `BaseLibrary`）逐项覆盖 A ~ J。

**验证**：boot 重建，种子再生成，`seed` 与 `seed --stage0` 逐字节相同，重建后再生成仍相同；完整测试 Core.Tests 229/229，IronScheme.Tests 全部通过（SystemLibraries 常数更新后单独复跑 2/2）。

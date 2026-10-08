# iron-014 构建模式下的确定性 gensym

- 里程碑：M2　依赖：iron-001　状态：完成
- 设计依据：[05 §3](../designs/05-bootstrap.md)

## 目标
让同一输入的两次构建产生相同的 gensym 名字，从而能比较自举不动点。

## 工作内容
1. 调查 psyntax 中 gensym 的生成点（库 id、位置 loc、词法变量）以及 `g$name$N$TICKS` 中时间戳的来源。
2. 构建模式下改为"库名 + 计数器"命名，保证跨库唯一、可复现；交互模式保持原样。
3. 后备方案：Lcil 比较工具在比较前做 gensym α 重命名。

## 验收标准
- 同一源文件两次展开得到的核心形式逐字相同（构建模式下）。

## 从 iron-013 转来

- 种子脚本雏形 `IronScheme/IronScheme.Console/seed-buildscript.sps` 已能在旧系统上展开全部 37 个文件（运行方式见 iron-013 结论）。确定性 gensym 应在这个脚本的运行环境中生效。

## 结论（2026-10-08）

完成。确定性分两处实现：

### 1. 新运行时（stage0 与新系统上运行 psyntax 时）

- `RuntimeOptions.DeterministicGensym`，Scheme 侧开关 `(deterministic-gensym? [#t/#f])`（`(ironscheme)`）。
- gensym 作用域（`Symbol.cs`）：构建模式下名字中的 TICKS 换成**作用域名**，计数在作用域内从 1 开始，命名与匿名 gensym 共用计数：`g$<名字>$<n>$<作用域>`、`g$gen<n>$<作用域>`。作用域名中的 `$` 换成 `_`（不影响 `ungensym` 取第一、第二个 `$` 之间的部分）。未进入作用域时用 `%top`。非构建模式下行为不变（`g$…$<计数>$<TICKS>`）。
- 原语 `$gensym-scope`（`(ironscheme unsafe)`）：无参返回当前作用域对象（无则 `#f`）；参数为库名列表（`(rnrs base)` → `rnrs.base`）或字符串时进入新作用域；参数为先前返回的对象或 `#f` 时恢复。
- `psyntax/expander.sls`：`library-expander` 在 `with-gensym-scope`（`dynamic-wind` 保存/恢复）中展开整个库，库 id 也在该作用域内生成；库名先用 `parse-library` 取出。展开中嵌套加载其他库时，内层进入自己的作用域，返回后外层计数继续。
- 原语表重新生成：125 个原语、10 个特殊条目。新增测试 `DeterministicGensymUsesScopeAndCounter`，143 项测试通过。

库 gensym 跨进程可复现且跨库唯一：作用域名就是库名，同一库在构建中只展开一次。注意：构建模式下若同一进程把同一个库展开两次，会得到同名 gensym（按名字驻留即同一对象），所以交互模式不开启该开关。

### 2. 文本种子（旧系统运行时）

旧系统的 gensym 无法改动。种子写出器（iron-015）把本进程的 gensym 后缀 `$TICKS` 改写为 `$%seed`；计数部分在同一输入下由展开顺序决定，实测两次生成的种子逐字节一致（见 iron-015）。`%seed`、`%top` 以 `%` 开头，不会与库名作用域（来自标识符，`$` 已替换）冲突。

### 留给 iron-017

- 在 stage0 上开启 `(deterministic-gensym? #t)` 后，用种子中的 psyntax 把同一库展开两次（两个进程），比较核心形式逐字相同，作为本任务在新系统上的最终验证。

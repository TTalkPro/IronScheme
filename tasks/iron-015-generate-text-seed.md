# iron-015 生成文本种子 boot-seed.core

- 里程碑：M2　依赖：iron-001、iron-013、iron-014　状态：完成
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

## 从 iron-013 转来

- `seed-buildscript.sps` 已完成展开部分；本任务只需加上把 `(map compile-core-expr core*)` 写成文本的步骤。
- 脚本必须复制到 `IronScheme.Console` 以外的目录、在 `legacy-stage0/` 下运行，源码根目录作为命令行参数（旧系统会优先加载当前目录和脚本目录下的 `psyntax/*.sls` 源码）。
- 生成的 `(psyntax primlocs)` 库已改为纯 Scheme 建表，不引用 C# 方法。

## 结论（2026-10-08）

完成。`IronScheme/IronScheme.Console/boot-seed.core`：1,553,922 字节、18,850 行、38 个顶层形式（37 个库的 `library-letrec*` + 构建脚本合成的 `(psyntax primlocs)` 库，位于最后一个库之前）。

### 生成

- 命令：`tools/gen-seed.sh`（仓库根目录）。它把 `seed-buildscript.sps` 复制到临时目录，在 `legacy-stage0/` 下运行，源码根目录作为参数（原因见 iron-013）。不生成 dll，不改动快照中的种子，无需恢复。耗时约 7 秒（展开 2.7 s、写出 2.3 s）。
- 输出为 ASCII 文本：文件头两行注释，之后每个顶层形式一段，子表放得进 100 列则写在一行，否则头部后各元素换行缩进 2 格。

### 文本格式（与新 reader 的约定）

核心形式本身就是普通 S 表达式，常量也都是标准数据，所以没有用 04 §3 的结构化常量编码（那是 Lcil 常量表的格式），而是写成新 reader 能逐值读回的 R6RS 语法。写出器在脚本里自己实现，不用旧系统的 `write`：

| 数据 | 写法 |
|---|---|
| 符号 | 不合 R6RS 标识符语法的字符写成 `\xHH;`（新 reader 不支持 `|…|`）；`+ - ...` 与 `->…` 原样 |
| gensym | `g$名字$计数$TICKS` 中本进程的 `$TICKS` 后缀改为 `$%seed`（iron-014） |
| 字符串 | `\"`、`\\` 转义，可打印 ASCII 原样，其余 `\xHH;`；旧系统按 UTF-16 存储，成对的代理项合成一个码点（`unicode.sls` 的大小写表有补充平面字符），落单的代理项报错 |
| 字符 | 可打印 ASCII 写 `#\c`，其余 `#\xHH` |
| 数值 | 精确数 `number->string`；flonum 检查能读回同一值，`+nan.0` 与 `-0.0` 单独处理（旧打印器把 `-0.0` 写成 `0.0`） |
| 向量、字节向量 | `#(…)`、`#vu8(…)` |
| 其他对象 | 报错。实际种子中没有：非调试模式下 psyntax 不生成注解，常量里也没有记录或语法对象 |

### 验收

1. 两次生成的种子逐字节一致（`cmp` 通过；SHA-256 前缀 `bac6eec8019d52f9`）。注意：旧系统编译构建脚本本身也消耗 gensym 计数，所以修改 `seed-buildscript.sps` 会整体改变种子中的计数（不影响正确性），比较种子时要用同一版脚本。
2. stage0（iron-016）用新 reader 完整读回并执行全部 38 个形式。

### 其他改动

- `seed-buildscript.sps` 导入增加 `(rnrs bytevectors)`、`(rnrs arithmetic flonums)`；iron-013 的诊断清单（无 Scheme 定义的 core-prim）改为写到标准错误。

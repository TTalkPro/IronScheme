# iron-002 以第三方依赖引入 nanopass-framework-scheme

- 里程碑：M0　依赖：无　状态：完成
- 设计依据：[03 §1](../designs/03-compiler.md)、[00 D15](../designs/00-overview.md)

## 目标
以 git 子模块引入 nanopass 框架，不复制源码。

## 工作内容
1. 在 `IronScheme/IronScheme.Console/lib/nanopass-framework-scheme` 添加子模块，指向 https://github.com/nanopass/nanopass-framework-scheme ，固定到一个明确的提交（记录提交号）。
   - 注意：`git submodule add` 会修改 `.gitmodules` 并暂存子模块条目；本仓库只开发不提交，暂存后不提交。
2. 确认库搜索方式：`(nanopass)` 对应子模块根目录的 `nanopass.ss`，子目录 `nanopass/` 下是各组件库。记录 IronScheme 的库扩展名约定（`.sls`、`.ss` 等）与搜索路径配置方法，供 stage0 与新宿主使用。
3. 列出 nanopass 依赖的实现相关功能（`implementation-helpers.ironscheme.sls` 导出的 `define-property`、`with-compile-time-environment`、`module`、`trace-*` 等），作为 stage0 与运行时需要提供的能力清单。
4. 需要对适配文件做的修改，以覆盖库或补丁文件的形式放在子模块之外（例如 `lib/nanopass-overrides/`），不改子模块内容。

## 验收标准
- 子模块就位，提交号已记录。
- 能力清单写在本任务文件末尾，供 iron-016、iron-017 使用。

## 结论（2026-10-08）

### 子模块

- 路径：`IronScheme/IronScheme.Console/lib/nanopass-framework-scheme`
- 上游：https://github.com/nanopass/nanopass-framework-scheme
- 固定提交：`c14d392487886df9275c1d4a3f0f61e1b6c4f2ef`（2026-09-27，"Merge pull request #31 … fix-duplicate-alt-detection"）
- 以 `git submodule add` 加入，`.gitmodules` 与子模块条目已暂存，未提交。

### 库搜索

- IronScheme 库扩展名按顺序为 `.ironscheme.sls`、`.sls`、`.ss`（`psyntax/main.sls:316`、`psyntax/library-manager.sls:91-93`）。
- 控制台用 `-I <目录>` 增加搜索路径（`IronScheme.Console/Program.cs:101-120`）。
- 所以加上 `-I …/lib/nanopass-framework-scheme` 后，`(nanopass)` 解析到 `nanopass.ss`，`(nanopass implementation-helpers)` 优先选中 `nanopass/implementation-helpers.ironscheme.sls`。

### 在旧系统上的实测

在 `legacy-stage0/` 上运行研究笔记 `nanopass.md` §8 的 `remove-when` 示例：
`(lambda (a) (call f (if a '1 '#f)))`，与 Chez 结果一致，总耗时约 2.8 秒（含加载编译 nanopass）。**适配文件无需任何修改**，子模块目录也没有被写入编译产物。

### nanopass 需要宿主提供的能力（供 iron-016、iron-017）

适配文件 `implementation-helpers.ironscheme.sls` 导入 `(rnrs)`、`(rnrs eval)`、`(ironscheme)`、`(ironscheme core)`、`(ironscheme clr)`、`(ironscheme reader)` 与 `(nanopass syntactic-property)`，用到：

| 能力 | 用途 |
|---|---|
| `gensym`（接受字符串参数）、`ungensym` | `gensym?`、`regensym` |
| `format`、`printf`、`pretty-print`、`error`、`warning` | `errorf`、`warningf`、调试输出 |
| `make-parameter` | `optimize-level`、`provide-full-source-information` |
| 记录（`define-record-type`，含 `nongenerative`、`sealed`、`protocol`） | `define-nanopass-record`、`source-information` |
| `syntax-case`、`with-syntax`、`datum->syntax`、`identifier-syntax` | 各种宏 |
| `hashtable-set!`、`hashtable-ref` | eq 哈希表 |
| `symbol-value`、`set-symbol-value!` | `define-property`、`with-compile-time-environment` |
| `syntax-property-set!`、`syntax-property-get`（来自 `(nanopass syntactic-property)`） | 编译期属性 |
| psyntax 内部：`stx?`、`stx-expr`、`annotation?`、`annotation-source` | `syntax->source-information` |
| **`(clr-static-call IronScheme.Runtime.Builtins SourceLocation …)`** | 源位置换算。**直接引用旧运行时的类型名**：新运行时要么提供同名类型与方法，要么在子模块之外放一个覆盖用的 `implementation-helpers.ironscheme.sls`（搜索路径排在子模块之前） |
| `trace-lambda`、`trace-define` 等、`module`、`make-compile-time-value` | 由适配文件导出，来自 `(ironscheme)` 系列库 |

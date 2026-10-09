# 随附的第三方代码

## 标准库 `(ironscheme std …)` 中的参照实现

`ironscheme/std/` 下的库由 SRFI 参照实现与 pfds 改写而来（designs/08-std-library.md，iron-041 ~ iron-046）。每个库的文件头写明出处、原作者与许可，许可证全文在 `ironscheme/std/LICENSES/`。改写所依据的上游版本：

| 来源 | 内容 | 上游 | 依据的提交 |
|---|---|---|---|
| chez-srfi | SRFI 的 R6RS 可移植实现（含各 SRFI 的参照实现与测试） | https://github.com/IronScheme/chez-srfi | `6804f60f2acc319f5c5686da80b519ee56984ea0` |
| pfds | 纯函数式数据结构：队列、双端队列、平衡树、集合、手指树、堆、HAMT 等 | https://github.com/IronScheme/pfds | `7a945ce18cb70630d3140cdff4d33605c37f1273` |

这两者在 iron-040 中从子模块改为普通目录 `srfi/`、`pfds/`，iron-046 删除：`(srfi …)`、`(pfds …)` 库名不再提供，对照表见 designs/08 §3。

## 其他

- `nanopass-framework-scheme/`：git 子模块（编译器的构建依赖，见 designs/03-compiler.md）。
- `wak/`：foof-loop、fmt、riastreams、trc-testing 等（Andreas Rottmann 的 R6RS 移植），许可证文件（`LICENSE.*`）在 `wak/` 目录中。

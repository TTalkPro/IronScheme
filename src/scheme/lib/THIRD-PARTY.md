# 随附的第三方库

以下库原为 git 子模块，2026-10-09 起直接纳入本仓库（iron-040），按原许可证分发，各自目录中保留其许可证文件。

| 目录 | 内容 | 来源 | 纳入时的提交 |
|---|---|---|---|
| `srfi/` | SRFI 的 R6RS 可移植实现（chez-srfi），库名形如 `(srfi :1 lists)` | https://github.com/IronScheme/chez-srfi | `6804f60f2acc319f5c5686da80b519ee56984ea0` |
| `pfds/` | 纯函数式数据结构（Purely Functional Data Structures in Scheme）：队列、双端队列、平衡树、集合、手指树、堆、HAMT 等 | https://github.com/IronScheme/pfds | `7a945ce18cb70630d3140cdff4d33605c37f1273` |

纳入时去掉了 `srfi/` 自带的 `.gitignore`（其中 `and-let*.sls` 一条会通配到上游实际跟踪的 `%3a2/and-let%2a.sls`）和上游的 CI 配置 `.github/`，其余文件未改动。

`nanopass-framework-scheme/` 仍是 git 子模块（编译器的构建依赖，见 designs/03-compiler.md）。

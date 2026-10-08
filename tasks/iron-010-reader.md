# iron-010 手写 reader

- 里程碑：M1　依赖：iron-005、iron-007　状态：未开始
- 设计依据：[02 §8](../designs/02-runtime.md)

## 目标
用手写递归下降 reader 取代 gplex/gppg 生成的分析器，使构建不再依赖 BuildTools。

## 工作内容
1. R6RS 第 4 章数据语法全集（注释、指令、字面量、数字、字符、字符串、字节向量、缩写）。
2. 数字解析覆盖精度前缀、基数、有理数、复数、`+inf.0`/`+nan.0`，与旧系统 `string->number` 行为对照。
3. `read-annotated`：带源位置的注解对象，结构与 psyntax 期望一致（对照 `IS/Runtime/psyntax/AnnotatedReader.cs`）。
4. 错误通过钩子报告 `lexical-error`。

## 验收标准
- 用旧系统的 `tests/r6rs/reader.sls` 用例与 `clisp-number-tests.sps` 中的数字字面量做对照测试。
- 能读完 `build/`、`psyntax/`、`lib/` 下全部源文件，且结果与旧 reader 一致（写一个对照工具）。

# R6RS 差异笔记（排除 call/cc）

日期：2026-10-09。基线：master 分支实测 `tests/r6rs/run.sps`，8973 项中 3 项失败。

## 实测的 R6RS 偏离（去掉 call/cc 后剩 2 项）

### ① 字符串端口的 `get-line` 吞掉了 `\r`

来源：`tests/r6rs/io/ports.sls:504`。

```scheme
(open-string-input-port "appλe\r\nban")
(get-line p)  ;; 实测 "ppλe"，R6RS 期望 "ppλe\r"
```

字符串端口不做 EOL 转换，`get-line` 应停在 `\n` 并保留前面的 `\r`。当前实现把它当文本行尾处理了。这是纯 R6RS 语义的 bug，与 call/cc 无关。

### ② 文件输出端口不遵守 `buffer-mode 'none`

来源：`tests/r6rs/io/ports.sls:288`。

```scheme
(open-file-output-port "io-tmp1" (file-options no-create) 'none)
(output-port-buffer-mode p)  ;; 实测 'line，期望 'none
```

`'line` 和 `'block` 都能正确回报，只有 `'none` 落回 `'line`。文本/文件端口 IO 层的独立缺陷。

### ③ dynamic-wind 重入（call/cc 连带项，不在本笔记范围）

续延重入的 `(out in out in)` 用例，因只支持逃逸续延而失败。见 `designs/06-r6rs-and-testing.md` §1。

## 设计文档承认的非 call/cc 偏离

来源：`designs/06-r6rs-and-testing.md` §1。

### ④ try/finally 区域内不是真尾调用

CIL 限制（`designs/03-compiler.md` §5）。`guard` 体、`dynamic-wind` 的 thunk、`try-finally` 节点内的尾位置调用会增长栈。R6RS 对 proper tail recursion 用的是 "should" 而非 "shall"，不是一致性硬违规，但深递归场景（guard 包着的自尾递归循环）有栈溢出风险。

### ⑤ guard 无匹配子句时再抛出的动态环境

保留 psyntax 派生行为（在 guard 的动态环境中 `raise-continuable`），新老系统一致。属于 R6RS 灰色地带的既定选择，不是回归。

## 不属于 R6RS 差异的项

06 文档偏离表里剩下的几行是 IronScheme 私有扩展的取舍，与 R6RS 符合性无关：

| 项 | 性质 |
|---|---|
| 记录生成 CLR 类型 | 扩展丢失；R6RS 记录语义本身完整（`define-record-type` 全支持） |
| `define-clr-class` | 扩展丢失，编译为运行时报错；`lib/` 中无使用者 |
| `step-into` 调试器 | 依赖 DLR 的扩展，调用时报不支持 |
| FFI | 反倒是改善：`dlopen`/`dlsym` 改用 `NativeLibrary`，不再限 Windows |

## 结论

排除 call/cc 后，与 R6RS 的差异收敛到：两处文本/文件端口 IO 语义缺陷（①②）+ try 区域内尾调用保证（④）+ guard 再抛出环境这个 psyntax 传统行为（⑤）。数值塔（bignum/有理数/复数/精确性）、Unicode、bytevectors、哈希表、枚举、条件系统、`eval`/`environment`、`syntax-case` 全部完整保留（实测 8970/8973 通过）。

①②两处失败看起来同属文本端口的行读取/缓冲模式处理代码，修复范围集中，是冲 R6RS 100% 的切入点。

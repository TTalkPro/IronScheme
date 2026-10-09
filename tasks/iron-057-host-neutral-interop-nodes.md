# iron-057 互操作节点改 `host-*`，codegen 加 `target` 参数

- 里程碑：后续　依赖：iron-056（不是硬依赖，但先做 056 可减少受影响的源码）　状态：未开始
- 设计依据：[11 §2](../designs/11-portability.md) D6、§3；[11 §1](../designs/11-portability.md) D5 的 `(target-host-type)`

## 目标
把 CLR 形状从编译器前端赶出去：L0 ~ L3 的互操作节点改为宿主中性的名字，codegen 通过 `target` 参数查机器描述表取运行时类名、是否发 `tail.` 和内联模板。现在只有一个表项 `clr`，生成的 Lcil 不变。

## 工作内容
1. **L0 节点改名**（`compiler/languages.sls`、`parse.sls`）：`clr-call` → `host-call`、`clr-static-call` → `host-static-call`、`clr-new` → `host-new`、`clr-is` → `host-is`、`clr-cast` → `host-cast`、字段 / 属性 / 索引器 / 事件各形式同理；节点内容（类型名、成员名、参数类型列表）不变。`(ironscheme clr)` 的宏仍展开为 `clr-call-internal` 等，parse-core 把它们解析为 `host-*` 节点；ffi 与 pinvoke 节点同样改名。
2. **各 pass 透传**：`front.sls`、`closures.sls` 中列出互操作节点的 `nanopass-case` 改名。
3. **codegen 的 `target` 参数与机器描述表**（`codegen.sls` 新增 `targets.sls`）：一张 alist / 记录，表项 `clr`：
   - 运行时类名（`IronScheme.Core.Procedure`、`VariadicProcedure`、`Box`、`MultipleValues`、`AsyncFrame`、模块与常量类的基类与接口名）；
   - 基本类型名（`System.Object`、`System.Int32`、`System.String` …）与装箱方式；
   - `tail-calls?`（`clr` 为 `#t`）；
   - 原语内联模板的来源（现为 `primitives.ss` 的模板名）。
   codegen 里所有写死的类名与 `tail.` 判断改为查表；`(ironscheme compiler)` 的驱动接受 `target` 参数，缺省 `clr`。
4. **`(target-host-type)`**（11 D5）：展开期可用的过程，返回当前编译的 `target`；`cond-expand` 的宿主特性改由它给出（不交叉编译时与 `(host-type)` 相同）。
5. **`host-*` 节点在 codegen 的解析**仍是现在的 CLR 实现（`EmitInterop` 静态解析），只是入口按 `target` 分派。
6. 更新 [03 §2、§7](../designs/03-compiler.md)、[02 §9](../designs/02-runtime.md)、[11 §0](../designs/11-portability.md)。

## 验收标准
- 编译整个种子得到的 `.lcil` 与改动前逐字相同（快照测试），boot 镜像字节相同；自举不动点不变。
- `grep -rn "clr-" src/scheme/lib/ironscheme/compiler` 只剩 parse-core 中从 `clr-*-internal` 到 `host-*` 的映射。
- `(compile-file … 'target 'clr)` 可用；给未知目标报清楚的错误。

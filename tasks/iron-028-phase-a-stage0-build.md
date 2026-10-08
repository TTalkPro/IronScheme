# iron-028 Phase A：stage0 编译出新 boot 镜像

- 里程碑：M5　依赖：iron-027、iron-021、iron-017　状态：未开始
- 设计依据：[05 §3](../designs/05-bootstrap.md)

## 目标
在 stage0 上运行新编译器，产出只引用 IronScheme.Core 的 stage1 boot 镜像。

## 工作内容
1. 构建脚本 `ironscheme-buildscript-nano.sps`：在 `seed-buildscript.sps` 基础上，`scheme-library-files` 加入编译器与 nanopass 的库（它们要进入 boot 镜像），`library-legend` / `identifier->library-map` 相应补充；最后一步调用新编译器生成 Lcil。
2. stage0 执行：种子 → 展开 boot 源文件、编译器、nanopass → 编译成 `boot.lcil`。
3. `iron-emit boot.lcil -o ironscheme.boot.dll`；ILVerify。
4. 检查产物的程序集引用中不含 `IronScheme.Scripting`、旧 `IronScheme`、`IronScheme.Closures`。
5. 记录耗时与 Lcil / dll 规模。

## 验收标准
- stage1 boot dll 生成且 ILVerify 通过；引用检查通过。

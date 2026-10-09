# iron-037 compile-file 与 .fasl

- 里程碑：M8　依赖：iron-035　状态：完成
- 设计依据：[07 §2](../designs/07-tooling-and-embedding.md)

## 目标
照 Chez 提供 `compile-file`、`compile-library`、`compile-program`，产物为 `.fasl`，`load` 与宿主可直接加载。

## 工作内容
1. 编译驱动：一个文件的全部顶层形式（库、顶层程序、交互环境顶层形式）编译为一个程序集，写为 `.fasl`。
2. `load` 与宿主识别 `.fasl`；库查找优先使用不旧于源文件的 `.fasl`。
3. 交互环境顶层定义在加载时重新登记。
4. 测试：三种形式编译、加载、结果与源码加载一致；ILVerify。

## 验收标准
- `(compile-file "a.ss")` 后 `(load "a.fasl")` 与 `(load "a.ss")` 行为一致；`IronScheme.Host a.fasl` 可运行编译后的程序。

## 结论（2026-10-09）

完成，见 07 §2。

接口在 psyntax main，经 `(ironscheme)` 导出：
- `compile-file`、`compile-library`、`compile-program`；
- 参数 `compile-imported-libraries`。

产物 `.fasl` 是一个程序集，入口返回 `(ironscheme-fasl 1 libraries …)` 或 `(ironscheme-fasl 1 program 依赖 thunk)`：
- `load` 与宿主（`IronScheme.Host a.fasl 参数…`）按扩展名识别；
- 导入库时优先使用源文件旁不旧于源文件的 `.fasl`；
- 编译后的程序加载时核对依赖库的 id，不符时报"requires a different compilation of a library"，与 Chez 相同。

与任务原计划的差异：本系统的 `load` 只接受以 `(import …)` 开头的顶层程序（程序体中可以有 `library` 形式），不存在"交互环境顶层形式"的文件。因此 `compile-file` 按首个形式分派：库文件同 `compile-library`，否则同 `compile-program`。工作内容第 3 项（交互环境顶层定义重新登记）不适用。

其他修改：
- 内部生成库 dll 的驱动改名为 `compile-library-dll`，名字让给 Chez 接口；
- 新增原语 `load-fasl`，按字节加载、不锁文件；
- library-manager 抽出 `library-content`、`source-libraries`；
- `compiled-library-filename?` 识别 `.fasl`。
- 常量表改为 Deflate 压缩后作为程序集的初始化数据嵌入，不再用 base64 字符串（04 §3）：
  - boot 镜像 5.2 MB → 2.0 MB；
  - 示例库的 `.fasl` 265 KB → 22 KB。

测试：新增类别 CompileFile 5 项，覆盖：
- 编译库与程序、宿主运行 `.fasl` 并传参；
- 源码导入时使用 `.fasl`、`compile-file` 分派；
- `compile-imported-libraries` 与过期检测；
- REPL 中 `load` 库 `.fasl`；
- ILVerify。

全部测试通过：Core.Tests 210/210，IronScheme.Tests 45/45（含自举不动点）。种子已按当前源码再生成，新宿主与 stage0 产物相同。

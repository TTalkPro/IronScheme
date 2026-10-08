# iron-008 迁移运行时库

- 里程碑：M1　依赖：iron-005、iron-006、iron-007　状态：完成
- 设计依据：[02 §5、§10](../designs/02-runtime.md)

## 目标
把旧运行时中 R6RS 所需的 C# 部分复制改写到 IronScheme.Core，去掉 DLR 依赖。

## 工作内容
1. 数值：`Numbers`、`BigFraction`、`ComplexFraction`、`Complex64`（从 DLR 移入）。
2. 列表、向量、字节向量、字符串与 Unicode、哈希表（含 `HashtableEx` 等）、相等性、条件、I/O 与端口（`R6RS/IO.cs` 等）、环境相关原语。
3. `[Builtin]` → `[Primitive]`，补充 `Pure`、`AllowTailCall`、`Inline` 元数据；`[InlineEmitter]` 只保留非内联后备方法。
4. `PrimitiveRegistry`：启动时登记全部原语到符号值槽（不在运行时生成 IL）。
5. 删去 BinaryFormatter 序列化与调试钩子相关代码（另有任务）。

## 验收标准
- Core 中不出现 `Microsoft.Scripting` 与 `IronScheme.Runtime` 命名空间的引用。
- 原语数量与旧系统 `[Builtin]` 对照表一致（差异逐项说明）。
- 数值、字符串、哈希表、端口的单元测试通过。

## 进度（逐步更新）

迁移方式：在 `IronScheme.Core` 中保留 `Builtins` 部分类（Scheme 源码有 `(clr-static-call Builtins …)` 的直接调用），旧文件复制后机械改写：命名空间改为 `IronScheme.Core`、`[Builtin(…, AllowConstantFold = true)]` → `[Primitive(…, Flags = PrimitiveFlags.Pure)]`、`RuntimeHelpers.Int32ToObject` → `RT.Box`、带类型参数的原语改为 `object` 参数并在方法内转换、删去 `[InlineEmitter]` 方法（由编译器内联模板取代）。

Scheme 源码按名字使用的 IronScheme 自有类型与成员（兼容面，迁移时保持同名）：
`Annotation`、`Builtins`（`ExactCompare`、`InexactCompare`、`ListToVector`、`SetSymbolValueFast`、`StringToList`、`ApplicationDirectory`）、`Callable`（`Arity`、`Form`、`AllowConstantFold`，在 iron-013 中改到 `Procedure`）、`Complex64`、`ComplexFraction`、`Cons`、`CustomBinary*Stream`、`CustomText*`、`Exceptions`、`Fraction`、`Hashtables`（`FromNull`、`ToNull`）、`HashtableEx`、`ReadOnlyHashtable`、`Helpers`（`GetTypeFast`、`LongToBignum`、`MakeProcess`、`StartProcess`）、`IntX`、`MultipleValues`、`NonBufferedTranscodedReader`、`RecordTypeDescriptor`、`RecordConstructorDescriptor`、`SchemeChar`、`SchemeException`、`SourceSpan`、`StringWriter`、`SymbolId`/`SymbolTable`（改为 `Symbol`）、`Transcoder`、`TranscodedReader`/`TranscodedWriter`。

| 步骤 | 内容 | 状态 |
|---|---|---|
| H | `PrimitiveRegistry`：扫描 `[Primitive]`、按参数个数分派重载、`params object[]` 原语、约定检查（参数与返回值必须为 object、同参数个数重载重复）；`PrimitiveProcedure` 不在运行时生成 IL | 完成 |
| A | 数值：`Fraction`、`ComplexFraction`、`Complex64`（从 DLR 移入，资源字符串内联）、`DoubleExtensions`、`Numbers`（13 个原语）；`Builtins` 辅助（`TRUE`/`FALSE`/`Unspecified`、`GetBool`、`Values`、`Requires*`、`GetCaller`）；`Errors.AssertionViolation` 的 who 改为 object | 完成。`string->number` 两个重载依赖 gppg 数字解析器，移到 iron-010；`Helpers.LongToBignum` 随步骤 G |
| B | 列表、向量、相等性、布尔（`Lists`、`Vectors`、`Equality`、`Booleans`，删去内联发射器；`Callable` → `Procedure`，`Procedure` 增加与旧 `Callable.Call` 同名的非虚 `Call` 重载） | 完成 |
| C | 字符串与字符 | 并入其他步骤：C# 侧没有独立的字符串原语（`StringToList` 随 B，`string-split`、`string->xml` 随 G，`StringWriter` 随 F） |
| D | 哈希表（`HashtableEx`、`ReadOnlyHashtable`、`HashComparer`、`Hashtables` 的 3 个原语与 `ToNull`/`FromNull`） | 完成 |
| E | 异常：`Exceptions`（`with-clr-exception-handler` 放行 `ContinuationException`；`GetStackTrace` 去掉 DLR 帧过滤） | 完成。`Conditions.cs` 依赖记录类型，改随 iron-009 移植 |
| F | 端口与 I/O：`IO.cs` 全部（转码器、自定义端口、文件端口，10 个原语）、`StringWriter`、`eof-object`/`eof-object?`；`Builtins` 增加旧 `Glue` 方法的同名转发；`RequiresNotNull<TextWriter/TextReader>` 支持双向端口 | 完成。修正旧缺陷：`open-file-input/output-port` 漏掉"文件已存在 / 被占用"的条件映射。`Ports.cs` 中程序集加载转 iron-021，`read` 等转 iron-010 |
| G | 杂项原语（`Runtime/Misc.cs`）：版本、运行时、命令行、库路径、5 个运行时开关（`RuntimeOptions` 取代 `ScriptDomainManager.Options`）、`void`、`unspecified?`、`with-timeout`、`time-it`、`list*`、`pointer+`、`string-split`、`string->xml`、`open-tcp-input/output-port`，以及非原语的 `MakePrimlocHashtable`、`SetSymbolValueFast`、`ListToByteVector`；`Helpers`：`LongToBignum`、`UnwrapValue`、`WrapValue`、`MakeProcess`、`StartProcess` | 完成，差异见下 |

测试：`PrimitiveRegistryTests`（6 项）、`NumbersTests`（9 项），全部 60 项通过。

### 与旧实现的行为差异

| 原语 | 差异 | 原因 |
|---|---|---|
| `with-timeout` | 超时后不再终止后台线程，只放弃等待并报错 | .NET Core 不支持 `Thread.Abort` |
| `time-it` | 只调用无参 thunk；统计写 `Console.Error` 而非 Scheme 的 `current-error-port` | 旧版按 `Callable.Arity` 决定是否传 Stopwatch，Scheme 源码中只有无参用法；新运行时不经 `Eval` |
| `string-split` | 分隔符生效 | 修正旧缺陷：`del as string[]` 对 `object[]` 总是得到 null，分隔符被忽略 |
| `open-file-input/output-port` | 文件已存在 / 被占用时报对应的 `&i/o-file-*` 条件 | 修正旧缺陷（只写端口版本本来就有这些映射） |
| `GetStackTrace` | 不再过滤 DLR 帧 | DLR 已不存在 |

## 结论（2026-10-08）

### 验收

1. `IronScheme.Core` 中没有 `Microsoft.Scripting`、`IronScheme.Runtime`、`IronScheme.Compiler` 的引用（检查结果 0 处）。
2. 原语对照：旧系统 `[Builtin]` 共 89 个名字，Core 中 `[Primitive]` 共 69 个名字。差异逐项说明：

| 旧系统有、Core 暂无 | 去向 |
|---|---|
| `make-record-type-descriptor`、`make-record-constructor-descriptor`、`record-constructor`、`record-predicate`、`record-accessor`、`record-mutator`、`record-rtd`、`record?`；`condition`、`condition-accessor`、`condition-predicate`、`simple-conditions` | iron-009（记录与条件） |
| `read`、`read-annotated`、`make-annotation`、`string->number` | iron-010（reader 与数字解析） |
| `get-clr-type` | iron-011（互操作） |
| `serialize-port`、`deserialize-port` | iron-020（fasl 取代 BinaryFormatter） |
| `load-library-dll` | iron-021（加载器） |
| `compile-core`、`compile-library`、`compile-bootfile` | iron-027（编译驱动） |
| `lw-debugger`、`lw-debugger-call-stack`、`lw-debugger-location-trace`、`lw-debugger-stackframe-variables`、`disassemble` | **不再支持**：依赖 DLR 调试钩子与 IL 反汇编；设计中调试器列为以后另做（02 §10） |

| Core 有、旧系统 `[Builtin]` 中没有 | 说明 |
|---|---|
| `$set-runtime-hook!`、`$runtime-hooks-missing` | iron-007 新增 |
| `call/cc`、`call-with-current-continuation` | 旧系统同样是原语（两个名字写在同一个属性方括号里，统计脚本未计入） |
| `call-with-values` | 旧系统由编译器专门登记（`OptimizedBuiltins`），不是 `[Builtin]` |
| `set-symbol-value!`、`string->symbol`、`symbol->string` | iron-005 新增为原语。`set-symbol-value!` 在 `build/misc.sls` 中也有定义、`symbol->string` 在 `build/pretty-print.sls` 中出现，iron-013 中决定保留哪一边 |

3. 测试：`IronScheme.Core.Tests` 共 91 项全部通过，本任务新增 `PrimitiveRegistryTests`、`NumbersTests`、`ListsVectorsEqualityTests`、`HashtableTests`、`ExceptionsTests`、`IOTests`、`MiscTests`。

### 文件布局（`IronScheme/IronScheme.Core/`）

| 目录 / 文件 | 内容 |
|---|---|
| `PrimitiveRegistry.cs` | 原语登记表、`PrimitiveProcedure`、`PrimitiveOverload` |
| `Builtins.cs` | `Builtins` 部分类的辅助方法与旧 `Glue` 同名转发 |
| `Numbers/` | `Fraction`、`ComplexFraction`、`Complex64`、`DoubleExtensions`、`Numbers` |
| `Runtime/` | `Lists`、`Vectors`、`Equality`、`Booleans`、`Misc`、`Helpers` |
| `R6RS/` | `Hashtables`、`Exceptions`、`IO`、`Ports` |

### 移植工具

`tools/port-legacy-runtime.py`（不提交）：删除 `BuiltinEmitters` 块、去掉 DLR 与旧编译器的 using、命名空间改为 `IronScheme.Core`、`[Builtin]` → `[Primitive]`（无名者取方法名小写）、`Callable` → `Procedure`、`SymbolTable`/`SymbolId` → `Symbol`、`catch (Continuation)` → `catch (ContinuationException)`。iron-009/010/011 移植时继续使用。

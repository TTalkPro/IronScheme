# 09 C# 代码规范：以微软规范为主的 `.editorconfig` 对照建议

> 状态：**已采纳并落地**（iron-058，2026-10-09）：用户决定缩进改为 4 空格、私有字段改名；§2 的配置即仓库根目录的 `.editorconfig`。§0 的统计是落地前的现状。
> 依据：微软《C# 编码约定》（Common C# code conventions）与《C# 标识符命名规则和约定》（learn.microsoft.com，.NET 文档）、
> 《框架设计准则》（Framework Design Guidelines）、`.editorconfig` 的 .NET 代码样式规则（IDExxxx）与代码分析规则（CAxxxx）。

## §0 现状（2026-10-09 统计，99 个自有 C# 文件，约 1.7 万行；不含第三方的 `src/Oyster.IntX`）

| 项 | 现状 |
|---|---|
| `.editorconfig` | 只有 4 行：`[*]` 空格缩进、`indent_size = 2`、去掉行尾空白；没有 `root = true`，没有任何 C# 规则 |
| 缩进 | 2 空格（97 个文件），1 个文件 4 空格，1 个含制表符 |
| 大括号 | 另起一行（Allman）：2022 处；行尾 53 处，集中在移植来的 `Complex64.cs` |
| 命名空间 | 块式 `namespace X { … }` 95 个，无命名空间 4 个（顶级语句程序） |
| `using` 位置 | 命名空间外 |
| 私有字段命名 | `camelCase`，不带前缀；`_camelCase` 0 处 |
| `this.` | 175 处（多在构造函数里区分同名参数） |
| 访问修饰符 | 显式写 `private` 的只有 6 处，其余私有成员都省略修饰符 |
| `var` | `var` 785 处；内建类型显式写出 353 处 |
| 类型关键字 | `string`/`int` 等关键字 1534 处；`String`/`Int32` 3 处 |
| 单行 `if` 不加大括号 | 约 540 处 |
| 空值比较 | `== null` 123 处；`is null` 0 处 |
| 常量 | PascalCase 27、camelCase 5 |
| 行长 | 超过 120 列 369 行，超过 160 列 28 行 |
| 注释 | 中文 767 行，英文 268 行（英文多为移植来的旧代码） |
| 编码与换行 | UTF-8；3 个文件带 BOM；全部 LF |
| 项目设置 | `Nullable` 与 `ImplicitUsings`：8 个项目 `disable`，示例 WebServer `enable`；`LangVersion latest` |

⚠️ **不能改名的公开字段**：Scheme 源码（`clr-field-get`）和编译器生成的 IL（`ldfld`）按名字访问 17 个公开的小写字段：
`Cons.car` `Cons.cdr`、`Annotation.expression` `source` `stripped`、记录与 RCD 的 `type` `parent` `protocol` `uid` `id`、
端口与转码器的 `codec` `eolstyle` `handlingmode` `input` `output` `native` `operator` 等。
它们不符合微软"公开字段用 PascalCase（且最好不用公开字段）"的建议，但改名会破坏 boot 镜像与已编译的库 ⇒ **列为例外，命名规则不覆盖公开字段**。
反射按名字查找的都是公开成员（`Invoke`、`Instance`、`ReadPackedTable` …），私有字段改名是安全的。

## §1 逐项对照

"差距"指按微软规范要改动的量；"建议"中的严重级别：`warning` 构建时报告（启用 `EnforceCodeStyleInBuild` 后），`suggestion` 只在 IDE 中提示，`silent` 不提示。

| # | 项 | 微软规范 | 现状 | 建议 | 差距 |
|---|---|---|---|---|---|
| 1 | 缩进 | 4 空格 | 2 空格 | **改为 4 空格**（`dotnet format whitespace` 一次完成） | 97 个文件 13580 处空白改动，机械 |
| 2 | 大括号 | 另起一行 | 已是 | 保持，`csharp_new_line_before_open_brace = all` | `Complex64.cs` 一个文件 |
| 3 | 命名空间 | 文件范围 `namespace X;` | 块式 | **改为文件范围**（IDE0161，可自动修复），顺带少一层缩进；命名空间与文件夹不一致是有意的（如 `Numbers/` 下的类型属于 `IronScheme.Core`），关闭 IDE0130 | 95 个文件，机械 |
| 4 | `using` | 放在命名空间外，`System` 排在最前 | 位置已是；26 个文件顺序不符 | 保持并强制（IDE0065），`dotnet_sort_system_directives_first = true` | 26 个文件排序，机械 |
| 5 | 私有/内部实例字段 | `_camelCase` | `camelCase` | **改为 `_camelCase`**；私有/内部静态字段用 `s_camelCase`，线程静态 `t_camelCase` | 实例字段 220 个、静态字段 115 个，在 49 个文件中；半自动（IDE 重命名），逐项目做 |
| 6 | 公开字段 | PascalCase，宜改为属性 | 17 个小写公开字段 | **不改**（见 §0 ⚠️），规则不覆盖公开字段 | 无 |
| 7 | `this.` | 不加（除非必要） | 175 处 | 不加（IDE0003/IDE0009）；第 5 项完成后同名参数的歧义消失，`this.` 自然去掉 | 随第 5 项 |
| 8 | 访问修饰符 | 总是显式写出 | 省略 | **要求显式**（IDE0040，可自动修复） | 68 个文件 641 处，机械 |
| 9 | 类型关键字 | `string` 而非 `String` | 基本已是 | 强制（IDE0049） | 1 个文件 13 处 |
| 10 | `var` | 类型从右边看得出时用 `var`；内建类型写出类型 | 两种混用 | `var_when_type_is_apparent = true`、`var_for_built_in_types = false`、`var_elsewhere = false`，都设为 `suggestion`，不批量改 | 不强制 |
| 11 | 单行 `if` 的大括号 | 无硬性规定（runtime 允许单行省略） | 540 处省略 | `csharp_prefer_braces = when_multiline`：多行必须加，单行可省 | 无 |
| 12 | 表达式体成员 | 单行时可用 | 已大量使用 | 方法 `when_on_single_line`，属性与访问器 `true`，均 `silent` | 无 |
| 13 | 空值检查 | 推荐 `is null` / `is not null` | `== null` | `suggestion`，不批量改（IDE0041） | 不强制 |
| 14 | 其他现代写法 | 对象初始值设定项、集合表达式、模式匹配、`switch` 表达式、`readonly` 字段 | 部分已用 | 均设为 `suggestion`；主构造函数（IDE0290）不是规范要求，设为 `silent` | 不强制 |
| 15 | 常量 | PascalCase | 5 个 camelCase | PascalCase（`warning`） | 5 处 |
| 16 | 接口、类型参数 | `I` 前缀、`T` 前缀 | 已是 | 强制 | 无 |
| 17 | 异步方法 | `Async` 后缀 | 无异步方法 | 规则加上，备将来 | 无 |
| 18 | 行长 | 无硬性上限 | 369 行超过 120 列 | 建议不超过 120 列，不强制（`.editorconfig` 无法可靠检查） | 不强制 |
| 19 | 注释 | 单独成行、`///` 文档注释；不规定语言 | 中文为主 | **保持中文**（项目约定）；公开 API 用 `///` | 无 |
| 20 | 文件格式 | UTF-8、LF（跨平台仓库） | 3 个 BOM | `charset = utf-8`、`end_of_line = lf`、`insert_final_newline = true` | 3 个文件去 BOM，1 个补末尾换行 |
| 21 | 可空引用类型 | 新项目建议启用 | 8 个项目关闭 | **暂不启用**：运行时以 `object` 表示 Scheme 值，`null` 即空表 `'()`，启用要逐个成员标注，属于单独的改造 | 另立任务 |
| 22 | 隐式 `using` | 模板默认启用 | 关闭 | 保持关闭：库与运行时显式列出依赖，便于审阅；示例项目保持模板默认 | 无 |
| 23 | 第三方代码 | 保持原样 | `Oyster.IntX` | `generated_code = true` 排除在样式检查之外 | 无 |
| 24 | 非 C# 文件 | — | 同一份缩进设置 | Scheme 源码（`.sls` `.ss` `.sps` `.scm`）与 Lcil、种子保持 2 空格（Lisp 惯例）；项目文件与 JSON/YAML 2 空格 | 无 |

## §2 建议的 `.editorconfig`

```ini
root = true

# ———————— 全部文件 ————————
[*]
charset = utf-8
end_of_line = lf
insert_final_newline = true
trim_trailing_whitespace = true
indent_style = space
indent_size = 4

# Scheme 源码、Lcil、文本种子：Lisp 惯例 2 空格
[*.{sls,ss,sps,scm,lcil,core}]
indent_size = 2

# 项目文件与数据文件
[*.{csproj,props,targets,slnx,xml,json,yml,yaml}]
indent_size = 2

[*.md]
trim_trailing_whitespace = false

# 第三方代码：不做样式检查
[src/Oyster.IntX/**.cs]
generated_code = true

# ———————— C# ————————
[*.cs]

# 布局（第 1–4 项）
csharp_new_line_before_open_brace = all
csharp_new_line_before_else = true
csharp_new_line_before_catch = true
csharp_new_line_before_finally = true
csharp_indent_case_contents = true
csharp_indent_switch_labels = true
csharp_style_namespace_declarations = file_scoped:warning
csharp_using_directive_placement = outside_namespace:warning
dotnet_sort_system_directives_first = true
dotnet_separate_import_directive_groups = false
dotnet_style_namespace_match_folder = false

# 语言（第 7–14 项）
dotnet_style_qualification_for_field = false:suggestion
dotnet_style_qualification_for_property = false:suggestion
dotnet_style_qualification_for_method = false:suggestion
dotnet_style_qualification_for_event = false:suggestion
dotnet_style_require_accessibility_modifiers = for_non_interface_members:warning
dotnet_style_predefined_type_for_locals_parameters_members = true:warning
dotnet_style_predefined_type_for_member_access = true:suggestion
csharp_style_var_for_built_in_types = false:suggestion
csharp_style_var_when_type_is_apparent = true:suggestion
csharp_style_var_elsewhere = false:silent
csharp_prefer_braces = when_multiline:suggestion
csharp_style_expression_bodied_methods = when_on_single_line:silent
csharp_style_expression_bodied_properties = true:silent
csharp_style_expression_bodied_accessors = true:silent
dotnet_style_prefer_is_null_check_over_reference_equality_method = true:suggestion
csharp_style_pattern_matching_over_is_with_cast_check = true:suggestion
csharp_style_pattern_matching_over_as_with_null_check = true:suggestion
csharp_style_prefer_switch_expression = true:suggestion
dotnet_style_object_initializer = true:suggestion
dotnet_style_collection_initializer = true:suggestion
dotnet_style_readonly_field = true:suggestion
csharp_style_prefer_primary_constructors = false:silent

# 命名（第 5、6、15–17 项）——符号组
dotnet_naming_symbols.interfaces.applicable_kinds = interface
dotnet_naming_symbols.type_parameters.applicable_kinds = type_parameter
dotnet_naming_symbols.types_and_members.applicable_kinds = class, struct, enum, delegate, method, property, event
dotnet_naming_symbols.constants.applicable_kinds = field, local
dotnet_naming_symbols.constants.required_modifiers = const
dotnet_naming_symbols.private_fields.applicable_kinds = field
dotnet_naming_symbols.private_fields.applicable_accessibilities = private, internal, private_protected
dotnet_naming_symbols.private_static_fields.applicable_kinds = field
dotnet_naming_symbols.private_static_fields.applicable_accessibilities = private, internal, private_protected
dotnet_naming_symbols.private_static_fields.required_modifiers = static
dotnet_naming_symbols.async_methods.applicable_kinds = method
dotnet_naming_symbols.async_methods.required_modifiers = async
dotnet_naming_symbols.locals_and_parameters.applicable_kinds = parameter, local

# 命名——样式
dotnet_naming_style.pascal.capitalization = pascal_case
dotnet_naming_style.camel.capitalization = camel_case
dotnet_naming_style.i_prefix.capitalization = pascal_case
dotnet_naming_style.i_prefix.required_prefix = I
dotnet_naming_style.t_prefix.capitalization = pascal_case
dotnet_naming_style.t_prefix.required_prefix = T
dotnet_naming_style.underscore_camel.capitalization = camel_case
dotnet_naming_style.underscore_camel.required_prefix = _
dotnet_naming_style.s_camel.capitalization = camel_case
dotnet_naming_style.s_camel.required_prefix = s_
dotnet_naming_style.async_suffix.capitalization = pascal_case
dotnet_naming_style.async_suffix.required_suffix = Async

# 命名——规则（排在前面的先匹配；公开字段不设规则，见 §0 ⚠️）
dotnet_naming_rule.interfaces.symbols = interfaces
dotnet_naming_rule.interfaces.style = i_prefix
dotnet_naming_rule.interfaces.severity = warning
dotnet_naming_rule.type_parameters.symbols = type_parameters
dotnet_naming_rule.type_parameters.style = t_prefix
dotnet_naming_rule.type_parameters.severity = warning
dotnet_naming_rule.async_methods.symbols = async_methods
dotnet_naming_rule.async_methods.style = async_suffix
dotnet_naming_rule.async_methods.severity = warning
dotnet_naming_rule.constants.symbols = constants
dotnet_naming_rule.constants.style = pascal
dotnet_naming_rule.constants.severity = warning
dotnet_naming_rule.private_static_fields.symbols = private_static_fields
dotnet_naming_rule.private_static_fields.style = s_camel
dotnet_naming_rule.private_static_fields.severity = warning
dotnet_naming_rule.private_fields.symbols = private_fields
dotnet_naming_rule.private_fields.style = underscore_camel
dotnet_naming_rule.private_fields.severity = warning
dotnet_naming_rule.types_and_members.symbols = types_and_members
dotnet_naming_rule.types_and_members.style = pascal
dotnet_naming_rule.types_and_members.severity = warning
dotnet_naming_rule.locals_and_parameters.symbols = locals_and_parameters
dotnet_naming_rule.locals_and_parameters.style = camel
dotnet_naming_rule.locals_and_parameters.severity = suggestion
```

⚠️ 生成代码里的方法名（编译器生成的 `C0`、`Invoke1` 等）不在 C# 源码中，不受影响。
⚠️ 测试中 NUnit 的测试方法名按 PascalCase 已符合；测试数据里的小写 JSON 键是字符串，不受影响。

## §3 验证

§2 的配置已在仓库的临时副本上用 `dotnet format IronScheme.slnx --verify-no-changes --severity info` 实测：配置能被 Roslyn 正确加载，§1 "差距"一列的数字即其报告（另有若干 `info` 级别的代码分析提示，如 CA1822 可改为 `static`，不属于样式规范）。

## §4 落地步骤

每一步单独一次提交，每步之后全部测试与自举不动点照绿（这些改动不改变生成的 IL 语义）。

| 步 | 内容 | 方式 |
|---|---|---|
| ① | 换上 §2 的 `.editorconfig`，构建不强制（`EnforceCodeStyleInBuild` 不开） | 只改配置 |
| ② | 空白与文件格式：4 空格、LF、去 BOM、末尾换行；`Complex64.cs` 的大括号 | `dotnet format whitespace` |
| ③ | 文件范围命名空间（IDE0161）、显式访问修饰符（IDE0040）、`String` → `string`（IDE0049）、常量改名 | `dotnet format style --diagnostics IDE0161 IDE0040 IDE0049`，常量手工 |
| ④ | 私有/内部字段 `_camelCase` / `s_camelCase`，去掉随之多余的 `this.` | IDE 批量重命名，逐项目进行 |
| ⑤ | `Directory.Build.props` 打开 `EnforceCodeStyleInBuild`；CI 加 `dotnet format --verify-no-changes` | 配置 |

不在本次范围：可空引用类型（第 21 项，另立任务）；`var`、`is null`、模式匹配等 `suggestion` 级别的写法不批量改，新代码按提示写。

## §5 决定（已定）

1. **缩进改为 4 空格**（第 1 项）：微软规范如此，但这是对全部 C# 文件的一次性机械改动，`git blame` 会被这一次提交覆盖（可用 `.git-blame-ignore-revs` 忽略该提交）。
2. **私有字段 `_camelCase` / `s_camelCase`**（第 5 项）：335 个字段改名，半自动。
3. 第 21、22 项（可空引用类型、隐式 `using`）按上面的建议暂不跟随微软默认。

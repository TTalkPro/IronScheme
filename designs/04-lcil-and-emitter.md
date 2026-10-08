# 04 Lcil 与发射器

## 1. 为什么用文本 Lcil

- **编译器（Scheme）与发射器（C#）解耦**：发射器不依赖任何一版 Scheme 运行时的对象模型（旧的 `SymbolId`/`Cons`，新的 `Symbol`/`Cons`），只读文本。
- **与宿主隔离**：编译器无论跑在 stage0 解释器上还是编译后的新系统里，输出都只经文本，解释器或宿主的内部对象不会混进目标程序集。
- **可验证**：文本可 diff，自举不动点先比较 Lcil 文本，再比较二进制。
- 代价：eval 时多一次序列化和解析。可接受；以后可以加一条在新运行时内直接传递数据结构的快速路径。

## 2. Lcil 文本格式（第 1 版，iron-018 冻结）

### 2.1 词法

S 表达式，UTF-8。发射器自带读取器（`IronScheme.Emit.SExpr`），只认以下数据：

| 数据 | 写法 |
|---|---|
| 列表 | `( … )`，方括号 `[ … ]` 等同圆括号 |
| 符号 | 除空白、括号、`"`、`;` 以外的字符序列，且不是数 |
| 字符串 | `"…"`，转义 `\" \\ \n \r \t` 与 `\xHH;`（码点） |
| 整数 | 十进制，可带符号，64 位以内；`#x…` 十六进制 |
| 浮点 | 十进制小数或指数形式；常量中的 flonum 另用位模式（§3） |
| 布尔 | `#t` `#f` |
| 注释 | `;` 到行尾、`#| … |#` |

### 2.2 顶层结构

```scheme
(lcil 1
  (assembly "名字"
    (references "IronScheme.Core" …)       ; 可选：额外引用的程序集（按名字或路径加载）
    (entry "入口类型" "入口方法"))            ; 可选：入口（§6）
  (constants (0 编码) (1 编码) …)            ; 可选：常量表（§3），下标从 0 连续
  (type …) …)
```

`(lcil 1 …)` 的版本号不是 1 时报错。顶层各子句顺序任意，`assembly` 必须且只能有一个。

### 2.3 类型、字段、方法

```scheme
(type "名字" (base "基类型")? (attrs 属性…)? (interfaces "接口" …)?
  (field "名字" "类型" 属性…)                      ; 属性：static public private readonly
  (method "名字" (attrs 属性…)
    (params "类型" …) (ret "类型")
    (locals "类型" …)?                             ; 局部变量按下标 0.. 编号
    (clr-namespaces "命名空间" …)?                 ; 互操作类型名的查找前缀（§5）
    (source "文件")?                               ; 序列点所属文档
    (body 指令 …)))
```

- 类型名可含 `.`（命名空间）与 `$`、`#` 等字符；嵌套类型不支持。类型属性：`public`（默认）`sealed` `abstract` `interface`。`base` 缺省为 `System.Object`。
- 方法属性：`static`、`virtual`、`override`（= virtual + 复用基类槽位）、`abstract`、`public`（默认）、`private`、`ctor`（实例构造函数，名字须为 `.ctor`，不写 `ret` 类型）、`cctor`（类型初始化器，名字 `.cctor`）。
- 实例方法的 `ldarg 0` 是 `this`，`params` 只列显式参数。
- 构造函数体须自己调用基类构造函数（`(ldarg 0) (call "System.Object" ".ctor" () "System.Void")`）。

### 2.4 类型引用

字符串 `"T"`：

1. 本 Lcil 中定义的类型名；
2. 否则按全名在已加载程序集与 `references` 中查找（`System.Object`、`IronScheme.Core.Procedure`）；
3. 后缀 `[]` 表示一维数组，`&` 表示按引用（只用于参数）；
4. `System.Void` 只用于返回类型。

方法引用写参数类型列表以选择重载：`"T" "名字" ("P" …) "R"`；返回类型 `R` 用于核对（不匹配报错）。构造函数名为 `.ctor`。字段引用：`"T" "名字"`。

### 2.5 指令

**普通 CIL 指令**：凡 `System.Reflection.Emit.OpCodes` 中的指令都可按其名字书写（小写、带点，如 `(add)` `(conv.i4)` `(ldelem.ref)` `(ceq)`），操作数按指令类型：

| 操作数 | 写法 | 例 |
|---|---|---|
| 无 | — | `(add)` `(dup)` `(pop)` `(ret)` `(throw)` `(rethrow)` `(ldnull)` |
| 整数 | `n` | `(ldc.i4 3)` `(ldc.i8 1)` |
| 浮点 | `x` | `(ldc.r8 1.5)` |
| 字符串 | `"s"` | `(ldstr "abc")` |
| 参数 / 局部变量下标 | `i` | `(ldarg 1)` `(starg 0)` `(ldloc 2)` `(stloc 0)` `(ldloca 0)` |
| 标签 | `L`（符号） | `(br L1)` `(brtrue L2)` `(beq L3)` `(leave L4)` |
| 类型 | `"T"` | `(castclass "T")` `(isinst "T")` `(box "T")` `(unbox.any "T")` `(newarr "T")` |
| 字段 | `"T" "f"` | `(ldfld "T" "f")` `(stsfld "T" "f")` |
| 方法 | `"T" "m" ("P"…) "R"` | `(call …)` `(callvirt …)` `(ldftn …)` |
| 构造函数 | `"T" ("P"…)` | `(newobj "T" ("P"…))` |

- 短格式（`ldarg.0`、`br.s`、`ldc.i4.s` …）不必写，发射器自动选择；写了也接受。
- `(tail)` 是 `tail.` 前缀，必须紧接 `call`/`callvirt`，其后必须是 `ret`。

**伪指令**：

| 伪指令 | 含义 |
|---|---|
| `(label L)` | 定义标签；每个方法内唯一 |
| `(ldconst k)` | 载入常量表第 k 项（§3） |
| `(try (body 指令…) (catch "T" 指令…)… (finally 指令…)?)` | 结构化异常；至少一个 catch 或 finally。catch 块入口栈上是异常对象。各块末尾的 `leave` / `endfinally` 由发射器加入；块内也可显式 `leave` 到块外的标签。进入 try 时求值栈须为空 |
| `(line l1 c1 l2 c2)` | 后续指令的源位置（序列点），需方法有 `source` |

**互操作指令**（由发射器决议，§5）：参数事先按 `object` 压栈。

| 指令 | 栈 | 说明 |
|---|---|---|
| `(clr-call T 成员 static? argc)` | 实例？参数×argc → 结果 | `T` 为类型名字符串，或 `#f` 表示按实例的运行时类型；成员为 `"名字"`、`("名字" ("P"…))`（指定参数类型）或 `("名字" ("P"…)|#f ("G"…))`（泛型方法，`#f` 表示参数类型按实参推断；泛型方法总由运行时决议）；`static?` 为 `#t` 时无实例 |
| `(clr-field-get T "f" static?)` | 实例？→ 值 | |
| `(clr-field-set T "f" static?)` | 实例？值 → unspecified | |
| `(clr-new T argc)` | 参数×argc → 对象 | |
| `(clr-new-array T)` | 长度 → 数组 | |
| `(clr-cast T)` `(clr-is T)` | 值 → 值 / 布尔 | |
| `(clr-type T)` | → `System.Type` | |

结果一律为 Scheme 表示（`object`），与运行时 `Interop` 的转换规则一致。

### 2.6 校验（读取时报错，带行列）

未知指令或操作数个数 / 类型不对；标签重复或未定义；参数、局部变量下标越界；`ldconst` 越界；`(tail)` 后不是调用或调用后不是 `ret`；常量下标不连续；类型或成员找不到（发射时报错）。

## 3. 常量编码（iron-020 实现）

编译器（`(ironscheme compiler constants)` 的 `encode-constants`）把每个常量写成中立的结构化编码，不依赖宿主的 `write`：

| 编码 | 含义 |
|---|---|
| `(nil)` `(true)` `(false)` `(unspecified)` `(eof)` | 单例 |
| `(fix n)` `(big "十进制")` `(rat "n/d")` `(flo "位模式")` `(cpx 实 虚)` | 数值；flonum 为 IEEE 位模式的 16 位十六进制（大端），保证往返精确（含 `-0.0`、NaN） |
| `(chr n)` `(str "…")` `(mstr "…")` | 字符（码点）、不可变 / 可变字符串 |
| `(sym "name")` | 符号（含 gensym），运行时按名字驻留；`(gensym "…")` 为同义写法 |
| `(pair a d)` `(list e …)` `(dlist e … 表尾)` `(vec e …)` `(bv "十六进制")` | 序对与表（未被共享的表尾序对连成 `list`/`dlist`，避免长表深度嵌套）、向量、字节向量 |
| `(rtd "名字" uid 父 sealed? opaque? ((mutable\|immutable "字段") …))` | 记录类型；uid 为 `(sym …)`（非生成性）、`(str …)` 或 `(false)`（生成性）；父为编码或 `(false)` |
| `(rec rtd f …)` | 记录（含简单条件） |
| `(cnd 简单条件 …)` | 复合条件 |
| `(ann 表达式 源位置 剥离后的表达式)` | reader 注解 |
| `(eqht 键 值 …)` | eq 哈希表（psyntax 的 rib 索引用它）；条目按键（符号、字符串、定长整数的文本）排序，保证确定 |
| `(def n x)` / `(ref n)` | 共享与环（`eq?` 同一对象只编码一次，编号在整张常量表内统一） |

- **发射器**（`FaslEncoder`）把编码转成二进制 fasl（标签字节 + 内容；计数为 7 位变长整数；字符串为 UTF-16 码元），整张表编码成一个向量，以 base64 字符串放进保留类型 `$Constants` 的类型初始化器：`$Constants.c = Fasl.ReadTable("…")`。`(ldconst k)` 即 `ldsfld $Constants::c; ldc.i4 k; ldelem.ref`，Lcil 中也可直接写 `(ldsfld "$Constants" "c")`。不用托管资源：内存模式的程序集不能带资源，用字符串两种模式一致。
- **运行时** `IronScheme.Core.Fasl`：`Read` 重建对象（复合对象先登记再读子项，环才能指回自己），非生成性 RTD 经 `make-record-type-descriptor` 按名字 + uid 取回已登记的同一对象，生成性 RTD 在同一次读取内经 def/ref 共享；`Write` 把对象直接写成同一格式（`serialize-port`/`deserialize-port` 使用）。
- psyntax 的语法对象（`stx` 记录，含 mark、rib 与 rib 的 eq 哈希表）可完整往返：解码后 `syntax-case`、`free-identifier=?`、`bound-identifier=?` 与 `eval` 都正常（`compiler/tests/constants-roundtrip.sps`）。
- 无法编码的对象（自定义哈希函数的表、过程、端口等）报错。

## 4. 发射器 IronScheme.Emit

| 项 | 决定 |
|---|---|
| 项目 | `IronScheme/IronScheme.Emit/`，net10.0，只依赖 BCL；对 `IronScheme.Core` 的引用**按名字解析**（运行时加载），不做项目引用 |
| 输入 | Lcil 文本（自带一个极简 S 表达式读取器，不依赖 Scheme reader） |
| 输出模式 | **持久化**：`PersistedAssemblyBuilder`（.NET 9+）→ `GenerateMetadata` + `ManagedPEBuilder`（可加托管资源与 Portable PDB；iron-003 已验证）；**内存**：`AssemblyBuilder.DefineDynamicAssembly(…, RunAndCollect)`，用于 `eval` |
| 两种形态 | 库 API `LcilEmitter.Emit(string lcil, EmitMode)`；命令行 `iron-emit in.lcil -o out.dll`（交叉自举阶段使用） |
| 校验 | 发射后可选跑 `ILVerify`（.NET 自带的 IL 校验器，dotnet 工具形式） |
| 调试信息 | `(line …)` → 序列点；持久化模式生成 Portable PDB。第一版可选 |
| 确定性 | 类型、方法、常量顺序完全按 Lcil。PersistedAssemblyBuilder 每次生成随机 MVID，COFF 时间戳也随之变化（iron-003 实测）。**保存后回填**：把 MVID 与时间戳清零、算 SHA256、用哈希回填；实测处理后逐字节一致且可正常加载。同时生成 PDB 时 PDB ID 需一并处理，或自举构建不生成 PDB |

## 5. 互操作指令的决议

发射器手里有真实的 `Type`，按以下规则决议：

1. 类型名：先按全名查，再按方法级 `clr-namespaces` 列表逐个前缀查，在 `clr-references` 及已加载程序集中找。
2. 成员：按名字和参数个数过滤；**唯一**时直接生成 `call`/`callvirt`，参数从 `object` 做必要转换（`unbox.any`、`castclass`，或调用 `Interop.Convert<T>`），返回值装箱或转换（`void` → 未指定值）。
3. 不唯一或找不到：生成对 `Interop.Call` 等运行时方法的调用（02 §9），运行时按实际参数类型决议并缓存。
4. 字面常量字段（`const`）直接内联值。

## 6. 程序集结构与加载约定

- 每个程序集有一个入口：Lcil 的 `(entry "类型" "方法")`，入口须为 `public static object 方法()`（发射时校验）。boot 镜像约定为 `#Module::Initialize`，库为按库名生成的类型。
- 程序集级属性 `[IronScheme.Core.SchemeModule("入口类型", "入口方法")]` 标明入口（iron-021 用类型名字符串而非 `typeof`：内存模式要在定义类型前写属性），加载器不再按 `CustomSymbolDictionary` 搜索。
- 加载（`IronScheme.Core.ModuleLoader`）：`LoadModule(路径, inMemory)` → `LoadAssembly`（`~/` 前缀为运行时目录；`inMemory` 时按字节加载并带上修改时间相近的 .pdb）→ 读属性 → 调入口；内存模块（eval）由发射器给出 `Assembly`，调 `Run(asm)`。
  - boot 镜像：执行全部顶层代码，登记钩子与库。
  - 库：返回 13 元素列表，交给 psyntax 的 `try-load-from-file` 安装；原语 `load-library-dll` 即 `LoadModule`。
- 库 dll 文件名沿用 `library-name->dll-name`（`Console/psyntax/library-manager.sls:132-162`）。
- 每个 lambda 一个类会产生大量类型：boot 镜像预计数千个。这是 .NET 能承受的规模（Kotlin、F# 等也如此），先不优化。

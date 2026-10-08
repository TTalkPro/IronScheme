# 04 Lcil 与发射器

## 1. 为什么用文本 Lcil

- **编译器（Scheme）与发射器（C#）解耦**：发射器不依赖任何一版 Scheme 运行时的对象模型（旧的 `SymbolId`/`Cons`，新的 `Symbol`/`Cons`），只读文本。
- **与宿主隔离**：编译器无论跑在 stage0 解释器上还是编译后的新系统里，输出都只经文本，解释器或宿主的内部对象不会混进目标程序集。
- **可验证**：文本可 diff，自举不动点先比较 Lcil 文本，再比较二进制。
- 代价：eval 时多一次序列化和解析。可接受；以后可以加一条在新运行时内直接传递数据结构的快速路径。

## 2. Lcil 文本格式

S 表达式，UTF-8。顶层结构：

```scheme
(lcil 1                                   ; 格式版本
  (assembly "ironscheme.boot"
    (references "IronScheme.Core")        ; 额外引用的程序集
    (entry "#Module" "Initialize"))
  (constants                              ; 常量表，见 §3
    (0 (sym "car"))
    (1 (pair (fix 1) (pair (str "a") (nil)))))
  (type "#Module" (base "System.Object") (attrs public abstract sealed)
    (field "c$" (type "System.Object[]") static)
    (method "Initialize" (static) (params) (ret "System.Object")
      (locals ("System.Object") ("System.Object"))
      (maxstack 4)
      (source "build/base.sls")
      (body
        (ldconst 0)
        (ldfld "IronScheme.Core.Symbol" "Value")
        …
        (ret))))
  (type "base$lambda$12" (base "IronScheme.Core.Procedure") (attrs sealed)
    (field "f0" (type "System.Object"))
    (method "Invoke2" (override) (params "System.Object" "System.Object") (ret "System.Object")
      …)))
```

### 指令

| 类别 | 指令 |
|---|---|
| 载入/存储 | `(ldarg i)` `(starg i)` `(ldloc i)` `(stloc i)` `(ldnull)` `(ldc.i4 n)` `(ldc.r8 x)` `(ldstr "s")` `(ldconst k)` `(ldfld T f)` `(stfld T f)` `(ldsfld T f)` `(stsfld T f)` `(dup)` `(pop)` |
| 调用 | `(call T m (P…) R)` `(callvirt T m (P…) R)` `(newobj T (P…))`，任一前面可加 `(tail)` 前缀 |
| 类型 | `(castclass T)` `(isinst T)` `(box T)` `(unbox.any T)` |
| 运算 | `(add)` `(sub)` `(mul)` `(ceq)` `(clt)` `(cgt)` … 与 CIL 一一对应 |
| 控制 | `(label L)` `(br L)` `(brtrue L)` `(brfalse L)` `(ret)` `(throw)` `(leave L)` |
| 结构化异常 | `(try (body …) (finally …))`、`(try (body …) (catch T …))` |
| 源位置 | `(line l1 c1 l2 c2)`：后续指令的序列点 |
| 互操作（由发射器决议） | `(clr-call T name static? argc)` `(clr-field-get T name static?)` `(clr-field-set T name static?)` `(clr-new T argc)` `(clr-new-array T)` `(clr-cast T)` `(clr-is T)` `(clr-type T)`，以及方法级 `(clr-namespaces …)` `(clr-references …)` |

- 类型、成员一律用**名字**引用（`"命名空间.类型"`、成员名、参数类型列表），由发射器解析成 `Type`/`MethodInfo`。
- `ldconst k` 取常量表第 k 项（见 §3）。

## 3. 常量编码

编译器把每个常量写成中立的结构化编码，不依赖宿主的 `write`：

| 编码 | 含义 |
|---|---|
| `(nil)` `(true)` `(false)` `(unspecified)` | 单例 |
| `(fix n)` `(big "十进制")` `(rat "n/d")` `(flo "位模式十六进制")` `(cpx 实 虚)` | 数值；flonum 用位模式保证往返精确 |
| `(chr n)` `(str "…")` `(mstr "…")` | 字符（码点）、不可变 / 可变字符串 |
| `(sym "name")` `(gensym "g$name$N$TICKS")` | 符号，运行时按名字驻留 |
| `(pair a d)` `(vec e …)` `(bv "十六进制")` | 序对、向量、字节向量 |
| `(rec rtd-ref f …)` | 记录；`rtd-ref` = `(rtd "名字" "uid" 父 …字段描述)`，非生成性 RTD 按 uid 取已登记的同一对象 |
| `(def n x)` / `(ref n)` | 共享与环（`eq?` 同一对象只编码一次） |

- **发射器**把编码转成二进制 fasl，作为程序集的托管资源（或 `byte[]` 静态初始化数据）嵌入。
- **运行时**在模块类型初始化时调用 `Fasl.Read(资源)` 得到 `object[]`，存入静态字段 `c$`；`ldconst k` 即 `ldsfld c$; ldc.i4 k; ldelem.ref`。
- psyntax 的语法对象、`rtd`、条件等都是记录，走 `(rec …)`。它们的 RTD 必须能在目标运行时按 uid 找到同一个对象：要求这些记录类型是非生成性的，或者由编码携带完整定义在加载时登记。iron-013 与交叉自举阶段专门验证。

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

- 每个程序集有一个入口类型（boot 镜像为 `#Module`，库为按库名生成的类型）和一个 `public static object Initialize()`。
- 程序集级属性 `[IronScheme.Core.SchemeModule(typeof(入口类型))]` 标明入口，加载器不再按 `CustomSymbolDictionary` 搜索。
- 加载：`Runtime.LoadModule(路径)` → `Assembly.LoadFrom` → 读属性 → 调 `Initialize`。
  - boot 镜像：执行全部顶层代码，登记钩子与库。
  - 库：返回 13 元素列表，交给 psyntax 的 `try-load-from-file` 安装。
- 库 dll 文件名沿用 `library-name->dll-name`（`Console/psyntax/library-manager.sls:132-162`）。
- 每个 lambda 一个类会产生大量类型：boot 镜像预计数千个。这是 .NET 能承受的规模（Kotlin、F# 等也如此），先不优化。

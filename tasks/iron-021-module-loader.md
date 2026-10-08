# iron-021 程序集入口约定与加载器

- 里程碑：M3　依赖：iron-019、iron-020、iron-004　状态：完成
- 设计依据：[04 §6](../designs/04-lcil-and-emitter.md)

## 目标
统一编译产物的入口约定，实现 boot 镜像与库 dll 的加载。

## 工作内容
1. `SchemeModuleAttribute`（程序集级，指向入口类型）。
2. `Runtime.LoadModule(path)`：加载、读属性、调用 `Initialize`。
3. boot 镜像加载流程（执行顶层代码）与库加载流程（返回 13 元素列表）。
4. 内存模块（eval）的入口调用。

## 验收标准
- 手写 Lcil 生成的"迷你 boot 镜像"（定义几个全局过程并登记钩子）能被加载并调用。

## 从 iron-008 转来

- 原语 `load-library-dll`；旧 `Ports.cs` 中的 `AssemblyLoad`、`Load`、`ShowImports`、`IsSameAge`、`GetPath`（`~/` 前缀解析）。

## 结论（2026-10-08）

完成。

### 实现

- `IronScheme.Core/ModuleLoader.cs`：
  - `SchemeModuleAttribute(string entryType, string entryMethod)`：程序集级属性。用类型名字符串而不是设计草案中的 `typeof`，因为内存模式要在定义类型之前写属性。
  - `ModuleLoader`：`ResolvePath`（`~/` 为运行时目录，旧 `GetPath`）、`LoadAssembly(path, inMemory)`（`inMemory` 按字节加载不锁文件，同名 .pdb 修改时间相差 5 秒内时一并加载，旧 `IsSameAge`；`ShowImports` 开关）、`EntryPoint`（读属性、校验 `public static object M()`）、`Run(Assembly)`、`LoadModule(path, inMemory)`。
  - 原语 `load-library-dll`（psyntax `load-library-from-dll` 使用），原语表 128 个原语、10 个特殊条目。
- 发射器：Lcil 有 `(entry "类型" "方法")` 时校验入口（静态、公开、无参数、返回 `System.Object`）并写 `SchemeModule` 属性。
- 设计 04 §6 已按实现更新。

旧 `Ports.Load` 中"启动时用 `build/ironscheme.boot.dll` 替换 `ironscheme.boot.dll`"的逻辑属于宿主，留给 iron-029；`ClearTypesFrom`（编译期类型）在统一记录表示下不再需要。

### 验收

样例 `IronScheme.Emit/samples/miniboot.lcil`（迷你 boot 镜像：入口经常量表取得符号，定义全局过程 `mini-square` 与全局值 `mini-greeting`，经 `RuntimeHooks.SetRuntimeHook` 登记 `with-exception-handler` 钩子）与 `minilib.lcil`（入口返回 13 元素的库描述列表）。测试 `ModuleLoaderTests`（5 项）：
1. 持久化 dll 用 `LoadModule` 加载、按字节加载、内存模式发射后 `Run`，三种方式都能执行入口；之后调用全局过程得到 49，C# 侧经钩子 `SchemeCalls.WithExceptionHandler` 调到镜像中的过程。
2. `load-library-dll` 得到 13 元素列表，其中的过程可调用。
3. 错误：没有入口属性、入口签名不符（发射时报错）、文件不存在；`~/` 路径解析。

全部 200 项测试通过；`miniboot`、`minilib` 与 iron-020 的常量样例经命令行发射后 ILVerify 全部通过。

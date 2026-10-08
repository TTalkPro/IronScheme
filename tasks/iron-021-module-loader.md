# iron-021 程序集入口约定与加载器

- 里程碑：M3　依赖：iron-019、iron-020、iron-004　状态：未开始
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

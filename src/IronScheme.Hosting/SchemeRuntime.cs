using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using IronScheme.Core;

namespace IronScheme.Hosting;

/// <summary>初始化选项。</summary>
public sealed class SchemeRuntimeOptions
{
    /// <summary>boot 镜像路径；默认为应用目录下的 ironscheme.boot.dll，不存在时用入口程序集中名为 ironscheme.boot.dll 的嵌入资源（自包含发布）。</summary>
    public string BootImage { get; set; }

    /// <summary>库搜索路径（依次查找）；之后总是加上应用目录下的 lib/（存在时）。</summary>
    public IList<string> LibraryPaths { get; } = new List<string>();

    /// <summary>Scheme 侧 (command-line) 的值。</summary>
    public IList<string> CommandLine { get; } = new List<string> { "" };
}

/// <summary>Scheme 代码求值中引发的条件（Message 为 Scheme 打印器给出的条件描述）。</summary>
public sealed class SchemeError : Exception
{
    /// <summary>引发的 Scheme 条件对象。</summary>
    public object Condition { get; }

    internal SchemeError(string message, object condition, Exception inner) : base(message, inner) { Condition = condition; }
}

/// <summary>
/// C# 程序嵌入 IronScheme 的入口（iron-039，designs/07-tooling-and-embedding.md §5）：
/// 初始化运行时（登记原语、加载 boot 镜像、设置库搜索路径），在交互环境或指定导入下求值，
/// 取得库导出的过程并以 <see cref="Procedure"/> 或强类型委托调用。一个进程只有一个 Scheme 运行时。
/// Scheme 值与 C# 值的转换沿用 CLR 互操作的规则（designs/02-runtime.md §9）。
/// </summary>
public static class SchemeRuntime
{
    private static readonly object s_gate = new object();
    private static bool s_initialized;

    public static bool IsInitialized => s_initialized;

    /// <summary>应用目录（单文件发布时 Assembly.Location 为空，用 AppContext.BaseDirectory）。</summary>
    public static string ApplicationDirectory => AppContext.BaseDirectory;

    /// <summary>初始化运行时；重复调用无效果。</summary>
    public static void Initialize(SchemeRuntimeOptions options = null)
    {
        lock (s_gate)
        {
            if (s_initialized) return;
            options ??= new SchemeRuntimeOptions();
            foreach (var p in options.LibraryPaths) Builtins.AddIncludePath(p);
            string appLib = Path.Combine(ApplicationDirectory, "lib");
            if (Directory.Exists(appLib) && !options.LibraryPaths.Any(p => Path.GetFullPath(p) == Path.GetFullPath(appLib)))
                Builtins.AddIncludePath(appLib);
            Builtins.CommandLineArgs = options.CommandLine.ToArray();
            PrimitiveRegistry.RegisterAll();
            string boot = options.BootImage ?? Path.Combine(ApplicationDirectory, BootImageName);
            if (File.Exists(boot))
                ModuleLoader.LoadModule(boot);
            else if (options.BootImage == null && ReadResource(BootImageName) is byte[] bytes)
                ModuleLoader.Run(System.Reflection.Assembly.Load(bytes));   // 自包含发布：boot 镜像嵌入在可执行文件中（iron-036）
            else
                throw new FileNotFoundException("IronScheme boot image not found", boot);
            s_initialized = true;
        }
    }

    public const string BootImageName = "ironscheme.boot.dll";

    /// <summary>入口程序集中的嵌入资源（自包含发布时 boot 镜像与应用的 .fasl 放在这里）；没有时为 null。</summary>
    public static byte[] ReadResource(string name)
    {
        var asm = System.Reflection.Assembly.GetEntryAssembly();
        using var s = asm?.GetManifestResourceStream(name);
        if (s == null) return null;
        var ms = new MemoryStream();
        s.CopyTo(ms);
        return ms.ToArray();
    }

    private static void EnsureInitialized()
    {
        if (!s_initialized) Initialize();
    }

    private static Procedure Global(string name) =>
      Symbol.Intern(name).Value as Procedure ?? throw new InvalidOperationException(name + " is not defined (boot image not loaded?)");

    /// <summary>读入 Scheme 源码文本中的全部数据。</summary>
    public static IReadOnlyList<object> Read(string code)
    {
        var reader = new SchemeReader(new StringReader(code), "embedded", false);
        var data = new List<object>();
        for (object x = reader.Read(); !ReferenceEquals(x, Builtins.EofObject()); x = reader.Read()) data.Add(x);
        return data;
    }

    /// <summary>在交互环境（导入了 (ironscheme)）中依次求值源码中的各个数据，返回最后一个值。</summary>
    public static object Eval(string code)
    {
        EnsureInitialized();
        object result = Unspecified.Instance;
        foreach (var x in Read(code)) result = EvalDatum(x);
        return result;
    }

    /// <summary>在只导入 imports（库名，如 "(rnrs)"、"(demo app)"）的环境中求值一个表达式。</summary>
    public static object Eval(string expression, params string[] imports)
    {
        EnsureInitialized();
        var expr = Read(expression).Single();
        var specs = imports.Select(i => Cons.FromArray(Symbol.Intern("quote"), Read(i).Single())).ToArray();
        return EvalDatum(Cons.FromArray(Symbol.Intern("eval"),
                                        Cons.FromArray(Symbol.Intern("quote"), expr),
                                        new Cons(Symbol.Intern("environment"), Cons.FromArray(specs))));
    }

    /// <summary>把库导入交互环境（之后 <see cref="Eval(string)"/> 可直接使用其导出）。</summary>
    public static void Import(params string[] libraries) =>
      Eval("(import " + string.Join(" ", libraries) + ")");

    /// <summary>库导出的过程（如 GetProcedure("(demo app)", "find-books")）。</summary>
    public static Procedure GetProcedure(string library, string name) =>
      Eval(name, library) as Procedure ?? throw new InvalidOperationException($"{name} in {library} is not a procedure");

    /// <summary>库导出的过程，包装为强类型委托（如 Func&lt;string, object&gt;）；参数与返回值按 CLR 互操作规则转换。</summary>
    public static T GetFunction<T>(string library, string name) where T : Delegate =>
      (T)Interop.ToDelegate(typeof(T), new Guarded(GetProcedure(library, name)));

    /// <summary>调用时把 Scheme 条件转为 <see cref="SchemeError"/> 的过程包装（委托经它调用）。</summary>
    private sealed class Guarded : VariadicProcedure
    {
        private readonly Procedure _inner;
        public Guarded(Procedure inner) { _inner = inner; }
        public override string Name => _inner.Name;
        public override object Arity => _inner.Arity;
        public override object Form => _inner.Form;
        public override object InvokeN(object[] args) => SchemeRuntime.Call(_inner, args);
    }

    /// <summary>调用 Scheme 过程；引发的条件转为 <see cref="SchemeError"/>。</summary>
    public static object Call(Procedure procedure, params object[] args)
    {
        try
        {
            return procedure.Call(args);
        }
        catch (SchemeException e)
        {
            throw Wrap(e);
        }
    }

    /// <summary>Scheme 值的文本形式（write 的输出）。</summary>
    public static string ToSchemeString(object value)
    {
        EnsureInitialized();
        return Format("~s", value);
    }

    /// <summary>在交互环境中求值 (format fmt (quote value))。</summary>
    private static string Format(string fmt, object value)
    {
        object s = Global("eval-embedded").Invoke1(
          Cons.FromArray(Symbol.Intern("format"), fmt, Cons.FromArray(Symbol.Intern("quote"), value)));
        return s as string ?? (s is SchemeString or System.Text.StringBuilder ? s.ToString() : null) ?? "";
    }

    private static object EvalDatum(object x)
    {
        try
        {
            return Global("eval-embedded").Invoke1(x);
        }
        catch (SchemeException e)
        {
            throw Wrap(e);
        }
    }

    private static SchemeError Wrap(SchemeException e)
    {
        string message;
        try
        {
            message = Format("~a", e.Condition);
        }
        catch (Exception)
        {
            message = null;
        }
        return new SchemeError(message ?? e.Message, e.Condition, e);
    }
}

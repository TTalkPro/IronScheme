using System;
using System.IO;
using System.Threading;
using IronScheme.Core;
using IronScheme.Hosting;

namespace IronScheme.Host
{
  /// <summary>
  /// 新控制台宿主（iron-029，designs/02-runtime.md §11）：
  ///   IronScheme.Host [选项] [脚本.sps 参数 …]
  /// 选项：
  ///   -I &lt;目录&gt;        增加库搜索路径（可重复）
  ///   --boot &lt;dll&gt;     boot 镜像，默认 ~/ironscheme.boot.dll（~ 为宿主所在目录）
  ///   --show-imports   加载模块时打印路径
  ///   --deterministic  确定性 gensym（构建自举时使用）
  /// 有脚本时以 R6RS 顶层程序运行（(load/program 脚本)，失败时退出码 1）；否则进入 REPL。
  /// </summary>
  public static class Program
  {
    const string DefaultBoot = "~/ironscheme.boot.dll";

    public static int Main(string[] args)
    {
      int exitCode = 0;
      // 编译后的代码与 psyntax 递归较深：与旧宿主一样在大栈线程上运行
      var t = new Thread(() => exitCode = Run(args), 256 * 1024 * 1024);
      t.Start();
      t.Join();
      return exitCode;
    }

    static int Run(string[] args)
    {
      // 自包含发布的应用（iron-036）：可执行文件中嵌入了应用清单，全部参数交给应用
      if (SchemeRuntime.ReadResource(AppManifest) is byte[] manifest) return RunApp(manifest, args);

      string boot = DefaultBoot;
      var options = new SchemeRuntimeOptions();
      int i = 0;
      for (; i < args.Length; i++)
      {
        switch (args[i])
        {
          case "-I" when i + 1 < args.Length: options.LibraryPaths.Add(args[++i]); continue;
          case "--boot" when i + 1 < args.Length: boot = args[++i]; continue;
          case "--show-imports": ModuleLoader.ShowImports = true; continue;
          case "--deterministic": RuntimeOptions.DeterministicGensym = true; continue;
          case "-h": case "--help": return Usage();
        }
        if (args[i].StartsWith("-", StringComparison.Ordinal) && args[i] != "-") return Usage();
        break;
      }
      string script = i < args.Length ? args[i] : null;

      // psyntax 在 boot 初始化时读取命令行：脚本及其参数（REPL 时为空串，与旧宿主一致）
      options.CommandLine.Clear();
      foreach (var a in script != null ? args[i..] : new[] { "" }) options.CommandLine.Add(a);

      try
      {
        if (boot == DefaultBoot) ReplaceBootImage();
        // 默认镜像不存在时交给 SchemeRuntime：它再找可执行文件中的嵌入资源（单文件发布）
        string resolved = ModuleLoader.ResolvePath(boot);
        options.BootImage = boot == DefaultBoot && !File.Exists(resolved) ? null : resolved;
        SchemeRuntime.Initialize(options);
      }
      catch (Exception e)
      {
        Console.Error.WriteLine("IronScheme.Host: cannot load boot image " + boot + ": " + Unwrap(e).Message);
        return 2;
      }

      return script != null ? RunScript(script) : Repl.Run();
    }

    const string AppManifest = "ironscheme.app";

    /// <summary>
    /// 运行嵌入的应用：清单（compile-whole-program 生成）每行 "library 资源名" 或 "program 资源名"，
    /// 依次加载这些嵌入的 .fasl 并交给 psyntax 的 load-fasl-content（安装库、运行程序）。(command-line) 为应用名与参数。
    /// </summary>
    static int RunApp(byte[] manifest, string[] args)
    {
      var options = new SchemeRuntimeOptions();
      options.CommandLine.Clear();
      options.CommandLine.Add(Path.GetFileNameWithoutExtension(Environment.ProcessPath ?? "app"));
      foreach (var a in args) options.CommandLine.Add(a);
      try
      {
        SchemeRuntime.Initialize(options);
        var load = Symbol.Intern("load-fasl-content").Value as Procedure
          ?? throw new InvalidOperationException("boot image has no load-fasl-content hook");
        foreach (var line in System.Text.Encoding.UTF8.GetString(manifest).Split('\n'))
        {
          var parts = line.Trim().Split(' ', 2);
          if (parts.Length != 2) continue;
          var bytes = SchemeRuntime.ReadResource(parts[1]) ?? throw new InvalidOperationException("missing embedded file " + parts[1]);
          load.Invoke2(ModuleLoader.Run(System.Reflection.Assembly.Load(bytes)), parts[1]);
        }
        return 0;
      }
      catch (Exception e)
      {
        Repl.Report(e);
        return 1;
      }
      finally
      {
        Console.Out.Flush();
      }
    }

    static int Usage()
    {
      Console.Error.WriteLine("usage: IronScheme.Host [-I dir]... [--boot dll] [--show-imports] [--deterministic] [script.sps args...]");
      return 2;
    }

    /// <summary>
    /// 旧 Ports.Load 的约定：当前目录下的 build/ironscheme.boot.dll 比宿主目录中的镜像新时，用它替换
    /// （旧镜像改名为 ironscheme.boot.old.dll）。只对默认镜像路径生效。
    /// 与旧系统不同，新镜像是复制而不是移动：build/ 中的镜像是构建产物的正本（GenerateBootImage 构建目标、自举测试）。
    /// </summary>
    static void ReplaceBootImage()
    {
      const string newBoot = "build/ironscheme.boot.dll";
      string current = ModuleLoader.ResolvePath(DefaultBoot);
      if (!File.Exists(newBoot) || (File.Exists(current) && File.GetLastWriteTime(newBoot) <= File.GetLastWriteTime(current))) return;
      string dir = Path.GetDirectoryName(current);
      string old = Path.Combine(dir, "ironscheme.boot.old.dll");
      if (File.Exists(current))
      {
        File.Delete(old);
        File.Move(current, old);
      }
      File.Copy(newBoot, current, true);
      string newPdb = Path.ChangeExtension(newBoot, ".pdb"), pdb = Path.ChangeExtension(current, ".pdb");
      if (File.Exists(newPdb)) File.Copy(newPdb, pdb, true);
    }

    static int RunScript(string script)
    {
      try
      {
        Repl.EvalEmbedded(Cons.FromArray(Symbol.Intern("load/program"), script.Replace('\\', '/')));
        return 0;
      }
      catch (ProgramFailedException)
      {
        return 1;
      }
      catch (Exception e)
      {
        Repl.Report(e);
        return 1;
      }
      finally
      {
        Console.Out.Flush();
      }
    }

    internal static Exception Unwrap(Exception e) =>
      e is System.Reflection.TargetInvocationException tie && tie.InnerException != null ? Unwrap(tie.InnerException) : e;
  }
}

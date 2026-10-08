using System;
using System.IO;
using System.Threading;
using IronScheme.Core;

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
      string boot = DefaultBoot;
      int i = 0;
      for (; i < args.Length; i++)
      {
        switch (args[i])
        {
          case "-I" when i + 1 < args.Length: Builtins.AddIncludePath(args[++i]); continue;
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
      Builtins.CommandLineArgs = script != null ? args[i..] : new[] { "" };

      try
      {
        PrimitiveRegistry.RegisterAll();
        if (boot == DefaultBoot) ReplaceBootImage();
        ModuleLoader.LoadModule(boot);
      }
      catch (Exception e)
      {
        Console.Error.WriteLine("IronScheme.Host: cannot load boot image " + boot + ": " + Unwrap(e).Message);
        return 2;
      }

      return script != null ? RunScript(script) : Repl.Run();
    }

    static int Usage()
    {
      Console.Error.WriteLine("usage: IronScheme.Host [-I dir]... [--boot dll] [--show-imports] [--deterministic] [script.sps args...]");
      return 2;
    }

    /// <summary>
    /// 旧 Ports.Load 的约定：当前目录下的 build/ironscheme.boot.dll 比宿主目录中的镜像新时，用它替换
    /// （旧镜像改名为 ironscheme.boot.old.dll，pdb 一并移动）。只对默认镜像路径生效。
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
      File.Move(newBoot, current);
      string newPdb = Path.ChangeExtension(newBoot, ".pdb"), pdb = Path.ChangeExtension(current, ".pdb");
      if (File.Exists(newPdb))
      {
        File.Delete(pdb);
        File.Move(newPdb, pdb);
      }
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

using System;
using IronScheme.Core;

namespace IronScheme.Host
{
  /// <summary>
  /// 简单 REPL（iron-029）：读入一个数据（可跨行）→ psyntax 的 eval-r6rs（交互环境；出错时由它打印条件）→
  /// 用 pretty-print 打印结果（未指定值不打印，多值逐个打印）。输入结束或 (exit) 时退出。
  /// </summary>
  static class Repl
  {
    static Procedure Global(string name) =>
      Symbol.Intern(name).Value as Procedure
        ?? throw new InvalidOperationException(name + " is not defined (boot image not loaded?)");

    /// <summary>在交互环境中求值，异常原样传出（eval-r6rs 会吞掉 CLR 异常，脚本模式需要 ProgramFailedException）。</summary>
    public static object EvalEmbedded(object expr) => Global("eval-embedded").Invoke1(expr);

    public static int Run()
    {
      Console.WriteLine($"IronScheme {Builtins.VersionString} on {System.Runtime.InteropServices.RuntimeInformation.FrameworkDescription} (new runtime)");
      var reader = new SchemeReader(Console.In, "stdin", false);
      var eval = Global("eval-r6rs");
      var print = Global("pretty-print");
      while (true)
      {
        Console.Write("> ");
        Console.Out.Flush();
        object x;
        try
        {
          x = reader.Read();
        }
        catch (ReaderException e)
        {
          Console.Error.WriteLine("read error: " + e.Message);
          reader = new SchemeReader(Console.In, "stdin", false);
          continue;
        }
        if (ReferenceEquals(x, Builtins.EofObject()))
        {
          Console.WriteLine();
          return 0;
        }
        try
        {
          object v = eval.Invoke1(x);
          if (v is MultipleValues mv)
            foreach (var item in mv.ToArray()) print.Invoke1(item);
          else if (!(v is Unspecified))
            print.Invoke1(v);
        }
        catch (Exception e)
        {
          Report(e);
        }
        Console.Out.Flush();
      }
    }

    public static void Report(Exception e)
    {
      e = Program.Unwrap(e);
      Console.Out.Flush();
      if (e is SchemeException se)
      {
        try
        {
          Console.Error.WriteLine("Unhandled condition:");
          Global("pretty-print").Invoke1(se.Condition);
          return;
        }
        catch (Exception) { }
      }
      Console.Error.WriteLine("Unhandled CLR exception: " + e);
    }
  }
}

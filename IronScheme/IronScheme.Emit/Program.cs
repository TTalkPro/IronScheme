using System;
using System.IO;

namespace IronScheme.Emit
{
  /// <summary>
  /// 命令行：iron-emit &lt;in.lcil&gt; -o &lt;out.dll&gt; [--pdb] [-r &lt;目录&gt;]…
  /// -r 增加查找被引用程序集（如 IronScheme.Core.dll）的目录；默认含发射器所在目录。
  /// </summary>
  public static class Program
  {
    public static int Main(string[] args)
    {
      string input = null, output = null;
      bool pdb = false;
      for (int i = 0; i < args.Length; i++)
      {
        switch (args[i])
        {
          case "-o" when i + 1 < args.Length: output = args[++i]; break;
          case "-r" when i + 1 < args.Length: LcilEmitter.ProbeDirectories.Add(Path.GetFullPath(args[++i])); break;
          case "--pdb": pdb = true; break;
          default:
            if (input == null && !args[i].StartsWith("-", StringComparison.Ordinal)) input = args[i];
            else return Usage();
            break;
        }
      }
      if (input == null) return Usage();
      output ??= Path.ChangeExtension(input, ".dll");
      try
      {
        LcilEmitter.Save(File.ReadAllText(input), input, output, pdb);
        return 0;
      }
      catch (LcilException e)
      {
        Console.Error.WriteLine("iron-emit: " + e.Message);
        return 1;
      }
    }

    static int Usage()
    {
      Console.Error.WriteLine("usage: iron-emit <in.lcil> [-o <out.dll>] [--pdb] [-r <dir>]...");
      return 2;
    }
  }
}

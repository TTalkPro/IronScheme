using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using IronScheme.Core;

namespace IronScheme.Host;

/// <summary>
/// REPL（iron-029、iron-038）：读入一个数据（可跨行）→ 展开器的 eval-r6rs（交互环境；出错时由它打印条件）→
/// 用 pretty-print 打印结果（未指定值不打印，多值逐个打印）。输入结束或 (exit) 时退出。
/// 终端交互时用 LineEditor（行编辑、历史、补全、提示）；标准输入或输出被重定向时逐个读取数据。
/// </summary>
internal static class Repl
{
    private static Procedure Global(string name) =>
      Symbol.Intern(name).Value as Procedure
        ?? throw new InvalidOperationException(name + " is not defined (boot image not loaded?)");

    /// <summary>在交互环境中求值，异常原样传出（eval-r6rs 会吞掉 CLR 异常，脚本模式需要 ProgramFailedException）。</summary>
    public static object EvalEmbedded(object expr) => Global("eval-embedded").Invoke1(expr);

    public static int Run()
    {
        Console.WriteLine($"IronScheme {Builtins.VersionString} on {System.Runtime.InteropServices.RuntimeInformation.FrameworkDescription} (new runtime)");
        if (!Console.IsInputRedirected && !Console.IsOutputRedirected)
        {
            try
            {
                return RunInteractive();
            }
            catch (Exception e) when (e is IOException || e is InvalidOperationException || e is ArgumentException)
            {
                // 终端不支持所需的控制（如光标定位）：退回逐个读取数据
                Console.Error.WriteLine("line editing disabled: " + e.Message);
            }
        }
        return RunPlain();
    }

    private static int RunPlain()
    {
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
            EvalPrint(eval, print, x);
        }
    }

    private static void EvalPrint(Procedure eval, Procedure print, object x)
    {
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

    /// <summary>终端交互：行编辑器读入一个完整的输入（可含多个数据），逐个求值打印。</summary>
    private static int RunInteractive()
    {
        var eval = Global("eval-r6rs");
        var print = Global("pretty-print");
        string historyFile = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".ironscheme_history");
        var editor = new LineEditor(new SchemeServices(), historyFile);
        while (true)
        {
            string text = editor.Read("> ", ". ");
            if (text == null) return 0;
            if (text.Trim().Length == 0) continue;
            var reader = new SchemeReader(new StringReader(text), "stdin", false);
            while (true)
            {
                object x;
                try
                {
                    x = reader.Read();
                }
                catch (ReaderException e)
                {
                    Console.Error.WriteLine("read error: " + e.Message);
                    break;
                }
                if (ReferenceEquals(x, Builtins.EofObject())) break;
                EvalPrint(eval, print, x);
            }
        }
    }

    /// <summary>
    /// 补全与提示的数据来自展开器 main 登记的钩子（repl-complete、repl-describe）；旧的 boot 镜像没有这些钩子时不补全、不提示。
    /// </summary>
    private sealed class SchemeServices : IReplServices
    {
        private static Procedure Hook(string name) => Symbol.Intern(name).Value as Procedure;

        public IReadOnlyList<string> Complete(string prefix, bool library)
        {
            var p = Hook("repl-complete");
            if (p == null) return Array.Empty<string>();
            var result = new List<string>();
            for (object l = p.Invoke2(prefix, RT.Bool(library)); l is Cons c; l = c.cdr)
                if (c.car is string s) result.Add(s);
                else if (c.car != null) result.Add(c.car.ToString());
            return result.Distinct().OrderBy(s => s, StringComparer.Ordinal).ToList();
        }

        public string Hint(string name)
        {
            var p = Hook("repl-describe");
            if (p == null) return null;
            object v = p.Invoke1(name);
            return v as string ?? (v is SchemeString or System.Text.StringBuilder ? v.ToString() : null);
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

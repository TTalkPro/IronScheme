using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using IronScheme.Core;

namespace IronScheme.PrimGen;

/// <summary>
/// 用法：
///   IronScheme.PrimGen &lt;输出文件&gt;            生成原语表
///   IronScheme.PrimGen --check &lt;已有文件&gt;     检查已有原语表是否与当前 IronScheme.Core 一致（不一致返回 1）
/// </summary>
public static class Program
{
    /// <summary>编译器专门处理的原语（03 §6）。种类名供编译器分派使用。</summary>
    private static readonly (string Name, string Kind, string Note)[] s_specials =
    {
  ("$and?", "and", "短路与，参数为未求值表达式，结果为 CLR bool"),
  ("$or?", "or", "短路或，参数为未求值表达式，结果为 CLR bool"),
  ("$break", "break", "调用 Debugger.Break"),
  ("$throw", "throw", "抛出参数（一个 .NET 异常对象）"),
  ("$try/finally", "try-finally", "($try/finally body finalizer)：finalizer 在 finally 中求值"),
  ("call/cc", "escape-frame", "逃逸续延捕获帧（02 §6）"),
  ("call-with-current-continuation", "escape-frame", "同 call/cc"),
  ("call-with-values", "call-with-values", "消费者为字面 lambda 时可内联"),
  ("apply", "apply", "展开最后一个列表参数"),
  ("values", "values", "在 Scheme 中定义（boot/exceptions.sls）；作为原语出现时编译为多值构造"),
};

    public static int Main(string[] args)
    {
        if (args.Length == 2 && args[0] == "--check")
        {
            string expected = Generate();
            string actual = File.Exists(args[1]) ? File.ReadAllText(args[1]) : "";
            if (expected == actual) { Console.WriteLine("primitives table is up to date"); return 0; }
            Console.Error.WriteLine("primitives table is out of date: regenerate with IronScheme.PrimGen");
            return 1;
        }
        if (args.Length != 1)
        {
            Console.Error.WriteLine("usage: IronScheme.PrimGen <output.ss> | --check <existing.ss>");
            return 2;
        }
        string text = Generate();
        Verify(text);
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(args[0])));
        File.WriteAllText(args[0], text, new UTF8Encoding(false));
        Console.WriteLine($"wrote {args[0]}: {PrimitiveRegistry.All.Count} primitives, {s_specials.Length} specials");
        return 0;
    }

    private static string Flags(PrimitiveFlags f)
    {
        var names = new List<string>();
        if (f.HasFlag(PrimitiveFlags.Pure)) names.Add("pure");
        if (f.HasFlag(PrimitiveFlags.Unsafe)) names.Add("unsafe");
        if (f.HasFlag(PrimitiveFlags.AllowTailCall)) names.Add("allow-tail-call");
        return "(" + string.Join(" ", names) + ")";
    }

    private static string Str(string s) => "\"" + s.Replace("\\", "\\\\").Replace("\"", "\\\"") + "\"";

    public static string Generate()
    {
        var sb = new StringBuilder();
        sb.Append(";;; 原语表：由 IronScheme.PrimGen 从 IronScheme.Core 生成，请勿手工修改。\n");
        sb.Append(";;; 设计：designs/03-compiler.md §6；任务：tasks/iron-012-primgen.md\n");
        sb.Append(";;;\n");
        sb.Append(";;; (primitive 名字 重载 …)\n");
        sb.Append(";;;   重载 = (overload \"类型全名\" \"方法名\" 固定参数个数 剩余参数? (标志 …) 内联模板)\n");
        sb.Append(";;;   标志：pure（可常量折叠）、unsafe（不做类型检查）、allow-tail-call；内联模板为名字或 #f\n");
        sb.Append(";;; (special 名字 种类)：编译器专门处理的原语；同名的 primitive 条目（若有）是非内联时的后备实现\n");
        sb.Append("(primitive-table 1\n");

        foreach (var kv in PrimitiveRegistry.All)   // 已按名字排序
        {
            sb.Append("  (primitive ").Append(kv.Key);
            // 重载按（固定参数个数、是否剩余参数、类型名、方法名）排序，保证输出稳定
            foreach (var o in kv.Value.OrderBy(o => o.FixedArity).ThenBy(o => o.HasRest).ThenBy(o => o.Method.DeclaringType.FullName, StringComparer.Ordinal).ThenBy(o => o.Method.Name, StringComparer.Ordinal))
            {
                sb.Append("\n    (overload ")
                  .Append(Str(o.Method.DeclaringType.FullName)).Append(' ')
                  .Append(Str(o.Method.Name)).Append(' ')
                  .Append(o.FixedArity).Append(' ')
                  .Append(o.HasRest ? "#t" : "#f").Append(' ')
                  .Append(Flags(o.Attribute.Flags)).Append(' ')
                  .Append(o.Attribute.Inline ?? "#f").Append(')');
            }
            sb.Append(")\n");
        }
        foreach (var s in s_specials.OrderBy(s => s.Name, StringComparer.Ordinal))
            sb.Append("  (special ").Append(s.Name).Append(' ').Append(s.Kind).Append(")   ; ").Append(s.Note).Append('\n');
        sb.Append(")\n");
        return sb.ToString();
    }

    /// <summary>用 Scheme reader 读回，确认每个名字都按原样读成符号。</summary>
    private static void Verify(string text)
    {
        var table = (Cons)new SchemeReader(new StringReader(text), "primitives.ss", false).Read();
        var names = new List<string>();
        for (object x = ((Cons)table.cdr).cdr; x is Cons c; x = c.cdr)
            names.Add(((Symbol)((Cons)((Cons)c.car).cdr).car).Name);
        var expected = PrimitiveRegistry.All.Keys.Concat(s_specials.Select(s => s.Name).OrderBy(n => n, StringComparer.Ordinal)).ToList();
        if (!names.SequenceEqual(expected))
            throw new InvalidOperationException("primitive names do not round-trip through the reader");
    }
}

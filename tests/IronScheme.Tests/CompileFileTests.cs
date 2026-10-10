using System;
using System.IO;
using System.Linq;
using System.Reflection.Metadata;
using System.Reflection.PortableExecutable;
using NUnit.Framework;

namespace IronScheme.Tests;

/// <summary>
/// compile-file / compile-library / compile-program 与 .fasl（iron-037，designs/07-tooling-and-embedding.md §2）。
/// 在临时目录中写一个库与一个程序，编译、运行，并检查导入时使用 .fasl、依赖过期检测、REPL 中 load、ILVerify。
/// </summary>
[Order(5)]
[Category(nameof(CompileFile))]
[NonParallelizable]
public class CompileFile : TestRunner
{
    private string _dir;

    private const string Library = @"(library (demo util)
  (export square greet bump)
  (import (rnrs))
  (define (square x) (* x x))
  (define (greet who) (string-append ""hello, "" who))
  (define-syntax bump (syntax-rules () ((_ x) (+ x 1)))))";

    private const string Program = @"(import (rnrs) (demo util))
(display (list (square 7) (greet ""fasl"") (bump 41) (cdr (command-line))))
(newline)";

    private const string Expected = "(49 hello, fasl 42 ";

    [SetUp]
    public void SetUp()
    {
        if (!File.Exists(Paths.Boot)) Assert.Ignore("boot image not built");
        _dir = Path.Combine(Path.GetTempPath(), "ironscheme-compile-file-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(Path.Combine(_dir, "demo"));
        File.WriteAllText(Path.Combine(_dir, "demo", "util.sls"), Library);
        File.WriteAllText(Path.Combine(_dir, "prog.sps"), Program);
    }

    [TearDown]
    public void TearDown()
    {
        if (_dir != null && Directory.Exists(_dir)) Directory.Delete(_dir, true);
    }

    /// <summary>在临时目录中运行宿主（库搜索路径含 src/scheme/lib）。</summary>
    private TestResult Host(string input, bool check, params string[] args) =>
      RunProcess("dotnet", new[] { Paths.Host, "--boot", Paths.Boot, "-I", Path.Combine(Paths.SchemeDir, "lib") }.Concat(args).ToArray(),
                 input, _dir, checkExitCode: check);

    private TestResult Script(string code)
    {
        File.WriteAllText(Path.Combine(_dir, "build.sps"), "(import (ironscheme))\n" + code);
        return Host(null, true, "build.sps");
    }

    private string F(params string[] parts) => Path.Combine(new[] { _dir }.Concat(parts).ToArray());

    [Test]
    public void CompileLibraryAndProgram()
    {
        var r = Script("(display (compile-library \"demo/util.sls\")) (newline) (display (compile-program \"prog.sps\"))");
        Assert.That(r.Output, Does.Contain("demo/util.fasl").And.Contain("prog.fasl"));
        Assert.That(File.Exists(F("demo", "util.fasl")) && File.Exists(F("prog.fasl")), Is.True);

        // 宿主直接运行编译后的程序，参数原样传入
        Assert.That(Host(null, true, "prog.fasl", "a", "b").Output, Is.EqualTo(Expected + "(a b))"));
        // 源码程序导入库时使用源文件旁的 .fasl
        var s = Host(null, true, "--show-imports", "prog.sps");
        Assert.That(s.Error, Does.Contain("util.fasl"));
        Assert.That(s.Output, Is.EqualTo(Expected + "())"));
    }

    [Test]
    public void CompileFileDispatchesOnContent()
    {
        Script("(compile-file \"demo/util.sls\") (compile-file \"prog.sps\" \"out.fasl\")");
        Assert.That(File.Exists(F("demo", "util.fasl")), Is.True);
        Assert.That(Host(null, true, "out.fasl").Output, Is.EqualTo(Expected + "())"));
    }

    [Test]
    public void StaleLibraryIsDetected()
    {
        Script("(compile-imported-libraries #t) (compile-program \"prog.sps\")");
        Assert.That(File.Exists(F("demo", "util.fasl")), Is.True, "compile-imported-libraries");
        Assert.That(Host(null, true, "prog.fasl").Output, Is.EqualTo(Expected + "())"));

        // 库源文件比 .fasl 新：导入时从源码重新展开，编译后的程序不再能用
        File.SetLastWriteTimeUtc(F("demo", "util.sls"), DateTime.UtcNow.AddMinutes(1));
        var r = Host(null, false, "prog.fasl");
        Assert.That(r.ExitCode, Is.Not.EqualTo(0));
        Assert.That(r.Error, Does.Contain("requires a different compilation of a library"));
    }

    [Test]
    public void LoadLibraryFaslInRepl()
    {
        Script("(compile-library \"demo/util.sls\")");
        var r = Host("(load \"demo/util.fasl\")\n(import (demo util))\n(list (square 9) (bump 1))", true);
        Assert.That(r.Output, Does.Contain("(81 2)"));
    }

    /// <summary>编译产物引用的程序集名（iron-034e：直接调用 boot 导出的过程时引用 ironscheme.boot）。</summary>
    private static string[] AssemblyRefs(string file)
    {
        using var pe = new PEReader(File.OpenRead(file));
        var md = pe.GetMetadataReader();
        return md.AssemblyReferences.Select(h => md.GetString(md.GetAssemblyReference(h).Name)).ToArray();
    }

    [Test]
    public void CompiledCodeCallsBootDirectly()
    {
        Script("(compile-library \"demo/util.sls\") (compile-program \"prog.sps\")");
        Assert.That(AssemblyRefs(F("prog.fasl")), Does.Contain("ironscheme.boot"));
        Assert.That(AssemblyRefs(F("demo", "util.fasl")), Does.Contain("ironscheme.boot"));
        Assert.That(Host(null, true, "prog.fasl").Output, Is.EqualTo(Expected + "())"));
    }

    [Test]
    public void ProgramCallsCompiledLibraryDirectly()
    {
        // 库的 .fasl 旁有接口文件；另一个进程从 .fasl 装入库后编译的程序直接调用库的类（iron-034e）
        Script("(compile-library \"demo/util.sls\")");
        Assert.That(File.Exists(F("demo", "util.ifc")), Is.True);
        Assert.That(File.ReadAllText(F("demo", "util.ifc")), Does.Contain("square"));
        Script("(compile-program \"prog.sps\")");
        var utilAsm = AssemblyName(F("demo", "util.fasl"));
        Assert.That(utilAsm, Does.StartWith("util$"));
        Assert.That(AssemblyRefs(F("prog.fasl")), Does.Contain(utilAsm));
        Assert.That(Host(null, true, "prog.fasl").Output, Is.EqualTo(Expected + "())"));
        // ILVerify：直接调用库的类的程序也可校验。ILVerify 按文件名找被引用的程序集，库产物的程序集名带唯一后缀，
        // 所以把它复制成以程序集名命名的 dll 作为引用
        var refDir = F("refs");
        Directory.CreateDirectory(refDir);
        File.Copy(F("demo", "util.fasl"), Path.Combine(refDir, utilAsm + ".dll"));
        var v = Bootstrap.ILVerify(F("prog.fasl"), "-r", Path.Combine(refDir, "*.dll"));
        Assert.That(v.Output, Does.Contain($"All Classes and Methods in {F("prog.fasl")} Verified."), v.ToString());
        // 源码程序导入 .fasl 中的库：eval 的单元同样直接调用
        Assert.That(Host(null, true, "prog.sps").Output, Is.EqualTo(Expected + "())"));

        // 库重新编译（新的编译实例）：旧程序按现有机制报需要重新编译
        Script("(compile-library \"demo/util.sls\")");
        var r = Host(null, false, "prog.fasl");
        Assert.That(r.ExitCode, Is.Not.EqualTo(0));
        Assert.That(r.Error, Does.Contain("requires a different compilation of a library"));
    }

    private static string AssemblyName(string file)
    {
        using var pe = new PEReader(File.OpenRead(file));
        var md = pe.GetMetadataReader();
        return md.GetString(md.GetAssemblyDefinition().Name);
    }

    [Test]
    public void StaleBootInterfaceIsIgnored()
    {
        // 镜像旁的接口文件与镜像不符（id 不同）：编译器不用它，产物经位置调用 boot 的过程
        string bootDir = F("boot");
        Directory.CreateDirectory(bootDir);
        string boot = Path.Combine(bootDir, "ironscheme.boot.dll");
        File.Copy(Paths.Boot, boot);
        string ifc = File.ReadAllText(Path.ChangeExtension(Paths.Boot, ".ifc"));
        int q = ifc.IndexOf('"');
        File.WriteAllText(Path.ChangeExtension(boot, ".ifc"), ifc.Substring(0, q + 1) + new string('0', 32) + ifc.Substring(q + 33));
        File.WriteAllText(F("build.sps"), "(import (ironscheme))\n(compile-library \"demo/util.sls\") (compile-program \"prog.sps\")");
        RunProcess("dotnet", new[] { Paths.Host, "--boot", boot, "-I", Path.Combine(Paths.SchemeDir, "lib"), "build.sps" }, null, _dir);
        Assert.That(AssemblyRefs(F("prog.fasl")), Does.Not.Contain("ironscheme.boot"));
        Assert.That(AssemblyRefs(F("demo", "util.fasl")), Does.Not.Contain("ironscheme.boot"));
        Assert.That(Host(null, true, "prog.fasl").Output, Is.EqualTo(Expected + "())"));
    }

    [Test]
    public void BootImageMismatchIsReported()
    {
        // 编译产物入口的核对：id 与正在运行的镜像不同时报错（库的 .fasl 由加载方退回源码，程序报需要重新编译）
        File.WriteAllText(F("check.sps"), "(import (ironscheme) (ironscheme clr))\n" +
          "(display (guard (e (#t (condition-message e))) (clr-static-call IronScheme.Core.BootInterface Check \"0\")))");
        var r = Host(null, true, "check.sps");
        Assert.That(r.Output, Does.Contain("requires a different boot image"));
    }

    [Test]
    public void FaslPassesILVerify()
    {
        Script("(compile-library \"demo/util.sls\") (compile-program \"prog.sps\")");
        foreach (var f in new[] { F("demo", "util.fasl"), F("prog.fasl") })
        {
            var r = Bootstrap.ILVerify(f);
            Assert.That(r.Output, Does.Contain($"All Classes and Methods in {f} Verified."), r.ToString());
        }
    }
}

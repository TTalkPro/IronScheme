using System;
using System.IO;
using System.Linq;
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

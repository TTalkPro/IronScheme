using System.Diagnostics;
using System.IO;
using NUnit.Framework;

namespace IronScheme.Core.Tests
{
  /// <summary>
  /// 新宿主（iron-029）在 stage1 boot 镜像上的冒烟测试。stage1 由 tools/build-stage1.sh 生成到
  /// IronScheme.Console/build/ironscheme.boot.dll；不存在时跳过。
  /// </summary>
  [Category("Stage1")]
  public class HostTests
  {
    static string TestDir => TestContext.CurrentContext.TestDirectory;
    static string SolutionDir => Path.GetFullPath(Path.Combine(TestDir, "..", "..", "..", ".."));
    static string ConsoleDir => Path.Combine(SolutionDir, "IronScheme.Console");
    static string Boot => Path.Combine(ConsoleDir, "build", "ironscheme.boot.dll");

    static (int Exit, string Out, string Err) Host(string input, params string[] args)
    {
      if (!File.Exists(Boot)) Assert.Ignore("stage1 boot image not built (run tools/build-stage1.sh)");
      var config = new DirectoryInfo(TestDir);
      string host = Path.Combine(SolutionDir, "IronScheme.Host", "bin", config.Parent.Name, config.Name, "IronScheme.Host.dll");
      var psi = new ProcessStartInfo("dotnet")
      {
        WorkingDirectory = ConsoleDir,
        RedirectStandardInput = true,
        RedirectStandardOutput = true,
        RedirectStandardError = true,
      };
      foreach (var a in new[] { host, "--boot", Boot, "-I", "lib" }) psi.ArgumentList.Add(a);
      foreach (var a in args) psi.ArgumentList.Add(a);
      using var p = Process.Start(psi);
      if (input != null) p.StandardInput.Write(input);
      p.StandardInput.Close();
      var err = p.StandardError.ReadToEndAsync();
      string output = p.StandardOutput.ReadToEnd();
      p.WaitForExit();
      return (p.ExitCode, output, err.Result);
    }

    [Test]
    public void SmokeScript()
    {
      var r = Host(null, Path.Combine("tests", "host-smoke.sps"), "arg1");
      Assert.That(r.Exit, Is.EqualTo(0), r.Out + r.Err);
      Assert.That(r.Out, Does.StartWith("hello").And.Contain("host smoke: all checks passed"));
    }

    [Test]
    public void FailingScriptExitsWithOne()
    {
      var script = Path.Combine(Path.GetTempPath(), "iron-host-fail.sps");
      File.WriteAllText(script, "(import (rnrs))\n(display \"before\")\n(newline)\n(car 5)\n");
      var r = Host(null, script);
      Assert.That(r.Exit, Is.EqualTo(1));
      Assert.That(r.Out, Does.Contain("before"));
      Assert.That(r.Out + r.Err, Does.Contain("not a pair"));
    }

    [Test]
    public void Repl()
    {
      var r = Host("(+ 1 2)\n(define (f x)\n  (* x 2))\n(f 21)\n(car 5)\n(string-append \"a\" \"b\")\n");
      Assert.That(r.Exit, Is.EqualTo(0), r.Err);
      Assert.That(r.Out, Does.Contain("> 3").And.Contain("> 42").And.Contain("\"ab\""));
      Assert.That(r.Out + r.Err, Does.Contain("not a pair"));
    }
  }
}

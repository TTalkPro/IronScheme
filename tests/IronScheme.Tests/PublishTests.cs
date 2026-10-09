using System;
using System.IO;
using System.Linq;
using NUnit.Framework;

namespace IronScheme.Tests
{
  /// <summary>
  /// 自包含发布（iron-036，designs/07-tooling-and-embedding.md §3）：用 tools/build.cs publish 发布 IronScheme 宿主
  /// 与示例程序 examples/WordCount，直接运行发布出的可执行文件（不经 dotnet 启动）。
  /// </summary>
  [Order(8)]
  [Category(nameof(Publish))]
  [NonParallelizable]
  public class Publish : TestRunner
  {
    static readonly string Dir = Path.Combine(Path.GetTempPath(), "ironscheme-publish-test");
    static string Exe(string dir, string name) => Path.Combine(dir, OperatingSystem.IsWindows() ? name + ".exe" : name);

    [OneTimeSetUp]
    public void Clean()
    {
      if (Directory.Exists(Dir)) Directory.Delete(Dir, true);
      Directory.CreateDirectory(Dir);
    }

    [OneTimeTearDown]
    public void Remove()
    {
      if (Directory.Exists(Dir)) Directory.Delete(Dir, true);
    }

    static void BuildTool(params string[] args) =>
      RunProcess("dotnet", new[] { "run", Path.Combine(Paths.RepoDir, "tools", "build.cs"), "--" }.Concat(args).ToArray(), null, Paths.RepoDir);

    [Test]
    public void SelfContainedHost()
    {
      string outDir = Path.Combine(Dir, "host");
      BuildTool("publish", "-o", outDir);
      string exe = Exe(outDir, "IronScheme.Host");
      Assert.That(File.Exists(exe), Is.True);
      Assert.That(File.Exists(Path.Combine(outDir, "ironscheme.boot.dll")), Is.False, "boot image is embedded");
      Assert.That(Directory.Exists(Path.Combine(outDir, "lib", "ironscheme")), Is.True, "lib/ next to the executable");

      string script = Path.Combine(Dir, "t.sps");
      File.WriteAllText(script, "(import (rnrs) (ironscheme clr))\n(display (list (+ 1 2) (string? (clr-static-prop-get System.Environment MachineName)) (cdr (command-line))))\n");
      Assert.That(RunProcess(exe, new[] { script, "a", "b" }, null, Dir).Output, Is.EqualTo("(3 #t (a b))"));
      Assert.That(RunProcess(exe, new string[0], "(define (f x) (* x 3))\n(f 14)", Dir).Output, Does.Contain("42"));
    }

    [Test]
    public void StandaloneApplication()
    {
      string outDir = Path.Combine(Dir, "wordcount");
      BuildTool("publish", Path.Combine(Paths.RepoDir, "examples", "WordCount", "wordcount.sps"), "-o", outDir);
      string exe = Exe(outDir, "wordcount");
      Assert.That(File.Exists(exe), Is.True);
      Assert.That(Directory.GetFileSystemEntries(outDir).Select(Path.GetFileName), Is.EquivalentTo(new[] { Path.GetFileName(exe) }), "a single file");

      string text = Path.Combine(Dir, "words.txt");
      File.WriteAllText(text, "the quick brown fox jumps over the lazy dog the end");
      Assert.That(RunProcess(exe, new[] { "-n", "2", text }, null, Dir).Output.Replace("\r", ""), Is.EqualTo("3\tthe\n1\tbrown"));
      // 应用的条件导致非零退出码
      var r = RunProcess(exe, new[] { Path.Combine(Dir, "no-such-file.txt") }, null, Dir, checkExitCode: false);
      Assert.That(r.ExitCode, Is.Not.EqualTo(0));
    }
  }
}

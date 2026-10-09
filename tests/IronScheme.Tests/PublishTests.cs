using System;
using System.IO;
using System.Linq;
using NUnit.Framework;

namespace IronScheme.Tests;

/// <summary>
/// 自包含发布（iron-036，designs/07-tooling-and-embedding.md §3）：用 tools/build.cs publish 发布 IronScheme 宿主
/// 与示例程序 examples/WordCount，直接运行发布出的可执行文件（不经 dotnet 启动）。
/// </summary>
[Order(8)]
[Category(nameof(Publish))]
[NonParallelizable]
public class Publish : TestRunner
{
    private static readonly string s_dir = Path.Combine(Path.GetTempPath(), "ironscheme-publish-test");
    private static string Exe(string dir, string name) => Path.Combine(dir, OperatingSystem.IsWindows() ? name + ".exe" : name);

    [OneTimeSetUp]
    public void Clean()
    {
        if (Directory.Exists(s_dir)) Directory.Delete(s_dir, true);
        Directory.CreateDirectory(s_dir);
    }

    [OneTimeTearDown]
    public void Remove()
    {
        if (Directory.Exists(s_dir)) Directory.Delete(s_dir, true);
    }

    private static void BuildTool(params string[] args) =>
      RunProcess("dotnet", new[] { "run", Path.Combine(Paths.RepoDir, "tools", "build.cs"), "--" }.Concat(args).ToArray(), null, Paths.RepoDir);

    [Test]
    public void SelfContainedHost()
    {
        string outDir = Path.Combine(s_dir, "host");
        BuildTool("publish", "-o", outDir);
        string exe = Exe(outDir, "IronScheme.Host");
        Assert.That(File.Exists(exe), Is.True);
        Assert.That(File.Exists(Path.Combine(outDir, "ironscheme.boot.dll")), Is.False, "boot image is embedded");
        Assert.That(Directory.Exists(Path.Combine(outDir, "lib", "ironscheme")), Is.True, "lib/ next to the executable");

        string script = Path.Combine(s_dir, "t.sps");
        File.WriteAllText(script, "(import (rnrs) (ironscheme clr))\n(display (list (+ 1 2) (string? (clr-static-prop-get System.Environment MachineName)) (cdr (command-line))))\n");
        Assert.That(RunProcess(exe, new[] { script, "a", "b" }, null, s_dir).Output, Is.EqualTo("(3 #t (a b))"));
        Assert.That(RunProcess(exe, new string[0], "(define (f x) (* x 3))\n(f 14)", s_dir).Output, Does.Contain("42"));
    }

    [Test]
    public void StandaloneApplication()
    {
        string outDir = Path.Combine(s_dir, "wordcount");
        BuildTool("publish", Path.Combine(Paths.RepoDir, "examples", "WordCount", "wordcount.sps"), "-o", outDir);
        string exe = Exe(outDir, "wordcount");
        Assert.That(File.Exists(exe), Is.True);
        Assert.That(Directory.GetFileSystemEntries(outDir).Select(Path.GetFileName), Is.EquivalentTo(new[] { Path.GetFileName(exe) }), "a single file");

        string text = Path.Combine(s_dir, "words.txt");
        File.WriteAllText(text, "the quick brown fox jumps over the lazy dog the end");
        Assert.That(RunProcess(exe, new[] { "-n", "2", text }, null, s_dir).Output.Replace("\r", ""), Is.EqualTo("3\tthe\n1\tbrown"));
        // 应用的条件导致非零退出码
        var r = RunProcess(exe, new[] { Path.Combine(s_dir, "no-such-file.txt") }, null, s_dir, checkExitCode: false);
        Assert.That(r.ExitCode, Is.Not.EqualTo(0));
    }
}

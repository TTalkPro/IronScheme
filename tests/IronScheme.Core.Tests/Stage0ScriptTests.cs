using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using NUnit.Framework;

namespace IronScheme.Core.Tests;

/// <summary>
/// 在 stage0 上运行 src/scheme/tests/compiler/*.sps（执行文本种子后运行脚本，退出码 0 为通过）。
/// 以子进程运行：种子会登记运行时钩子等全局状态，不宜放进单元测试进程。
/// </summary>
[Category("Stage0Script")]
public class Stage0ScriptTests
{
    // 测试程序集在 IronScheme/IronScheme.Core.Tests/bin/<配置>/<框架>/
    private static string TestDir => TestContext.CurrentContext.TestDirectory;
    private static string SrcDir => Path.GetFullPath(Path.Combine(TestDir, "..", "..", "..", "..", "..", "src"));
    private static string SchemeDir => Path.Combine(SrcDir, "scheme");

    /// <summary>tests/compiler/*.sps；slow- 开头的（如编译整个种子）归入 Slow 类别，可用 --filter "TestCategory!=Slow" 跳过。</summary>
    public static IEnumerable<TestCaseData> Scripts() =>
      Directory.GetFiles(Path.Combine(Path.GetFullPath(Path.Combine(TestContext.CurrentContext.TestDirectory ?? ".", "..", "..", "..", "..", "..")), "src", "scheme", "tests", "compiler"), "*.sps")
        .Select(Path.GetFileName).OrderBy(n => n)
        .Select(n => { var d = new TestCaseData(n).SetName(n); return n.StartsWith("slow-") ? d.SetCategory("Slow") : d; });

    [TestCaseSource(nameof(Scripts))]
    public void Script(string name)
    {
        var config = new DirectoryInfo(TestDir);
        string stage0 = Path.Combine(SrcDir, "IronScheme.Stage0", "bin", config.Parent.Name, config.Name, "stage0.dll");
        Assert.That(File.Exists(stage0), Is.True, "stage0 not built: " + stage0);
        var psi = new ProcessStartInfo("dotnet")
        {
            WorkingDirectory = SchemeDir,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        };
        foreach (var a in new[] { stage0, "-I", "lib", "-I", Path.Combine("lib", "nanopass-framework-scheme"), Path.Combine("boot", "boot-seed.core"), Path.Combine("tests", "compiler", name) })
            psi.ArgumentList.Add(a);
        using var p = Process.Start(psi);
        var stderr = p.StandardError.ReadToEndAsync();
        string stdout = p.StandardOutput.ReadToEnd();
        p.WaitForExit();
        TestContext.Out.WriteLine(stdout);
        Assert.That(p.ExitCode, Is.EqualTo(0), stdout + stderr.Result);
    }
}

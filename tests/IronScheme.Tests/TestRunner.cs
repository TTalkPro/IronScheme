using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Text;
using NUnit.Framework;

namespace IronScheme.Tests;

/// <summary>路径：测试程序集在 IronScheme/IronScheme.Tests/bin/&lt;配置&gt;/&lt;框架&gt;/。</summary>
internal static class Paths
{
    private static string TestDir => TestContext.CurrentContext.TestDirectory;
    public static string Configuration => new DirectoryInfo(TestDir).Parent.Name;
    public static string Framework => new DirectoryInfo(TestDir).Name;
    /// <summary>仓库根目录（测试目录为 tests/项目/bin/配置/框架）。</summary>
    public static string RepoDir => Path.GetFullPath(Path.Combine(TestDir, "..", "..", "..", "..", ".."));
    public static string SrcDir => Path.Combine(RepoDir, "src");
    /// <summary>运行 Scheme 程序的工作目录 src/scheme（tests/、lib/ 所在处）；可用环境变量 ISWD 覆盖。</summary>
    public static string SchemeDir => Environment.GetEnvironmentVariable("ISWD") ?? Path.Combine(SrcDir, "scheme");
    /// <summary>发现测试用例时（还没有 TestContext）按测试程序集所在目录定位 src/scheme。</summary>
    public static string SchemeDirForDiscovery =>
      Environment.GetEnvironmentVariable("ISWD") ??
      Path.Combine(Path.GetFullPath(Path.Combine(Path.GetDirectoryName(typeof(Paths).Assembly.Location), "..", "..", "..", "..", "..")), "src", "scheme");
    public static string Host => Path.Combine(SrcDir, "IronScheme.Host", "bin", Configuration, Framework, "IronScheme.Host.dll");
    public static string Stage0 => Path.Combine(SrcDir, "IronScheme.Stage0", "bin", Configuration, Framework, "stage0.dll");
    public static string Emit => Path.Combine(SrcDir, "IronScheme.Emit", "bin", Configuration, Framework, "IronScheme.Emit.dll");
    /// <summary>测试使用的 boot 镜像；可用环境变量 IRONSCHEME_BOOT 覆盖。</summary>
    public static string Boot => Environment.GetEnvironmentVariable("IRONSCHEME_BOOT") ?? Path.Combine(SchemeDir, "boot", "ironscheme.boot.dll");
}

[TestFixture]
public abstract class TestRunner
{
    protected void AssertError(TestResult tr)
    {
        Warn.If(tr.Error, Is.Not.Empty, "stderr is not empty");
    }

    protected static string NormalizeLineBreaks(string input)
    {
        using var sr = new StringReader(input);
        using var sw = new StringWriter();
        string line;
        while ((line = sr.ReadLine()) != null) sw.WriteLine(line.Trim('\r', '\n'));
        return sw.ToString().TrimEnd('\r', '\n');
    }

    protected internal class TestResult
    {
        public string Output;
        public string Error;
        public int ExitCode;

        public override string ToString() => $"Output:\n{Output}\nError:\n{Error}";
    }

    protected TestResult RunIronSchemeTestWithInput(string input, [CallerMemberName] string method = null) =>
      RunIronSchemeTest(null, input, method);

    protected TestResult RunIronSchemeTest(string args, [CallerMemberName] string method = null) =>
      RunIronSchemeTest(args, null, method);

    /// <summary>
    /// 用新宿主运行：IronScheme.Host --boot &lt;镜像&gt; -I lib 参数 …；有 input 时作为 REPL 的标准输入（末尾加 (exit)）。
    /// 参数中的 \ 换成 /（测试中沿用旧写法的路径）。
    /// </summary>
    protected internal static TestResult RunIronSchemeTest(string args, string input, [CallerMemberName] string method = null, string boot = null)
    {
        if (!File.Exists(boot ?? Paths.Boot)) Assert.Ignore("boot image not built (run dotnet build in the repository root, or the Bootstrap tests)");
        var argv = new[] { Paths.Host, "--boot", boot ?? Paths.Boot, "-I", "lib" }
          .Concat((args ?? "").Replace('\\', '/').Split(' ', StringSplitOptions.RemoveEmptyEntries)).ToArray();
        return RunProcess("dotnet", argv, input, Paths.SchemeDir);
    }

    protected internal static TestResult RunProcess(string exe, string[] args, string input, string workingDirectory, int timeoutMs = 1800000, bool checkExitCode = true)
    {
        var error = new StringBuilder();
        var output = new StringBuilder();
        var psi = new ProcessStartInfo(exe)
        {
            RedirectStandardOutput = true,
            StandardOutputEncoding = Encoding.UTF8,
            RedirectStandardError = true,
            RedirectStandardInput = true,
            UseShellExecute = false,
            CreateNoWindow = true,
            WorkingDirectory = workingDirectory,
        };
        foreach (var a in args) psi.ArgumentList.Add(a);
        using var p = new Process { StartInfo = psi };
        p.ErrorDataReceived += (s, e) => { if (e.Data != null) lock (error) error.AppendLine(e.Data); };
        p.OutputDataReceived += (s, e) => { if (e.Data != null) lock (output) output.AppendLine(e.Data); };
        Assert.That(p.Start(), Is.True, $"could not start {exe}");
        p.BeginErrorReadLine();
        p.BeginOutputReadLine();
        if (input != null)
        {
            p.StandardInput.WriteLine(input);
            p.StandardInput.WriteLine("(exit)");
        }
        p.StandardInput.Close();
        if (!p.WaitForExit(timeoutMs))
        {
            try { p.Kill(true); } catch (Exception) { }
            Assert.Fail($"{exe} timed out");
        }
        p.WaitForExit();
        var r = new TestResult
        {
            Output = output.ToString().TrimEnd('\r', '\n'),
            Error = error.ToString().TrimEnd('\r', '\n'),
            ExitCode = p.ExitCode,
        };
        if (checkExitCode) Assert.That(p.ExitCode, Is.EqualTo(0), r.ToString());
        return r;
    }
}

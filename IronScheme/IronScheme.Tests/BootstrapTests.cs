using System;
using System.IO;
using System.Linq;
using NUnit.Framework;

namespace IronScheme.Tests
{
  /// <summary>
  /// 自举（iron-030，designs/05-bootstrap.md §3）：
  ///   stage0（文本种子 + 解释器）运行 ironscheme-buildscript-nano.sps → stage1；
  ///   新宿主加载 stage1 运行同一脚本 → stage2；加载 stage2 → stage3。
  /// 判据：stage2 与 stage3 的 Lcil 文本一致、dll 逐字节一致；ILVerify 通过。最后把 stage3 装为工作区的 boot 镜像。
  /// </summary>
  [Order(1)]
  [Category(nameof(Bootstrap))]
  [NonParallelizable]
  public class Bootstrap : TestRunner
  {
    static readonly string Root = Path.Combine(Path.GetTempPath(), "ironscheme-bootstrap");
    static string StageDir(int n) => Path.Combine(Root, "stage" + n);
    static string Dll(int n) => Path.Combine(StageDir(n), "ironscheme.boot.dll");
    static string Lcil(int n) => Path.Combine(StageDir(n), "ironscheme.boot.lcil");

    static readonly string[] BuildArgs = { "-I", "lib", "-I", "lib/nanopass-framework-scheme" };
    const string Script = "ironscheme-buildscript-nano.sps";

    [Test, Order(1)]
    public void Stage1_FromStage0()
    {
      Directory.CreateDirectory(StageDir(1));
      RunProcess("dotnet", new[] { Paths.Stage0 }.Concat(BuildArgs).Concat(new[] { "boot-seed.core", Script, StageDir(1) }).ToArray(), null, Paths.ConsoleDir);
      Assert.That(File.Exists(Dll(1)), Is.True);
    }

    [Test, Order(2)]
    public void Stage2_FromStage1() => BuildWith(1, 2);

    [Test, Order(3)]
    public void Stage3_FromStage2() => BuildWith(2, 3);

    static void BuildWith(int from, int to)
    {
      if (!File.Exists(Dll(from))) Assert.Ignore($"stage{from} not built");
      Directory.CreateDirectory(StageDir(to));
      RunProcess("dotnet", new[] { Paths.Host, "--boot", Dll(from) }.Concat(BuildArgs).Concat(new[] { Script, StageDir(to) }).ToArray(), null, Paths.ConsoleDir);
      Assert.That(File.Exists(Dll(to)), Is.True);
    }

    [Test, Order(4)]
    public void Fixpoint()
    {
      if (!File.Exists(Dll(3))) Assert.Ignore("stage3 not built");
      Assert.That(File.ReadAllText(Lcil(3)), Is.EqualTo(File.ReadAllText(Lcil(2))), "stage2 / stage3 Lcil");
      Assert.That(File.ReadAllBytes(Dll(3)), Is.EqualTo(File.ReadAllBytes(Dll(2))), "stage2 / stage3 dll");
      // stage0 编译出的 stage1 也与之相同（符号哈希只取决于名字、gensym 规范改名，产物与宿主无关）
      Assert.That(File.ReadAllBytes(Dll(1)), Is.EqualTo(File.ReadAllBytes(Dll(2))), "stage1 / stage2 dll");
    }

    [Test, Order(5)]
    public void Verify()
    {
      if (!File.Exists(Dll(3))) Assert.Ignore("stage3 not built");
      var r = ILVerify(Dll(3));
      Assert.That(r.Output, Does.Contain($"All Classes and Methods in {Dll(3)} Verified."), r.ToString());
    }

    [Test, Order(6)]
    public void InstallStage3()
    {
      if (!File.Exists(Dll(3))) Assert.Ignore("stage3 not built");
      Directory.CreateDirectory(Path.GetDirectoryName(Paths.Boot));
      File.Copy(Dll(3), Paths.Boot, true);
      File.Copy(Lcil(3), Path.ChangeExtension(Paths.Boot, ".lcil"), true);
    }

    /// <summary>ILVerify（dotnet tool install -g dotnet-ilverify）；找不到时忽略。</summary>
    internal static TestResult ILVerify(params string[] assemblies)
    {
      var tool = Path.Combine(Environment.GetEnvironmentVariable("HOME") ?? "", ".dotnet", "tools", "ilverify");
      if (!File.Exists(tool)) Assert.Ignore("ilverify not installed");
      var runtimeDir = Path.GetDirectoryName(typeof(object).Assembly.Location);
      var core = Path.Combine(Paths.SolutionDir, "IronScheme.Core", "bin", Paths.Configuration, Paths.Framework);
      var args = assemblies.Concat(new[]
      {
        "-r", Path.Combine(runtimeDir, "*.dll"),
        "-r", Path.Combine(core, "IronScheme.Core.dll"),
        "-r", Path.Combine(core, "Oyster.IntX.dll"),
        "-r", Paths.Emit,
      }).ToArray();
      return RunProcess(tool, args, null, Paths.ConsoleDir, checkExitCode: false);
    }
  }
}

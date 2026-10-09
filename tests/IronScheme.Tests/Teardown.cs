using System;
using System.IO;
using NUnit.Framework;

namespace IronScheme.Tests
{
  [SetUpFixture]
  public class Setup
  {
    [OneTimeSetUp]
    public void RunBeforeAnyTests()
    {
      Cleanup();
      if (File.Exists(Paths.Boot))
      {
        var r = TestRunner.RunIronSchemeTest(null, "(ironscheme-runtime)");
        TestContext.Error.WriteLine($"ironscheme-runtime: {r.Output}");
      }
    }

    /// <summary>删除系统库编译测试生成的 dll（compiled.lst 中列出，相对 src/scheme）。</summary>
    internal static void Cleanup()
    {
      // R6RS 测试中 I/O 用例写出的临时文件
      File.Delete(Path.Combine(Paths.SchemeDir, "tmp1"));
      var list = Path.Combine(Paths.SchemeDir, "compiled.lst");
      if (!File.Exists(list)) return;
      foreach (var lib in File.ReadAllLines(list))
      {
        var path = Path.Combine(Paths.SchemeDir, lib);
        File.Delete(path);
        File.Delete(Path.ChangeExtension(path, "pdb"));
      }
      File.Delete(list);
    }
  }

  [Order(100)]
  [Category(nameof(Teardown))]
  public class Teardown : TestRunner
  {
    [Test]
    public void Run() => Setup.Cleanup();
  }
}

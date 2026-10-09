using System.Collections.Generic;
using System.IO;
using System.Linq;
using NUnit.Framework;

namespace IronScheme.Tests;

/// <summary>
/// (ironscheme std …) 库（designs/08-std-library.md D8）：逐个运行 src/scheme/tests/std/*.sps
/// （每个打印 "名字: all passed (n checks)"），以及 D2 守卫 check-std.sps（std 库与 (ironscheme) 无交集）。
/// </summary>
[Order(3)]
[Category(nameof(Std))]
[Parallelizable(ParallelScope.All)]
public class Std : TestRunner
{
    private static IEnumerable<string> Scripts() =>
      Directory.GetFiles(Path.Combine(Paths.SchemeDirForDiscovery, "tests", "std"), "*.sps")
        .Select(Path.GetFileNameWithoutExtension).OrderBy(n => n);

    [TestCaseSource(nameof(Scripts))]
    public void Run(string script)
    {
        var r = RunIronSchemeTest($"tests/std/{script}.sps");
        Assert.That(r.Output, Does.Not.Contain("FAIL"), r.ToString());
        Assert.That(r.Output, Does.Contain("all passed"), r.ToString());
    }
}

using System;
using System.IO;
using System.Linq;
using NUnit.Framework;

namespace IronScheme.Tests;

/// <summary>
/// 系统库编译（iron-031，对应旧 Bootstrap 中的 Compile / Verify）：compile-system-libraries 把全部系统库
/// （含 (ironscheme std …)、wak）编译成 dll；把 lib 藏起来再运行一次，全部库须能只从 dll 加载；ILVerify 全部通过。
/// 生成的 dll 列在 src/scheme/compiled.lst，Teardown 时删除。
/// </summary>
[Order(5)]
[Category(nameof(SystemLibraries))]
[NonParallelizable]
public class SystemLibraries : TestRunner
{
    // iron-046：删除 srfi、pfds（原 232 个），加入 (ironscheme std …) 46 个与内部库 6 个
    private const int LIBSCOUNT = 126;   // iron-053：加了 (ironscheme async)
    private static string ListFile => Path.Combine(Paths.SchemeDir, "compiled.lst");

    [Test, Order(1)]
    public void Compile()
    {
        Setup.Cleanup();
        var r = RunIronSchemeTest("compile-system-libraries.sps");
        var list = r.Output.Split('\n', StringSplitOptions.RemoveEmptyEntries)
          .Select(l => l.Trim()).Where(l => l.StartsWith("compiling ")).Select(l => l.Substring("compiling ".Length)).ToArray();
        File.WriteAllLines(ListFile, list);
        Assert.That(list, Has.Length.EqualTo(LIBSCOUNT));

        // 没有源码时全部从 dll 加载，不再编译
        var lib = Path.Combine(Paths.SchemeDir, "lib");
        var hidden = Path.Combine(Paths.SchemeDir, "lib.hide");
        Directory.Move(lib, hidden);
        try
        {
            var again = RunIronSchemeTest("compile-system-libraries.sps");
            Assert.That(again.Output, Does.Not.Contain("compiling "));
        }
        finally
        {
            Directory.Move(hidden, lib);
        }
    }

    [Test, Order(2)]
    public void Verify()
    {
        if (!File.Exists(ListFile)) Assert.Ignore("system libraries not compiled");
        var libs = File.ReadAllLines(ListFile).Select(l => Path.Combine(Paths.SchemeDir, l)).ToArray();
        Assert.That(libs, Has.Length.EqualTo(LIBSCOUNT));
        var r = Bootstrap.ILVerify(libs.Concat(new[] { "-r", Path.Combine(Paths.SchemeDir, "*.dll") }).ToArray());
        foreach (var l in libs) Assert.That(r.Output, Does.Contain($"All Classes and Methods in {l} Verified."), r.ToString());
    }
}

using NUnit.Framework;

namespace IronScheme.Tests;

[Order(4)]
[Parallelizable(scope: ParallelScope.All | ParallelScope.Fixtures)]
[Category(nameof(Other))]
public class Other : TestRunner
{
    [Test]
    [Platform(Exclude = "MacOsX")]   // pinvoke 用例按 libc.so.6 / msvcrt 查找 C 运行库
    public void FFI()
    {
        var r = RunIronSchemeTest(@"tests\ffi-test.sps");
        Assert.That(r.Output, Does.Contain("ffi: all passed"));
        AssertError(r);
    }

    [Test]
    public void BaseLibrary()
    {
        // 基础库问题修复的回归测试（iron-054）
        var r = RunIronSchemeTest(@"tests\base-library.sps");
        Assert.That(r.Output, Does.Contain("base-library: all passed"));
        AssertError(r);
    }

    [Test]
    public void Bignums()
    {
        // 大整数：位运算、进制转换、到 flonum 的舍入（iron-059）
        var r = RunIronSchemeTest(@"tests\bignums.sps");
        Assert.That(r.Output, Does.Contain("bignums: all passed"));
        AssertError(r);
    }

    [Test]
    public void UnicodeStrings()
    {
        // 字符串按码点（iron-055）
        var r = RunIronSchemeTest(@"tests\unicode-strings.sps");
        Assert.That(r.Output, Does.Contain("unicode-strings: all passed"));
        AssertError(r);
    }

    [Test]
    public void ReplHooks()
    {
        var r = RunIronSchemeTest(@"tests\repl-hooks.sps");
        Assert.That(r.Output, Does.Contain("repl-hooks: all passed"));
        AssertError(r);
    }

    [Test]
    public void MiniKanren()
    {
        var r = RunIronSchemeTestWithInput(@"(include ""lib/minikanren/mktests.scm"")");
        Assert.That(r.Output, Does.Contain("Ignoring divergent test 10.62"));

        AssertError(r);
    }
}

using NUnit.Framework;

namespace IronScheme.Tests;

/// <summary>异步（designs/10-async.md）：iron-050 的互操作与原语用例；async-lambda 的用例在 iron-053 补。</summary>
[Order(4)]
[Parallelizable(scope: ParallelScope.All | ParallelScope.Fixtures)]
[Category(nameof(Async))]
public class Async : TestRunner
{
    [Test]
    public void Interop()
    {
        var r = RunIronSchemeTest(@"tests\async\interop.sps");
        Assert.That(r.Output, Does.Contain("async-interop: all passed"));
        AssertError(r);
    }
}

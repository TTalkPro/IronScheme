using NUnit.Framework;

namespace IronScheme.Tests;

/// <summary>异步（designs/10-async.md）：iron-050 的互操作与原语用例、iron-052 的状态机用例；库与更多用例在 iron-053 补。</summary>
[Order(4)]
[Parallelizable(scope: ParallelScope.All | ParallelScope.Fixtures)]
[Category(nameof(Async))]
public class Async : TestRunner
{
    [Test]
    public void Basic()
    {
        // iron-049 的测试矩阵改写成 async-lambda：快路径、挂起恢复、循环、dynamic-wind / guard / parameterize 跨 await、深递归、100 × 300 ms
        var r = RunIronSchemeTest(@"tests\async\basic.sps");
        Assert.That(r.Output, Does.Contain("async-basic: all passed"));
        AssertError(r);
    }

    [Test]
    public void Library()
    {
        // (ironscheme async) 库：再导出、for-each-async / map-async、编译期错误、Func<Task<int>> 互操作、失败经 task 传递
        var r = RunIronSchemeTest(@"tests\async\library.sps");
        Assert.That(r.Output, Does.Contain("async-library: all passed"));
        AssertError(r);
    }

    [Test]
    public void Interop()
    {
        var r = RunIronSchemeTest(@"tests\async\interop.sps");
        Assert.That(r.Output, Does.Contain("async-interop: all passed"));
        AssertError(r);
    }
}

using System;
using IronScheme.Core;
using IronScheme.Hosting;
using NUnit.Framework;

namespace IronScheme.Tests;

/// <summary>
/// 嵌入 API（iron-039，designs/07-tooling-and-embedding.md §5）：在测试进程内初始化 IronScheme（boot 镜像随
/// IronScheme.Hosting 复制到测试输出目录），求值、取库导出的过程、强类型委托、条件转为 SchemeError。
/// </summary>
[Order(7)]
[Category(nameof(Hosting))]
[NonParallelizable]
public class Hosting
{
    [OneTimeSetUp]
    public void Init() => SchemeRuntime.Initialize();

    [Test]
    public void EvalInInteractionEnvironment()
    {
        Assert.That(SchemeRuntime.Eval("(+ 1 2)"), Is.EqualTo(3));
        Assert.That(SchemeRuntime.Eval("(define (sq x) (* x x)) (sq 12)"), Is.EqualTo(144));
        Assert.That(SchemeRuntime.Eval("(sq 3)"), Is.EqualTo(9), "definitions persist between calls");
    }

    [Test]
    public void EvalWithImports()
    {
        Assert.That(SchemeRuntime.Eval("(string-upcase \"abc\")", "(rnrs)"), Is.EqualTo("ABC"));
        Assert.That(SchemeRuntime.ToSchemeString(SchemeRuntime.Eval("(map (lambda (x) (* x x)) '(1 2 3))", "(rnrs)")), Is.EqualTo("(1 4 9)"));
    }

    [Test]
    public void LibraryProceduresAndDelegates()
    {
        SchemeRuntime.Eval(@"(library (hosting test)
                             (export double greet)
                             (import (rnrs))
                             (define (double x) (* x 2))
                             (define (greet name) (string-append ""hello, "" name)))");
        var p = SchemeRuntime.GetProcedure("(hosting test)", "double");
        Assert.That(SchemeRuntime.Call(p, 21), Is.EqualTo(42));
        var f = SchemeRuntime.GetFunction<Func<int, int>>("(hosting test)", "double");
        Assert.That(f(50), Is.EqualTo(100));
        var g = SchemeRuntime.GetFunction<Func<string, string>>("(hosting test)", "greet");
        Assert.That(g("C#"), Is.EqualTo("hello, C#"));
        SchemeRuntime.Import("(hosting test)");
        Assert.That(SchemeRuntime.Eval("(double 4)"), Is.EqualTo(8));
    }

    [Test]
    public void ConditionsBecomeSchemeError()
    {
        var e = Assert.Throws<SchemeError>(() => SchemeRuntime.Eval("(car 1)"));
        Assert.That(e.Message, Does.Contain("car"));
        Assert.That(e.Condition, Is.Not.Null);
        SchemeRuntime.Eval(@"(library (hosting fail) (export boom) (import (rnrs)) (define (boom) (error 'boom ""it broke"" 42)))");
        var boom = SchemeRuntime.GetFunction<Func<object>>("(hosting fail)", "boom");
        Assert.That(Assert.Throws<SchemeError>(() => boom()).Message, Does.Contain("it broke"));
    }

    [Test]
    public void ClrValuesAtTheBoundary()
    {
        // 声明为 object 的 CLR 返回值按运行时类型转为 Scheme 数（装箱的 Int64 等）
        Assert.That(SchemeRuntime.Eval("(import (ironscheme clr)) (number? (clr-static-call System.Convert (ToInt64 Object) 5))"), Is.EqualTo(true));
        Assert.That(SchemeRuntime.Eval("(+ 1 (clr-static-call System.Convert (ChangeType Object System.Type) 41 (clr-type-of System.Int64)))"), Is.EqualTo(42));
    }
}

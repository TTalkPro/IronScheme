using NUnit.Framework;
using IronScheme.Core;
using IntX = Oyster.Math.IntX;

namespace IronScheme.Core.Tests
{
  public class NumbersTests
  {
    [Test]
    public void FixnumArithmeticStaysFixnum()
    {
      Assert.That(Builtins.Add(1, 2), Is.EqualTo(3).And.InstanceOf<int>());
      Assert.That(Builtins.Subtract(1, 2), Is.EqualTo(-1));
      Assert.That(Builtins.Multiply(6, 7), Is.EqualTo(42));
    }

    [Test]
    public void OverflowPromotesToBignum()
    {
      var r = Builtins.Add(int.MaxValue, 1);
      Assert.That(r, Is.InstanceOf<IntX>());
      Assert.That(r.ToString(), Is.EqualTo("2147483648"));
      var m = Builtins.Multiply(int.MaxValue, int.MaxValue);
      Assert.That(m.ToString(), Is.EqualTo("4611686014132420609"));
    }

    [Test]
    public void BignumDemotesWhenSmall()
    {
      var big = Builtins.Add(int.MaxValue, 1);
      Assert.That(Builtins.Subtract(big, 1), Is.EqualTo(int.MaxValue).And.InstanceOf<int>());
    }

    [Test]
    public void ExactDivisionGivesFraction()
    {
      var r = Builtins.Divide(1, 3);
      Assert.That(r, Is.InstanceOf<Fraction>());
      Assert.That(Builtins.Multiply(r, 3), Is.EqualTo(1));
      Assert.That(Builtins.Divide(6, 3), Is.EqualTo(2).And.InstanceOf<int>());
    }

    [Test]
    public void InexactContagion()
    {
      Assert.That(Builtins.Add(1, 0.5), Is.EqualTo(1.5));
      Assert.That(Builtins.Divide(1.0, 4), Is.EqualTo(0.25));
    }

    [Test]
    public void ComplexArithmetic()
    {
      var i = Complex64.Make(0, 1);
      var r = Builtins.Multiply(i, i);
      Assert.That(r, Is.EqualTo(-1.0));
    }

    [Test]
    public void FxInternalReturnsFalseOnOverflow()
    {
      Assert.That(Builtins.FxPlusInternal(1, 2), Is.EqualTo(3));
      Assert.That(Builtins.FxPlusInternal(int.MaxValue, 1), Is.SameAs(RT.False));
      Assert.That(Builtins.FxMultiplyInternal(65536, 65536), Is.SameAs(RT.False));
      Assert.That(Builtins.FxShiftLeftInternal(1, 31), Is.SameAs(RT.False));
    }

    [Test]
    public void Comparisons()
    {
      Assert.That(Builtins.ExactCompare(1, 2), Is.LessThan(0));
      Assert.That(Builtins.ExactCompare(Builtins.Divide(1, 2), Builtins.Divide(1, 3)), Is.GreaterThan(0));
      Assert.That(Builtins.InexactEqual(1.0, 1), Is.SameAs(RT.True));
    }

    [Test]
    public void BignumSqrtAndDecompose()
    {
      var big = Builtins.Multiply(Builtins.Add(int.MaxValue, 1), Builtins.Add(int.MaxValue, 1));
      // 对应 exact-integer-sqrt：返回 (平方根, 余数) 两个值
      var sr = ((MultipleValues)Builtins.ExactSqrtBigInteger(big)).ToArray(2);
      Assert.That(sr[0].ToString(), Is.EqualTo("2147483648"));
      Assert.That(sr[1], Is.EqualTo(0));
      var parts = Builtins.DecomposeFlonum(1.5);
      Assert.That(parts, Is.InstanceOf<MultipleValues>());
    }
  }
}

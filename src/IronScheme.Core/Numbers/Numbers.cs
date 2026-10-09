#region License
/* Copyright (c) 2007-2016 Llewellyn Pritchard
 * All rights reserved.
 * This source code is subject to terms and conditions of the BSD License.
 * See docs/license.txt. */
#endregion

using System;
using System.Diagnostics;
using System.Globalization;
using BigInteger = System.Numerics.BigInteger;


namespace IronScheme.Core;

public partial class Builtins
{
    [Primitive("decompose-flonum")]
    public static object DecomposeFlonum(object flonum)
    {
        double d = (double)flonum;

        BigInteger mantissa;
        BigInteger exponent;
        bool res = d.GetMantissaAndExponent(out mantissa, out exponent);

        if (res)
        {
            return Control.Values(flonum, mantissa, exponent);
        }
        else
        {
            return FALSE;
        }
    }

    // string->number 由 iron-010 以手写数字解析器重新实现（旧版依赖 gppg 生成的解析器）

    [Primitive("inexact=?", Flags = PrimitiveFlags.Pure)]
    public static object InexactEqual(object a, object b)
    {
        return GetBool(ConvertToComplex(a) == ConvertToComplex(b));
    }

    public static int ExactCompare(object a, object b)
    {
        NumberClass f = GetNumberClass(a);
        NumberClass s = GetNumberClass(b);

        NumberClass effective = f & s;

        switch (effective)
        {
            case NumberClass.Integer:
                return ((int)a).CompareTo((int)b);
            case NumberClass.BigInteger:
                return ConvertToBigInteger(a).CompareTo(ConvertToBigInteger(b));
            case NumberClass.Rational:
                return ConvertToRational(a).CompareTo(ConvertToRational(b));

            default:
                AssertionViolation("exact-compare", "not exact", a, b);
                // never reached
                return 0;
        }
    }

    public static int InexactCompare(object a, object b)
    {
        NumberClass f = GetNumberClass(a);
        NumberClass s = GetNumberClass(b);

        NumberClass effective = f & s;

        switch (effective)
        {
            case NumberClass.Real:
                return ((double)a).CompareTo(b);
            default:
                AssertionViolation("inexact-compare", "not a real", a, b);
                // never reached
                return 0;
        }
    }

    private static bool IsExact(object obj)
    {
        return obj is int ||
               obj is BigInteger ||
               obj is Fraction ||
               obj is ComplexFraction;
    }

    #region math

    [Primitive("fx+internal", Flags = PrimitiveFlags.Pure)]
    public static object FxPlusInternal(object ao, object bo)
    {
        int a = (int)ao, b = (int)bo;
        long r = (long)a + b;
        int rr = (int)r;
        if (r != rr)
        {
            return FALSE;
        }
        return RT.Box(rr);
    }

    [Primitive("fx-internal", Flags = PrimitiveFlags.Pure)]
    public static object FxMinusInternal(object ao, object bo)
    {
        int a = (int)ao, b = (int)bo;
        long r = (long)a - b;
        int rr = (int)r;
        if (r != rr)
        {
            return FALSE;
        }
        return RT.Box(rr);
    }

    [Primitive("fx*internal", Flags = PrimitiveFlags.Pure)]
    public static object FxMultiplyInternal(object ao, object bo)
    {
        int a = (int)ao, b = (int)bo;
        long r = (long)a * b;
        int rr = (int)r;
        if (r != rr)
        {
            return FALSE;
        }
        return RT.Box(rr);
    }

    [Primitive("fxarithmetic-shift-left-internal", Flags = PrimitiveFlags.Pure)]
    public static object FxShiftLeftInternal(object ao, object bo)
    {
        int a = (int)ao, b = (int)bo;
        long r = (long)a << b;
        int rr = (int)r;
        if (r != rr)
        {
            return FALSE;
        }
        return RT.Box(rr);
    }

    private enum NumberClass
    {
        Complex = 1,
        Real = 2 | Complex,
        Rational = 4 | Real,
        BigInteger = 8 | Rational,
        Integer = 16 | BigInteger,
        NotANumber = 0
    }

    private static NumberClass GetNumberClass(object obj)
    {
        if (obj is int)
        {
            return NumberClass.Integer;
        }
        else if (obj is double)
        {
            return NumberClass.Real;
        }
        else if (obj is BigInteger)
        {
            return NumberClass.BigInteger;
        }
        else if (obj is Fraction)
        {
            return NumberClass.Rational;
        }
        else if (obj is Complex64 || obj is ComplexFraction)
        {
            return NumberClass.Complex;
        }
        else
        {
            RaiseNumberTypeNotSupported();
            return NumberClass.NotANumber;
        }
    }

    private static int ConvertToInteger(object o)
    {
        if (o is int)
        {
            return (int)o;
        }
        RaiseNumberTypeNotSupported();
        return default(int);
    }

    private static void RaiseNumberTypeNotSupported()
    {
        throw new NotSupportedException("number type not supported");
    }

    protected internal static BigInteger ConvertToBigInteger(object o)
    {
        if (o is int)
        {
            return (int)o;
        }
        if (o is BigInteger)
        {
            return (BigInteger)o;
        }
        RaiseNumberTypeNotSupported();
        return default(int);
    }

    private static Fraction ConvertToRational(object o)
    {
        if (o is int)
        {
            return (int)o;
        }
        if (o is Fraction)
        {
            return (Fraction)o;
        }
        if (o is BigInteger)
        {
            return new Fraction((BigInteger)o, 1);
        }
        if (o is double)
        {
            return (Fraction)(double)o;
        }
        RaiseNumberTypeNotSupported();
        return default(int);
    }

    private static double ConvertToReal(object o)
    {
        return SafeConvert(o);
    }

    private static Complex64 ConvertToComplex(object o)
    {
        if (o is Complex64)
        {
            return (Complex64)o;
        }
        else if (o is ComplexFraction)
        {
            return (ComplexFraction)o;
        }
        else
        {
            return Complex64.MakeReal(ConvertToReal(o));
        }
    }

    private static ComplexFraction ConvertToComplexFraction(object o)
    {
        if (o is ComplexFraction)
        {
            return (ComplexFraction)o;
        }
        else if (o is int)
        {
            return new ComplexFraction((int)o);
        }
        else if (o is BigInteger)
        {
            return new ComplexFraction((BigInteger)o);
        }
        else
        {
            return new ComplexFraction((Fraction)o);
        }
    }

    [Primitive("generic+", Flags = PrimitiveFlags.Pure)]
    public static object Add(object first, object second)
    {
        NumberClass f = GetNumberClass(first);
        NumberClass s = GetNumberClass(second);

        NumberClass effective = f & s;

        switch (effective)
        {
            case NumberClass.Integer:
                {
                    long result = (long)ConvertToInteger(first) + ConvertToInteger(second);
                    int iresult = (int)result;
                    if (result != iresult)
                    {
                        return (BigInteger)result;
                    }
                    else
                    {
                        return RT.Box(iresult);
                    }
                }
            case NumberClass.BigInteger:
                return ToIntegerIfPossible(ConvertToBigInteger(first) + ConvertToBigInteger(second));
            case NumberClass.Rational:
                return IntegerIfPossible(ConvertToRational(first) + ConvertToRational(second));
            case NumberClass.Real:
                return ConvertToReal(first) + ConvertToReal(second);
            case NumberClass.Complex:
                if (IsExact(first) && IsExact(second))
                {
                    return IntegerIfPossible(ConvertToComplexFraction(first) + ConvertToComplexFraction(second));
                }
                return DoubleIfPossible(ConvertToComplex(first) + ConvertToComplex(second));
        }

        RaiseNumberTypeNotSupported();
        return null;
    }

    /// <summary>
    /// (- x)：fixnum、flonum、bignum 直接取负（(- 0.0) 为 -0.0；bignum 取负只翻转符号、共享数位，iron-059），
    /// 其余按 (* -1 x)（iron-033）。
    /// </summary>
    [Primitive("generic-negate", Flags = PrimitiveFlags.Pure)]
    public static object Negate(object x) => x switch
    {
        int i when i != int.MinValue => RT.Box(-i),
        double d => -d,
        BigInteger b => ToIntegerIfPossible(-b),
        _ => Multiply(-1, x)
    };

    [Primitive("generic-", Flags = PrimitiveFlags.Pure)]
    public static object Subtract(object first, object second)
    {
        NumberClass f = GetNumberClass(first);
        NumberClass s = GetNumberClass(second);

        NumberClass effective = f & s;

        switch (effective)
        {
            case NumberClass.Integer:
                {
                    long result = (long)ConvertToInteger(first) - ConvertToInteger(second);
                    int iresult = (int)result;
                    if (result != iresult)
                    {
                        return (BigInteger)result;
                    }
                    else
                    {
                        return RT.Box(iresult);
                    }
                }
            case NumberClass.BigInteger:
                return ToIntegerIfPossible(ConvertToBigInteger(first) - ConvertToBigInteger(second));
            case NumberClass.Rational:
                return IntegerIfPossible(ConvertToRational(first) - ConvertToRational(second));
            case NumberClass.Real:
                return ConvertToReal(first) - ConvertToReal(second);
            case NumberClass.Complex:
                if (IsExact(first) && IsExact(second))
                {
                    return IntegerIfPossible(ConvertToComplexFraction(first) - ConvertToComplexFraction(second));
                }
                return DoubleIfPossible(ConvertToComplex(first) - ConvertToComplex(second));
        }

        RaiseNumberTypeNotSupported();
        return null;
    }

    [Primitive("generic*", Flags = PrimitiveFlags.Pure)]
    public static object Multiply(object first, object second)
    {
        NumberClass f = GetNumberClass(first);
        NumberClass s = GetNumberClass(second);

        NumberClass effective = f & s;

        switch (effective)
        {
            case NumberClass.Integer:
                {
                    long result = (long)ConvertToInteger(first) * ConvertToInteger(second);
                    int iresult = (int)result;
                    if (result != iresult)
                    {
                        return (BigInteger)result;
                    }
                    else
                    {
                        return RT.Box(iresult);
                    }
                }
            case NumberClass.BigInteger:
                return ToIntegerIfPossible(ConvertToBigInteger(first) * ConvertToBigInteger(second));
            case NumberClass.Rational:
                return IntegerIfPossible(ConvertToRational(first) * ConvertToRational(second));
            case NumberClass.Real:
                return ConvertToReal(first) * ConvertToReal(second);
            case NumberClass.Complex:
                if (IsExact(first) && IsExact(second))
                {
                    return IntegerIfPossible(ConvertToComplexFraction(first) * ConvertToComplexFraction(second));
                }
                return DoubleIfPossible(ConvertToComplex(first) * ConvertToComplex(second));
        }

        RaiseNumberTypeNotSupported();
        return null;
    }


    protected internal static object ToIntegerIfPossible(BigInteger i)
    {
        if (i.IsInt32())
        {
            return RT.Box((int)i);
        }
        else
        {
            return i;
        }
    }

    [Primitive("generic/", Flags = PrimitiveFlags.Pure)]
    public static object Divide(object first, object second)
    {
        NumberClass f = GetNumberClass(first);
        NumberClass s = GetNumberClass(second);

        NumberClass effective = f & s;

        try
        {
            switch (effective)
            {
                case NumberClass.Integer:
                case NumberClass.BigInteger:
                    return IntegerIfPossible(new Fraction(ConvertToBigInteger(first), ConvertToBigInteger(second)));
                case NumberClass.Rational:
                    return IntegerIfPossible(ConvertToRational(first) / ConvertToRational(second));
                case NumberClass.Real:
                    return ConvertToReal(first) / ConvertToReal(second);
                case NumberClass.Complex:
                    if (IsExact(first) && IsExact(second))
                    {
                        return IntegerIfPossible(ConvertToComplexFraction(first) / ConvertToComplexFraction(second));
                    }
                    return DoubleIfPossible(ConvertToComplex(first) / ConvertToComplex(second));
            }
        }
        catch (DivideByZeroException)
        {
            return AssertionViolation("/", "divide by zero", first);
        }

        RaiseNumberTypeNotSupported();
        return null;
    }

    [Primitive("generic-div", Flags = PrimitiveFlags.Pure)]
    public static object Div(object first, object second)
    {
        NumberClass f = GetNumberClass(first);
        NumberClass s = GetNumberClass(second);

        NumberClass effective = f & s;

        try
        {
            switch (effective)
            {
                case NumberClass.Integer:
                    {
                        long ff = ConvertToInteger(first);
                        long ss = ConvertToInteger(second);
                        var ffa = Math.Abs(ff);
                        var ssa = Math.Abs(ss);
                        long r = ffa / ssa;
                        if (ff < 0 && ffa != ssa * r)
                        {
                            r++;
                        }
                        if (ff < 0 ^ ss < 0)
                        {
                            r = -r;
                        }
                        return ToIntegerIfPossible(r);
                    }
                case NumberClass.BigInteger:
                    {
                        var ff = ConvertToBigInteger(first);
                        var ss = ConvertToBigInteger(second);
                        var ffa = BigInteger.Abs(ff);
                        var ssa = BigInteger.Abs(ss);
                        var r = ffa / ssa;
                        if (ff.Sign < 0 && ffa != ssa * r)
                        {
                            r++;
                        }
                        if ((ff.Sign < 0) ^ (ss.Sign < 0))
                        {
                            r = -r;
                        }
                        return ToIntegerIfPossible(r);
                    }
                case NumberClass.Rational:
                    {
                        var ff = ConvertToRational(first);
                        var ss = ConvertToRational(second);
                        var ffa = ff.Abs();
                        var ssa = ss.Abs();
                        var r = ffa / ssa;
                        var br = r.Numerator / r.Denominator;

                        if (ff < 0 && r.Numerator != r.Denominator * br)
                        {
                            br++;
                        }
                        if (ff < 0 ^ ss < 0)
                        {
                            br = -br;
                        }
                        return IntegerIfPossible(br);
                    }
                case NumberClass.Real:
                    {
                        var ff = ConvertToReal(first);
                        var ss = ConvertToReal(second);

                        var ffa = Math.Abs(ff);
                        var ssa = Math.Abs(ss);
                        var r = ffa / ssa;
                        r = Math.Floor(r);
                        if (ff < 0 && !double.IsInfinity(ss) && ffa != ssa * r)
                        {
                            r++;
                        }

                        if (ff < 0 ^ ss < 0)
                        {
                            r = -r;
                        }

                        return r;
                    }
            }
        }
        catch (DivideByZeroException)
        {
            return AssertionViolation("/", "divide by zero", first);
        }

        RaiseNumberTypeNotSupported();
        return null;
    }

    #endregion

    private static double SafeConvert(object obj)
    {
        try
        {
            if (obj is int)
            {
                return (int)obj;
            }
            if (obj is double)
            {
                return (double)obj;
            }
            if (obj is BigInteger)
            {
                return ((BigInteger)obj).ToFloat64();
            }
            if (obj is Fraction)
            {
                return ((Fraction)obj).ToDouble(null);
            }
            if (obj is Complex64)
            {
                Complex64 c = (Complex64)obj;
                if (c.Imag == 0.0)
                {
                    return c.Real;
                }
                else
                {
                    return (double)AssertionViolation(GetCaller(), "no conversion to real possible", obj);
                }
            }
            //System.Diagnostics.Trace.Assert(!(obj is string));
            return Convert.ToDouble(obj, CultureInfo.InvariantCulture);
        }
        catch (OverflowException)
        {
            var i = (BigInteger)obj;
            return i < 0 ? double.NegativeInfinity : double.PositiveInfinity;
        }
    }

    // todo: this can probably be easily ported to Scheme
    //based on lsqrt()
    [Primitive("bignum-sqrt", Flags = PrimitiveFlags.Pure)]
    public static object SqrtBigInteger(object num)
    {
        BigInteger x = (BigInteger)num;
        BigInteger v0, q0, x1;

        if (x <= 1)
        {
            return x;
        }

        v0 = x;
        x = x / 2;
        while (true)
        {
            q0 = v0 / x;
            x1 = (x + q0) / 2;
            if (q0 >= x)
                break;
            x = x1;
        }
        if (x1 * x1 != v0)
        {
            return Math.Sqrt(v0.ToFloat64());
        }
        return x1;
    }

    // todo: this can probably be easily ported to Scheme
    [Primitive("bignum-sqrt-exact", Flags = PrimitiveFlags.Pure)]
    public static object ExactSqrtBigInteger(object num)
    {
        BigInteger x = (BigInteger)num;
        BigInteger v0, q0, x1;

        if (x <= 1)
        {
            return x;
        }

        v0 = x;
        x = x / 2;
        while (true)
        {
            q0 = v0 / x;
            x1 = (x + q0) / 2;
            if (q0 >= x)
                break;
            x = x1;
        }
        q0 = x1 * x1;

        if (q0 > v0)
        {
            x1 = x1 - 1;
            q0 = x1 * x1;
        }
        return Values(ToIntegerIfPossible(x1), ToIntegerIfPossible(v0 - q0));
    }

    private static object DoubleIfPossible(object res)
    {
        if (res is Complex64)
        {
            var c = (Complex64)res;
            if (c.Imag == 0)
            {
                return c.Real;
            }
        }
        return res;
    }

    // improve actually
    private static object IntegerIfPossible(object res)
    {
        if (res is BigInteger)
        {
            return ToIntegerIfPossible((BigInteger)res);
        }
        else if (res is Fraction)
        {
            Fraction f = (Fraction)res;
            if (f.Denominator == 1)
            {
                return ToIntegerIfPossible(f.Numerator);
            }
        }
        else if (res is ComplexFraction)
        {
            ComplexFraction cf = (ComplexFraction)res;
            if (cf.Imag == 0)
            {
                return IntegerIfPossible(cf.Real);
            }
        }
        return res;
    }
}

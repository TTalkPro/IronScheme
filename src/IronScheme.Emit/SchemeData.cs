using System;
using System.Collections.Generic;
using System.Linq.Expressions;
using System.Reflection;
using System.Text;

namespace IronScheme.Emit;

/// <summary>
/// eval 的快速路径（iron-033）：编译器产出的 Lcil S 表达式（IronScheme.Core 的 Cons、Symbol 等）直接转成 SNode，
/// 不经"写成文本再读回"。发射器不引用 IronScheme.Core（04 §1），这里按类型全名识别，用表达式树生成字段读取器。
/// 可以出现的原子与 write-lcil-datum（compiler/constants.sls）一致：符号、字符串、精确整数、flonum、#t/#f、空表。
/// </summary>
internal static class SchemeData
{
    private static Type s_consType, s_symbolType;
    private static Func<object, object> s_car, s_cdr;
    private static Func<object, string> s_symbolName;

    private static Func<object, T> Getter<T>(Type t, string field)
    {
        var o = Expression.Parameter(typeof(object), "o");
        var f = t.GetField(field, BindingFlags.Public | BindingFlags.Instance) ?? throw new LcilException($"{t.FullName}.{field} not found");
        return Expression.Lambda<Func<object, T>>(Expression.Convert(Expression.Field(Expression.Convert(o, t), f), typeof(T)), o).Compile();
    }

    private static void Init(Assembly core)
    {
        if (s_consType != null) return;
        s_symbolType = core.GetType("IronScheme.Core.Symbol", true);
        s_symbolName = Getter<string>(s_symbolType, "Name");
        s_car = Getter<object>(core.GetType("IronScheme.Core.Cons", true), "car");
        s_cdr = Getter<object>(core.GetType("IronScheme.Core.Cons", true), "cdr");
        s_consType = core.GetType("IronScheme.Core.Cons", true);
    }

    public static SNode Convert(object x, Assembly core)
    {
        Init(core);
        return Node(x);
    }

    private static SNode Node(object x)
    {
        switch (x)
        {
            case null: return new SList();
            case string s: return new SStr(s);
            case StringBuilder sb: return new SStr(sb.ToString());
            case bool b: return new SBool(b);
            case int i: return new SInt(i);
            case long l: return new SInt(l);
            case double d: return new SReal(d);
        }
        var t = x.GetType();
        // Scheme 字符串的另一种表示（可变串、含 BMP 外字符的串，iron-055）：取其 UTF-16 文本
        if (t.FullName == "IronScheme.Core.SchemeString") return new SStr(x.ToString());
        if (t == s_consType)
        {
            var l = new SList();
            object p = x;
            while (p != null)
            {
                if (p.GetType() != s_consType) throw new LcilException("improper list in Lcil data");
                l.Items.Add(Node(s_car(p)));
                p = s_cdr(p);
            }
            return l;
        }
        if (t == s_symbolType) return new SSym(s_symbolName(x));
        // bignum：Lcil 中的整数操作数都在 long 范围内
        if (x is System.Numerics.BigInteger big && big >= long.MinValue && big <= long.MaxValue) return new SInt((long)big);
        throw new LcilException("cannot convert to Lcil: " + t.FullName);
    }
}

using System;
using System.Collections.Generic;
using System.Linq.Expressions;
using System.Reflection;
using System.Text;

namespace IronScheme.Emit
{
  /// <summary>
  /// eval 的快速路径（iron-033）：编译器产出的 Lcil S 表达式（IronScheme.Core 的 Cons、Symbol 等）直接转成 SNode，
  /// 不经"写成文本再读回"。发射器不引用 IronScheme.Core（04 §1），这里按类型全名识别，用表达式树生成字段读取器。
  /// 可以出现的原子与 write-lcil-datum（compiler/constants.sls）一致：符号、字符串、精确整数、flonum、#t/#f、空表。
  /// </summary>
  static class SchemeData
  {
    static Type consType, symbolType;
    static Func<object, object> car, cdr;
    static Func<object, string> symbolName;

    static Func<object, T> Getter<T>(Type t, string field)
    {
      var o = Expression.Parameter(typeof(object), "o");
      var f = t.GetField(field, BindingFlags.Public | BindingFlags.Instance) ?? throw new LcilException($"{t.FullName}.{field} not found");
      return Expression.Lambda<Func<object, T>>(Expression.Convert(Expression.Field(Expression.Convert(o, t), f), typeof(T)), o).Compile();
    }

    static void Init(Assembly core)
    {
      if (consType != null) return;
      symbolType = core.GetType("IronScheme.Core.Symbol", true);
      symbolName = Getter<string>(symbolType, "Name");
      car = Getter<object>(core.GetType("IronScheme.Core.Cons", true), "car");
      cdr = Getter<object>(core.GetType("IronScheme.Core.Cons", true), "cdr");
      consType = core.GetType("IronScheme.Core.Cons", true);
    }

    public static SNode Convert(object x, Assembly core)
    {
      Init(core);
      return Node(x);
    }

    static SNode Node(object x)
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
      if (t == consType)
      {
        var l = new SList();
        object p = x;
        while (p != null)
        {
          if (p.GetType() != consType) throw new LcilException("improper list in Lcil data");
          l.Items.Add(Node(car(p)));
          p = cdr(p);
        }
        return l;
      }
      if (t == symbolType) return new SSym(symbolName(x));
      // bignum（Oyster.IntX）：Lcil 中的整数操作数都在 long 范围内
      if (t.FullName == "Oyster.Math.IntX" && long.TryParse(x.ToString(), out var big)) return new SInt(big);
      throw new LcilException("cannot convert to Lcil: " + t.FullName);
    }
  }
}

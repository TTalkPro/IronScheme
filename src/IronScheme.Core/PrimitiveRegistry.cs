using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;

namespace IronScheme.Core
{
  /// <summary>一个原语的一个 C# 重载。</summary>
  public sealed class PrimitiveOverload
  {
    public MethodInfo Method { get; }
    public PrimitiveAttribute Attribute { get; }
    /// <summary>固定参数个数（不含 params 数组）。</summary>
    public int FixedArity { get; }
    /// <summary>最后一个参数是否为 params object[]。</summary>
    public bool HasRest { get; }

    internal PrimitiveOverload(MethodInfo m, PrimitiveAttribute a)
    {
      Method = m;
      Attribute = a;
      var ps = m.GetParameters();
      HasRest = ps.Length > 0 && ps[^1].IsDefined(typeof(ParamArrayAttribute), false);
      FixedArity = HasRest ? ps.Length - 1 : ps.Length;
    }
  }

  /// <summary>
  /// 原语登记表：扫描 IronScheme.Core 中所有 [Primitive] 方法，包装成 <see cref="PrimitiveProcedure"/>，
  /// 写入名字符号的值槽。不在运行时生成 IL（只用 Delegate.CreateDelegate）。
  /// 约定：参数与返回值都是 object；最后一个参数可以是 params object[]。设计：designs/02-runtime.md §5。
  /// </summary>
  public static class PrimitiveRegistry
  {
    static readonly object gate = new object();
    static Dictionary<string, List<PrimitiveOverload>> table;

    /// <summary>按名字分组的全部原语（按名字排序）。PrimGen 也使用它。</summary>
    public static IReadOnlyDictionary<string, List<PrimitiveOverload>> All
    {
      get { lock (gate) return table ??= Scan(typeof(PrimitiveRegistry).Assembly); }
    }

    public static Dictionary<string, List<PrimitiveOverload>> Scan(Assembly asm)
    {
      var result = new SortedDictionary<string, List<PrimitiveOverload>>(StringComparer.Ordinal);
      var problems = new List<string>();

      foreach (var type in asm.GetTypes())
        foreach (var m in type.GetMethods(BindingFlags.Public | BindingFlags.Static | BindingFlags.DeclaredOnly))
          foreach (PrimitiveAttribute a in m.GetCustomAttributes(typeof(PrimitiveAttribute), false))
          {
            var o = new PrimitiveOverload(m, a);
            string sig = $"{type.FullName}.{m.Name}";
            if (m.ReturnType != typeof(object)) problems.Add($"{a.Name}: {sig} must return object");
            var ps = m.GetParameters();
            for (int i = 0; i < ps.Length; i++)
            {
              bool ok = (o.HasRest && i == ps.Length - 1) ? ps[i].ParameterType == typeof(object[]) : ps[i].ParameterType == typeof(object);
              if (!ok) problems.Add($"{a.Name}: {sig} parameter '{ps[i].Name}' must be object");
            }
            if (!result.TryGetValue(a.Name, out var list)) result[a.Name] = list = new List<PrimitiveOverload>();
            if (list.Any(x => x.FixedArity == o.FixedArity && x.HasRest == o.HasRest))
              problems.Add($"{a.Name}: duplicate overload with {o.FixedArity} fixed arguments ({sig})");
            list.Add(o);
          }

      if (problems.Count > 0)
        throw new InvalidOperationException("invalid primitives:\n  " + string.Join("\n  ", problems));
      return new Dictionary<string, List<PrimitiveOverload>>(result, StringComparer.Ordinal);
    }

    /// <summary>把全部原语写入各自名字符号的值槽。可重复调用。</summary>
    public static int RegisterAll()
    {
      int n = 0;
      foreach (var kv in All)
      {
        Symbol.Intern(kv.Key).Value = new PrimitiveProcedure(kv.Key, kv.Value);
        n++;
      }
      return n;
    }
  }

  /// <summary>原语的过程包装：按参数个数选择重载。</summary>
  public sealed class PrimitiveProcedure : VariadicProcedure
  {
    readonly string name;
    readonly Func<object> f0;
    readonly Func<object, object> f1;
    readonly Func<object, object, object> f2;
    readonly Func<object, object, object, object> f3;
    readonly Func<object, object, object, object, object> f4;
    readonly (int Fixed, bool HasRest, Func<object[], object> Call)[] others;   // params 重载与 >4 个固定参数的重载

    public override string Name => name;

    public IReadOnlyList<PrimitiveOverload> Overloads { get; }

    object form, arity;

    /// <summary>procedure-form：各重载的 (名字 . 形参)，形参取 C# 参数名，params 数组为剩余参数（REPL 的参数提示，iron-038）。</summary>
    public override object Form => form ??= Cons.FromArray(Overloads.OrderBy(o => o.FixedArity).ThenBy(o => o.HasRest).Select(o =>
    {
      var ps = o.Method.GetParameters();
      object formals = o.HasRest ? Symbol.Intern(ps[^1].Name) : null;
      for (int i = o.FixedArity - 1; i >= 0; i--) formals = new Cons(Symbol.Intern(ps[i].Name), formals);
      return (object)new Cons(Symbol.Intern(name), formals);
    }).ToArray());

    /// <summary>procedure-arity：与编译器生成的一致（固定 n，剩余参数 n.0，多个重载为列表）。</summary>
    public override object Arity => arity ??= Overloads.Count == 1
      ? ArityOf(Overloads[0])
      : Cons.FromArray(Overloads.OrderBy(o => o.FixedArity).Select(ArityOf).ToArray());

    static object ArityOf(PrimitiveOverload o) => o.HasRest ? (object)(double)o.FixedArity : RT.Box(o.FixedArity);

    public PrimitiveProcedure(string name, IReadOnlyList<PrimitiveOverload> overloads)
    {
      this.name = name;
      Overloads = overloads;
      var rest = new List<(int, bool, Func<object[], object>)>();
      foreach (var o in overloads)
      {
        var m = o.Method;
        if (!o.HasRest)
        {
          switch (o.FixedArity)
          {
            case 0: f0 = m.CreateDelegate<Func<object>>(); continue;
            case 1: f1 = m.CreateDelegate<Func<object, object>>(); continue;
            case 2: f2 = m.CreateDelegate<Func<object, object, object>>(); continue;
            case 3: f3 = m.CreateDelegate<Func<object, object, object, object>>(); continue;
            case 4: f4 = m.CreateDelegate<Func<object, object, object, object, object>>(); continue;
          }
        }
        rest.Add((o.FixedArity, o.HasRest, MakeArrayCall(o)));
      }
      // 剩余参数重载按固定参数个数从多到少尝试（更具体的优先）
      others = rest.OrderByDescending(r => r.Item1).ToArray();
    }

    static Func<object[], object> MakeArrayCall(PrimitiveOverload o)
    {
      var m = o.Method;
      int k = o.FixedArity;
      if (o.HasRest)
      {
        switch (k)
        {
          case 0: { var d = m.CreateDelegate<Func<object[], object>>(); return a => d(a); }
          case 1: { var d = m.CreateDelegate<Func<object, object[], object>>(); return a => d(a[0], a[1..]); }
          case 2: { var d = m.CreateDelegate<Func<object, object, object[], object>>(); return a => d(a[0], a[1], a[2..]); }
          case 3: { var d = m.CreateDelegate<Func<object, object, object, object[], object>>(); return a => d(a[0], a[1], a[2], a[3..]); }
        }
      }
      // 少见情形：反射调用
      return a =>
      {
        var args = new object[m.GetParameters().Length];
        Array.Copy(a, args, k);
        if (o.HasRest) args[k] = a[k..];
        try { return m.Invoke(null, args); }
        catch (TargetInvocationException e) { System.Runtime.ExceptionServices.ExceptionDispatchInfo.Capture(e.InnerException).Throw(); throw; }
      };
    }

    public override object Invoke0() => f0 != null ? f0() : InvokeN(Array.Empty<object>());
    public override object Invoke1(object a) => f1 != null ? f1(a) : InvokeN(new[] { a });
    public override object Invoke2(object a, object b) => f2 != null ? f2(a, b) : InvokeN(new[] { a, b });
    public override object Invoke3(object a, object b, object c) => f3 != null ? f3(a, b, c) : InvokeN(new[] { a, b, c });
    public override object Invoke4(object a, object b, object c, object d) => f4 != null ? f4(a, b, c, d) : InvokeN(new[] { a, b, c, d });

    public override object InvokeN(object[] args)
    {
      switch (args.Length)
      {
        case 0 when f0 != null: return f0();
        case 1 when f1 != null: return f1(args[0]);
        case 2 when f2 != null: return f2(args[0], args[1]);
        case 3 when f3 != null: return f3(args[0], args[1], args[2]);
        case 4 when f4 != null: return f4(args[0], args[1], args[2], args[3]);
      }
      foreach (var (k, isRest, call) in others)
        if (isRest ? args.Length >= k : args.Length == k) return call(args);
      return ArityError(args.Length);
    }
  }
}

using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Linq.Expressions;
using System.Reflection;
using System.Runtime.ExceptionServices;
using System.Text;
using BigInteger = Oyster.Math.IntX;

namespace IronScheme.Core
{
  /// <summary>
  /// CLR 互操作的运行时实现（设计 02 §9）。编译期能决议的成员由发射器直接生成调用（iron-019）；
  /// 决议不了的、以及 stage0 解释执行的 clr-* 形式，都走这里：按实际参数类型选重载并缓存。
  /// 转换规则以旧系统 ClrGenerators.cs（ConvertToHelper / ConvertFromHelper）与 Helpers.cs 为准。
  /// </summary>
  public static class Interop
  {
    #region 调用

    /// <summary>(clr-call T member instance arg …)：instance 为 null 表示静态调用。</summary>
    public static object Call(Type type, string member, object instance, object[] args) =>
      Call(type, member, instance, args, null, null);

    /// <param name="paramTypes">显式指定的参数类型（"Name(T1,T2)" 或 (Name T1 T2) 形式）；null 表示按实参推断</param>
    /// <param name="genericArgs">泛型方法的类型参数；null 表示非泛型</param>
    public static object Call(Type type, string member, object instance, object[] args, Type[] paramTypes, Type[] genericArgs)
    {
      bool isStatic = instance == null;
      if (!isStatic && !type.IsInstanceOfType(instance)) instance = ConvertTo(instance, type, "clr-call");

      // 索引器：按 DefaultMember 映射；数组直接下标访问
      if (member == "get_Item" || member == "set_Item")
      {
        if (type.IsArray && !isStatic)
        {
          var arr = (Array)instance;
          int idx = (int)ConvertTo(args[0], typeof(int), "clr-call");
          if (member == "get_Item") return ConvertFrom(arr.GetValue(idx), type.GetElementType());
          arr.SetValue(ConvertTo(args[1], type.GetElementType(), "clr-call"), idx);
          return Unspecified.Instance;
        }
        var dm = type.GetCustomAttribute<DefaultMemberAttribute>();
        if (dm != null) member = member.Substring(0, 4) + dm.MemberName;
      }

      var method = ResolveMethod(type, member, isStatic, args, paramTypes, genericArgs);
      if (method == null)
        return Errors.AssertionViolation("clr-call", $"member could not be resolved on type: {type.Name}", Symbol.Intern(member), Cons.FromArray(args));

      var converted = ConvertArguments(method.GetParameters(), args, "clr-call");
      object result = InvokeUnwrapped(() => method.Invoke(isStatic ? null : instance, converted));
      return ConvertFrom(result, method.ReturnType);
    }

    public static object GetField(Type type, string name, object instance)
    {
      var f = type.GetField(name, BindingFlags.Public | (instance == null ? BindingFlags.Static : BindingFlags.Instance) | BindingFlags.FlattenHierarchy);
      if (f == null) return Errors.AssertionViolation("clr-field-get", $"field not found on type: {type.Name}", Symbol.Intern(name));
      return ConvertFrom(f.GetValue(instance), f.FieldType);
    }

    public static object SetField(Type type, string name, object instance, object value)
    {
      var f = type.GetField(name, BindingFlags.Public | (instance == null ? BindingFlags.Static : BindingFlags.Instance) | BindingFlags.FlattenHierarchy);
      if (f == null) return Errors.AssertionViolation("clr-field-set!", $"field not found on type: {type.Name}", Symbol.Intern(name));
      f.SetValue(instance, ConvertTo(value, f.FieldType, "clr-field-set!"));
      return Unspecified.Instance;
    }

    /// <summary>(clr-new T arg …)：值类型无参数时得到默认值。</summary>
    public static object New(Type type, object[] args)
    {
      if (args.Length == 0 && type.IsValueType) return ConvertFrom(Activator.CreateInstance(type), type);
      var ctor = SelectOverload(type.GetConstructors(), args, null);
      if (ctor == null) return Errors.AssertionViolation("clr-new", $"constructor could not be resolved on type: {type.Name}", Cons.FromArray(args));
      var converted = ConvertArguments(ctor.GetParameters(), args, "clr-new");
      return ConvertFrom(InvokeUnwrapped(() => ((ConstructorInfo)ctor).Invoke(converted)), type);
    }

    public static object NewArray(Type elementType, object size) =>
      Array.CreateInstance(elementType, (int)ConvertTo(size, typeof(int), "clr-new-array"));

    /// <summary>(clr-cast T e)：转换为 T 后再转回 Scheme 表示；null 得到 T 的默认值（与旧系统一致）。</summary>
    public static object Cast(Type type, object value) =>
      value == null && type.IsValueType ? ConvertFrom(Activator.CreateInstance(type), type) : ConvertFrom(ConvertTo(value, type, "clr-cast"), type);

    public static object Is(Type type, object value) => RT.Bool(type.IsInstanceOfType(value));

    static object InvokeUnwrapped(Func<object> f)
    {
      try { return f(); }
      catch (TargetInvocationException e) when (e.InnerException != null)
      {
        ExceptionDispatchInfo.Capture(e.InnerException).Throw();
        throw;
      }
    }

    #endregion

    #region 重载决议

    static readonly ConcurrentDictionary<string, MethodBase> resolved = new ConcurrentDictionary<string, MethodBase>();

    static string CacheKey(Type type, string member, bool isStatic, object[] args, Type[] paramTypes, Type[] genericArgs)
    {
      var sb = new StringBuilder().Append(type.AssemblyQualifiedName).Append('|').Append(member).Append(isStatic ? "|s|" : "|i|");
      foreach (var a in args) sb.Append(a?.GetType().FullName ?? "null").Append(',');
      if (paramTypes != null) { sb.Append("|p:"); foreach (var p in paramTypes) sb.Append(p?.FullName).Append(','); }
      if (genericArgs != null) { sb.Append("|g:"); foreach (var g in genericArgs) sb.Append(g.FullName).Append(','); }
      return sb.ToString();
    }

    static MethodInfo ResolveMethod(Type type, string member, bool isStatic, object[] args, Type[] paramTypes, Type[] genericArgs)
    {
      string key = CacheKey(type, member, isStatic, args, paramTypes, genericArgs);
      if (resolved.TryGetValue(key, out var cached)) return (MethodInfo)cached;

      var flags = BindingFlags.Public | (isStatic ? BindingFlags.Static : BindingFlags.Instance) | BindingFlags.FlattenHierarchy;
      var candidates = new List<MethodBase>();
      foreach (var mi in type.GetMember(member, MemberTypes.Method, flags).Cast<MethodInfo>())
      {
        if (genericArgs != null)
        {
          if (mi.ContainsGenericParameters && mi.GetGenericArguments().Length == genericArgs.Length)
            candidates.Add(mi.MakeGenericMethod(genericArgs));
        }
        else if (!mi.ContainsGenericParameters) candidates.Add(mi);
      }
      // 接口类型上找不到时，再查 object 的方法（ToString 等）
      if (candidates.Count == 0 && type.IsInterface && !isStatic)
        candidates.AddRange(typeof(object).GetMember(member, MemberTypes.Method, flags).Cast<MethodInfo>());

      var m = (MethodInfo)SelectOverload(candidates, args, paramTypes);
      if (m != null) resolved[key] = m;
      return m;
    }

    /// <summary>按参数逐个打分：类型完全相同 3、可赋值 2、可转换 1、不可转换则淘汰；取总分最高者，平分时取先出现者。</summary>
    static MethodBase SelectOverload(IEnumerable<MethodBase> candidates, object[] args, Type[] paramTypes)
    {
      MethodBase best = null;
      int bestScore = -1;
      foreach (var m in candidates)
      {
        var ps = m.GetParameters();
        bool hasParams = ps.Length > 0 && ps[^1].IsDefined(typeof(ParamArrayAttribute), false);
        if (paramTypes != null)
        {
          if (ps.Length != paramTypes.Length) continue;
          bool match = true;
          for (int i = 0; i < ps.Length && match; i++) match = paramTypes[i] == null || ps[i].ParameterType == paramTypes[i];
          if (match) return m;
          continue;
        }
        int score = Score(ps, args, hasParams);
        if (score > bestScore) { best = m; bestScore = score; }
      }
      return best;
    }

    static int Score(ParameterInfo[] ps, object[] args, bool hasParams)
    {
      if (ps.Any(p => p.ParameterType.IsByRef)) return -1;   // 不支持 ref/out
      int fixedCount = hasParams ? ps.Length - 1 : ps.Length;
      if (hasParams ? args.Length < fixedCount : args.Length != ps.Length) return -1;
      int total = 0;
      for (int i = 0; i < args.Length; i++)
      {
        Type pt = i < fixedCount ? ps[i].ParameterType : null;
        if (pt == null)
        {
          // params 部分：若恰好传入一个匹配的数组，按数组整体传递
          if (args.Length == ps.Length && ps[^1].ParameterType.IsInstanceOfType(args[i])) { total += 2; continue; }
          pt = ps[^1].ParameterType.GetElementType();
        }
        int s = ScoreOne(args[i], pt);
        if (s < 0) return -1;
        total += s;
      }
      return total;
    }

    static int ScoreOne(object a, Type pt)
    {
      if (a == null) return !pt.IsValueType || Nullable.GetUnderlyingType(pt) != null ? 2 : -1;
      if (a.GetType() == pt) return 3;
      if (pt.IsInstanceOfType(a)) return 2;
      return CanConvert(a, pt) ? 1 : -1;
    }

    static object[] ConvertArguments(ParameterInfo[] ps, object[] args, string who)
    {
      bool hasParams = ps.Length > 0 && ps[^1].IsDefined(typeof(ParamArrayAttribute), false);
      var result = new object[ps.Length];
      int fixedCount = hasParams ? ps.Length - 1 : ps.Length;
      for (int i = 0; i < fixedCount; i++) result[i] = ConvertTo(args[i], ps[i].ParameterType, who);
      if (hasParams)
      {
        var arrType = ps[^1].ParameterType;
        if (args.Length == ps.Length && arrType.IsInstanceOfType(args[^1])) result[^1] = args[^1];
        else
        {
          var et = arrType.GetElementType();
          var arr = Array.CreateInstance(et, args.Length - fixedCount);
          for (int i = fixedCount; i < args.Length; i++) arr.SetValue(ConvertTo(args[i], et, who), i - fixedCount);
          result[^1] = arr;
        }
      }
      return result;
    }

    #endregion

    #region 转换

    static bool IsNumeric(Type t) =>
      Type.GetTypeCode(t) is TypeCode.Byte or TypeCode.SByte or TypeCode.Int16 or TypeCode.UInt16 or TypeCode.Int32 or TypeCode.UInt32
        or TypeCode.Int64 or TypeCode.UInt64 or TypeCode.Single or TypeCode.Double or TypeCode.Decimal;

    static bool IsSchemeNumber(object a) => a is int or double or BigInteger or Fraction || (a != null && IsNumeric(a.GetType()));

    static bool CanConvert(object a, Type t)
    {
      if (typeof(Delegate).IsAssignableFrom(t)) return a is Procedure;
      if (t.IsEnum) return a is Symbol || a is Cons || IsSchemeNumber(a);
      if (t == typeof(string)) return a is StringBuilder;
      if (t == typeof(bool)) return true;                         // 旧系统：非布尔按真值转换
      if (t == typeof(char)) return a is SchemeChar sc && sc.Value < 0x10000;
      if (IsNumeric(t)) return IsSchemeNumber(a);
      if (t.IsArray) return a is object[] || a is Cons || (a is Array arr && arr.GetType().GetElementType() != null);
      return false;
    }

    /// <summary>Scheme 值 → CLR 类型 t。无法转换时报 assertion-violation。</summary>
    public static object ConvertTo(object a, Type t, string who = "clr")
    {
      if (t == typeof(object) || t == typeof(void)) return a;
      if (a == null)
      {
        if (!t.IsValueType || Nullable.GetUnderlyingType(t) != null) return null;
        return Errors.AssertionViolation(who, "value type cannot be null", t.Name);
      }
      if (t.IsInstanceOfType(a)) return a;
      var u = Nullable.GetUnderlyingType(t);
      if (u != null) return ConvertTo(a, u, who);

      try
      {
        if (typeof(Delegate).IsAssignableFrom(t) && a is Procedure p) return ToDelegate(t, p);
        if (t.IsEnum) return a is Symbol || a is Cons ? SymbolToEnum(t, a) : Enum.ToObject(t, ToInteger(a));
        if (t == typeof(string) && a is StringBuilder sb) return sb.ToString();
        if (t == typeof(bool)) return RT.IsTrue(a);
        if (t == typeof(char) && a is SchemeChar sc && sc.Value < 0x10000) return (char)sc.Value;
        if (IsNumeric(t) && IsSchemeNumber(a)) return ConvertNumber(a, t);
        if (t.IsArray)
        {
          var et = t.GetElementType();
          IList<object> items = a switch
          {
            object[] v => v,
            Cons c => c.ToList(),
            Array arr => arr.Cast<object>().ToList(),
            _ => null,
          };
          if (items != null)
          {
            var result = Array.CreateInstance(et, items.Count);
            for (int i = 0; i < items.Count; i++) result.SetValue(ConvertTo(items[i], et, who), i);
            return result;
          }
        }
      }
      catch (Exception e) when (e is InvalidCastException or OverflowException or FormatException or ArgumentException)
      {
        return Errors.AssertionViolation(who, $"cannot convert to {t.Name}: {e.Message}", a);
      }
      return Errors.AssertionViolation(who, "expected type: " + t.Name, a);
    }

    public static T Convert<T>(object a) => (T)ConvertTo(a, typeof(T));

    static long ToInteger(object a) => a switch
    {
      int i => i,
      BigInteger b => (long)b,
      _ => System.Convert.ToInt64(a, CultureInfo.InvariantCulture),
    };

    static object ConvertNumber(object a, Type t)
    {
      if (a is BigInteger b)
      {
        switch (Type.GetTypeCode(t))
        {
          case TypeCode.Int64: return (long)b;
          case TypeCode.UInt64: return (ulong)b;
          case TypeCode.Double: return b.ToFloat64();
          case TypeCode.Single: return (float)b.ToFloat64();
          case TypeCode.Decimal: return decimal.Parse(b.ToString(), CultureInfo.InvariantCulture);
          default: return System.Convert.ChangeType((long)b, t, CultureInfo.InvariantCulture);
        }
      }
      if (a is Fraction) return System.Convert.ChangeType(Builtins.ToInexact(a), t, CultureInfo.InvariantCulture);
      return System.Convert.ChangeType(a, t, CultureInfo.InvariantCulture);
    }

    /// <summary>CLR 返回值 → Scheme 值：void → 未指定值，枚举 → 符号，bool → #t/#f 单例（旧系统每次装箱新对象）。</summary>
    public static object ConvertFrom(object v, Type declared)
    {
      if (declared == typeof(void)) return Unspecified.Instance;
      switch (v)
      {
        case bool b: return RT.Bool(b);
        case int i: return RT.Box(i);
        case Enum e: return EnumToSymbol(e);
        default: return v;
      }
    }

    public static object EnumToSymbol(object value) => Symbol.Intern(value.ToString());

    /// <summary>符号 → 枚举值；符号列表 → 按位或（[Flags] 枚举）。</summary>
    public static object SymbolToEnum(Type type, object symbol)
    {
      switch (symbol)
      {
        case Symbol s:
          try { return Enum.Parse(type, s.Name, true); }
          catch (ArgumentException ex) { return Errors.AssertionViolation("symbol-to-enum", ex.Message, symbol, type); }
        case Cons c:
          long v = 0;
          foreach (var n in c) v |= System.Convert.ToInt64(SymbolToEnum(type, n), CultureInfo.InvariantCulture);
          return Enum.ToObject(type, v);
        default:
          return Errors.AssertionViolation("symbol-to-enum", "not a valid type", symbol, type);
      }
    }

    #endregion

    #region 过程 → 委托

    static readonly ConcurrentDictionary<Type, Func<Procedure, Delegate>> delegateFactories = new ConcurrentDictionary<Type, Func<Procedure, Delegate>>();

    static readonly MethodInfo invokeN = typeof(Procedure).GetMethod(nameof(Procedure.InvokeN));
    static readonly MethodInfo convertFromM = typeof(Interop).GetMethod(nameof(ConvertFrom));
    static readonly MethodInfo convertToM = typeof(Interop).GetMethod(nameof(ConvertTo));

    /// <summary>用 System.Linq.Expressions 生成"参数转为 Scheme 值 → InvokeN → 结果转为返回类型"的适配委托，按委托类型缓存工厂。</summary>
    public static Delegate ToDelegate(Type delegateType, Procedure proc) =>
      delegateFactories.GetOrAdd(delegateType, BuildFactory)(proc);

    static Func<Procedure, Delegate> BuildFactory(Type dt)
    {
      var invoke = dt.GetMethod("Invoke");
      var ps = invoke.GetParameters();
      if (ps.Any(p => p.ParameterType.IsByRef)) throw new NotSupportedException("delegates with ref/out parameters are not supported: " + dt);

      var procParam = Expression.Parameter(typeof(Procedure), "proc");
      var lambdaParams = ps.Select(p => Expression.Parameter(p.ParameterType, p.Name)).ToArray();
      var argArray = Expression.NewArrayInit(typeof(object),
        lambdaParams.Select(p => (Expression)Expression.Call(convertFromM, Expression.Convert(p, typeof(object)), Expression.Constant(p.Type))));
      Expression call = Expression.Call(procParam, invokeN, argArray);
      Expression body = invoke.ReturnType == typeof(void)
        ? Expression.Block(typeof(void), call)
        : Expression.Convert(Expression.Call(convertToM, call, Expression.Constant(invoke.ReturnType), Expression.Constant("delegate")), invoke.ReturnType);
      var inner = Expression.Lambda(dt, body, lambdaParams);
      return Expression.Lambda<Func<Procedure, Delegate>>(inner, procParam).Compile();
    }

    #endregion
  }
}

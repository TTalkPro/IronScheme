using System;
using System.Collections.Concurrent;
using System.Linq;
using System.Linq.Expressions;
using System.Reflection;
using System.Reflection.Emit;
using System.Runtime.InteropServices;

namespace IronScheme.Core;

/// <summary>
/// FFI（iron-032）：(ironscheme ffi) 与 (ironscheme clr) 的 ffi-callout、ffi-callback、pinvoke-call。
/// 旧编译器把它们当特殊形式静态生成调用代码；新系统改为运行时原语，参数是类型名（符号或字符串）：
/// - 每种签名生成一个委托类型（动态程序集），原生调用经 Marshal.GetDelegateForFunctionPointer，
///   字符串等按委托封送规则转换；
/// - Scheme 值与原生值的转换用 Helpers.FFIConvertTo/FFIConvertFrom，适配代码用表达式树生成并按签名缓存。
/// 只依赖 .NET 自身（Reflection.Emit、System.Linq.Expressions、NativeLibrary）。
/// </summary>
public static class Ffi
{
    private sealed class Signature
    {
        public readonly CallingConvention Convention;
        public readonly Type Return;
        public readonly Type[] Params;
        public readonly string Key;

        public Signature(CallingConvention conv, object ret, object[] args, int start, string who)
        {
            Convention = conv;
            Return = FfiType(ret, who);
            Params = new Type[args.Length - start];
            for (int i = 0; i < Params.Length; i++) Params[i] = FfiType(args[start + i], who);
            Key = conv + ":" + Return.FullName + "(" + string.Join(",", Params.Select(p => p.FullName)) + ")";
        }
    }

    private static string Name(object x, string who) => x switch
    {
        Symbol s => s.Name,
        string s => s,
        _ => (string)Errors.AssertionViolation(who, "not a symbol or string", x)
    };

    private static Type FfiType(object spec, string who)
    {
        switch (Name(spec, who))
        {
            case "void": return typeof(void);
            case "intptr": case "void*": return typeof(IntPtr);
            case "int8": return typeof(sbyte);
            case "int16": return typeof(short);
            case "int": case "int32": return typeof(int);
            case "int64": return typeof(long);
            case "uint8": return typeof(byte);
            case "uint16": return typeof(ushort);
            case "uint32": return typeof(uint);
            case "uint64": return typeof(ulong);
            case "uintptr": return typeof(UIntPtr);
            case "float": case "float32": return typeof(float);
            case "double": case "float64": return typeof(double);
            case "string": case "char*": return typeof(string);
            default: return (Type)Errors.AssertionViolation(who, "unknown ffi type", spec);
        }
    }

    // ———————————————— 委托类型 ————————————————

    private static readonly ModuleBuilder s_module =
      AssemblyBuilder.DefineDynamicAssembly(new AssemblyName("ironscheme.ffi"), AssemblyBuilderAccess.Run)
        .DefineDynamicModule("ironscheme.ffi");

    private static readonly ConcurrentDictionary<string, Type> s_delegateTypes = new ConcurrentDictionary<string, Type>();

    private static Type DelegateType(Signature sig) => s_delegateTypes.GetOrAdd(sig.Key, _ =>
    {
        lock (s_module)
        {
            var tb = s_module.DefineType("ffi-delegate-" + s_delegateTypes.Count + "-" + Guid.NewGuid().ToString("N"),
          TypeAttributes.Public | TypeAttributes.Sealed, typeof(MulticastDelegate));
            tb.SetCustomAttribute(new CustomAttributeBuilder(
          typeof(UnmanagedFunctionPointerAttribute).GetConstructor(new[] { typeof(CallingConvention) }),
          new object[] { sig.Convention }));
            tb.DefineConstructor(MethodAttributes.RTSpecialName | MethodAttributes.SpecialName | MethodAttributes.Public | MethodAttributes.HideBySig,
          CallingConventions.Standard, new[] { typeof(object), typeof(IntPtr) }).SetImplementationFlags(MethodImplAttributes.Runtime);
            tb.DefineMethod("Invoke", MethodAttributes.Public | MethodAttributes.Virtual | MethodAttributes.NewSlot | MethodAttributes.HideBySig,
          sig.Return, sig.Params).SetImplementationFlags(MethodImplAttributes.Runtime);
            return tb.CreateType();
        }
    });

    private static readonly MethodInfo s_convertTo = typeof(Helpers).GetMethod(nameof(Helpers.FFIConvertTo));
    private static readonly MethodInfo s_convertFrom = typeof(Helpers).GetMethod(nameof(Helpers.FFIConvertFrom));

    // ———————————————— callout：原生函数指针 → Scheme 过程 ————————————————

    private static readonly ConcurrentDictionary<string, Func<Delegate, object[], object>> s_invokers =
      new ConcurrentDictionary<string, Func<Delegate, object[], object>>();

    /// <summary>(del args) → 转换实参、调用委托、转换返回值。</summary>
    private static Func<Delegate, object[], object> Invoker(Signature sig, Type dt) => s_invokers.GetOrAdd(sig.Key, _ =>
    {
        var d = Expression.Parameter(typeof(Delegate), "d");
        var a = Expression.Parameter(typeof(object[]), "a");
        var args = sig.Params.Select((p, i) =>
      (Expression)Expression.Call(s_convertTo.MakeGenericMethod(p), Expression.ArrayIndex(a, Expression.Constant(i))));
        Expression call = Expression.Invoke(Expression.Convert(d, dt), args);
        Expression body = sig.Return == typeof(void)
      ? Expression.Block(call, Expression.Constant(Unspecified.Instance, typeof(object)))
      : Expression.Call(s_convertFrom.MakeGenericMethod(sig.Return), call);
        return Expression.Lambda<Func<Delegate, object[], object>>(body, d, a).Compile();
    });

    private sealed class NativeProcedure : VariadicProcedure
    {
        private readonly string _name;
        private readonly Signature _sig;
        private readonly Func<Delegate> _resolve;
        private Delegate _target;
        private Func<Delegate, object[], object> _invoker;

        public NativeProcedure(string name, Signature sig, Func<Delegate> resolve)
        {
            _name = name;
            _sig = sig;
            _resolve = resolve;
        }

        public override string Name => _name;
        public override object Arity => RT.Box(_sig.Params.Length);

        public override object InvokeN(object[] args)
        {
            if (args.Length != _sig.Params.Length) return ArityError(args.Length);
            _target ??= _resolve();                       // pinvoke：首次调用时才加载库、查找入口
            _invoker ??= Invoker(_sig, _target.GetType());
            return _invoker(_target, args);
        }
    }

    private static Delegate DelegateFor(IntPtr ptr, Signature sig, string who)
    {
        if (ptr == IntPtr.Zero) Errors.AssertionViolation(who, "pointer cannot be null", ptr);
        return Marshal.GetDelegateForFunctionPointer(ptr, DelegateType(sig));
    }

    /// <summary>(ffi-callout-internal 'ret 'arg …) → (lambda (ptr) 调用 ptr 指向的 cdecl 函数的过程)。</summary>
    [Primitive("ffi-callout-internal")]
    public static object Callout(object ret, params object[] args)
    {
        var sig = new Signature(CallingConvention.Cdecl, ret, args, 0, "ffi-callout");
        DelegateType(sig);   // 类型错误在此报告
        return new Lambda1("ffi-callout", ptr =>
        {
            var p = Helpers.FFIConvertTo<IntPtr>(ptr);
            var d = DelegateFor(p, sig, "ffi-callout");
            return new NativeProcedure("ffi-callout", sig, () => d);
        });
    }

    /// <summary>(pinvoke-call-internal "lib" "proc" "ret" "arg" …) → 调用动态库导出函数的过程（首次调用时加载）。</summary>
    [Primitive("pinvoke-call-internal")]
    public static object PInvokeCall(object lib, object proc, object ret, params object[] args)
    {
        string libName = Name(lib, "pinvoke-call"), procName = Name(proc, "pinvoke-call");
        var sig = new Signature(CallingConvention.Winapi, ret, args, 0, "pinvoke-call");
        return new NativeProcedure(procName, sig, () =>
        {
            if (!NativeLibrary.TryLoad(libName, typeof(Ffi).Assembly, null, out var h))
                Errors.AssertionViolation("pinvoke-call", "cannot load library", libName);
            if (!NativeLibrary.TryGetExport(h, procName, out var p))
                Errors.AssertionViolation("pinvoke-call", "entry point not found", libName, procName);
            return DelegateFor(p, sig, "pinvoke-call");
        });
    }

    // ———————————————— callback：Scheme 过程 → 原生函数指针 ————————————————

    private static readonly MethodInfo s_procCall = typeof(Procedure).GetMethod(nameof(Procedure.Call), new[] { typeof(object[]) });

    private static readonly ConcurrentDictionary<string, Func<Procedure, Delegate>> s_callbackMakers =
      new ConcurrentDictionary<string, Func<Procedure, Delegate>>();

    /// <summary>proc → 签名对应的委托：原生实参转 Scheme 值，调用 proc，返回值转原生值。</summary>
    private static Func<Procedure, Delegate> CallbackMaker(Signature sig) => s_callbackMakers.GetOrAdd(sig.Key, _ =>
    {
        var dt = DelegateType(sig);
        var proc = Expression.Parameter(typeof(Procedure), "proc");
        var ps = sig.Params.Select((t, i) => Expression.Parameter(t, "a" + i)).ToArray();
        Expression call = Expression.Call(proc, s_procCall,
      Expression.NewArrayInit(typeof(object), ps.Select(p => (Expression)Expression.Call(s_convertFrom.MakeGenericMethod(p.Type), p))));
        Expression body = sig.Return == typeof(void)
      ? Expression.Block(typeof(void), call)
      : Expression.Call(s_convertTo.MakeGenericMethod(sig.Return), call);
        var inner = Expression.Lambda(dt, body, ps);
        return Expression.Lambda<Func<Procedure, Delegate>>(inner, proc).Compile();
    });

    /// <summary>(ffi-callback-internal 'ret 'arg …) → (lambda (proc) 原生函数指针)。委托保持存活（Helpers.FFIFunctionPointer）。</summary>
    [Primitive("ffi-callback-internal")]
    public static object Callback(object ret, params object[] args)
    {
        var sig = new Signature(CallingConvention.Cdecl, ret, args, 0, "ffi-callback");
        var maker = CallbackMaker(sig);
        return new Lambda1("ffi-callback", proc =>
          Helpers.FFIFunctionPointer(maker(Errors.RequiresType<Procedure>(proc, "ffi-callback"))));
    }

    private sealed class Lambda1 : Procedure
    {
        private readonly string _name;
        private readonly Func<object, object> _f;
        public Lambda1(string name, Func<object, object> f) { _name = name; _f = f; }
        public override string Name => _name;
        public override object Arity => RT.Box(1);
        public override object Invoke1(object a1) => _f(a1);
    }
}

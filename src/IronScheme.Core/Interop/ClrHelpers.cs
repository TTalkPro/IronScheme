using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using BigInteger = System.Numerics.BigInteger;

namespace IronScheme.Core;

/// <summary>get-clr-type 原语。</summary>
public partial class Builtins
{
    [Primitive("get-clr-type")]
    public static object GetClrType(object name) => GetClrType(name, Array.Empty<object>());

    /// <summary>(get-clr-type 'Name type-arg …)：按全名查找（不经命名空间列表）；带类型参数时构造泛型。</summary>
    [Primitive("get-clr-type")]
    public static object GetClrType(object name, params object[] typeargs)
    {
        var t = TypeResolver.GetTypeFast(RequiresNotNull<Symbol>(name).Name);
        if (t == null) return FALSE;
        if (typeargs.Length == 0) return t;
        return t.MakeGenericType(Array.ConvertAll(typeargs, x => RequiresNotNull<Type>(x)));
    }
}

/// <summary>从旧 Helpers.cs 移植的互操作 / FFI 辅助方法（Scheme 源码按名字调用 Helpers.GetTypeFast；编译器生成的 FFI 调用代码使用其余方法，iron-025）。</summary>
public static partial class Helpers
{
    public static Type GetTypeFast(string name) => TypeResolver.GetTypeFast(name);

    public static T ConvertToDelegate<T>(object proc) where T : Delegate =>
      proc is T d ? d : (T)Interop.ToDelegate(typeof(T), Errors.RequiresType<Procedure>(proc, "convert-to-delegate"));

    public static object EnumToSymbol<T>(T value) => Interop.EnumToSymbol(value);

    public static T SymbolToEnum<T>(object symbol) => (T)Interop.SymbolToEnum(typeof(T), symbol);

    public static T[] RequiresArray<T>(object obj) => (T[])Interop.ConvertTo(obj, typeof(T[]), "requires-array");

    public static T UnsafeConvert<T>(object o) => o is T t ? t : default;

    /// <summary>FFI 参数：Scheme 值 → 原生类型（数值按 Convert 规则；null 视为 IntPtr.Zero）。</summary>
    public static T FFIConvertTo<T>(object obj)
    {
        if (obj == null && typeof(T) == typeof(IntPtr)) return (T)(object)IntPtr.Zero;
        if (obj is T t) return t;
        switch (Type.GetTypeCode(typeof(T)))
        {
            case TypeCode.Int32:
            case TypeCode.UInt32:
            case TypeCode.Int64:
            case TypeCode.UInt64:
            case TypeCode.Int16:
            case TypeCode.UInt16:
            case TypeCode.Byte:
            case TypeCode.SByte:
            case TypeCode.Single:
            case TypeCode.Double:
                return (T)Interop.ConvertTo(obj, typeof(T), "ffi");
            default:
                if (typeof(T) == typeof(IntPtr)) return (T)(object)new IntPtr(Convert.ToInt64(obj));
                return (T)Errors.AssertionViolation("ffi", "not a known ffi type", obj, typeof(T));
        }
    }

    /// <summary>FFI 返回值：原生类型 → Scheme 值（窄整数转 fixnum，宽整数可能转 bignum，float 转 flonum）。</summary>
    public static object FFIConvertFrom<T>(T value)
    {
        object v = value;
        switch (Type.GetTypeCode(typeof(T)))
        {
            case TypeCode.Int32: case TypeCode.Double: return v;
            case TypeCode.UInt32: return Builtins.ToIntegerIfPossible((uint)v);
            case TypeCode.Int64: return Builtins.ToIntegerIfPossible((long)v);
            case TypeCode.UInt64: return Builtins.ToIntegerIfPossible((ulong)v);
            case TypeCode.Int16: case TypeCode.UInt16: case TypeCode.Byte: case TypeCode.SByte: return Convert.ToInt32(v);
            case TypeCode.Single: return Convert.ToDouble(v);
            case TypeCode.String: return v;
            default:
                if (typeof(T) == typeof(IntPtr) || typeof(T) == typeof(UIntPtr)) return v;
                return Errors.AssertionViolation("ffi", "not a known ffi type", v, typeof(T));
        }
    }

    public static T FFIDelegate<T>(IntPtr ptr) where T : Delegate
    {
        if (ptr == IntPtr.Zero) Errors.AssertionViolation("ffi", "pointer cannot be null", ptr);
        return Marshal.GetDelegateForFunctionPointer<T>(ptr);
    }

    // 防止回调委托被回收：函数指针交给原生代码后，委托必须保持存活
    private static readonly List<Delegate> s_pinnedCallbacks = new List<Delegate>();

    /// <summary>委托 → 原生函数指针。旧版需要把委托重新绑定到 DLR 的 CodeContext；新运行时直接取指针，并保持委托存活。</summary>
    public static IntPtr FFIFunctionPointer(Delegate del)
    {
        lock (s_pinnedCallbacks) s_pinnedCallbacks.Add(del);
        return Marshal.GetFunctionPointerForDelegate(del);
    }
}

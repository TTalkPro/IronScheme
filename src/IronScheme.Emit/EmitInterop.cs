using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Reflection.Emit;
using System.Threading.Tasks;

namespace IronScheme.Emit;

// 互操作指令的决议（designs/04-lcil-and-emitter.md §5）。
// 规则与运行时 IronScheme.Core.Interop 一致：类型名经 TypeResolver（含别名与命名空间列表）解析；
// 成员唯一时静态生成调用，参数经 Interop.Convert<T>、返回值经 Interop.ConvertFrom 转换；
// 不唯一、类型在运行时才知道、索引器、params 数组、值类型实例等情况，生成对 Interop.* 的调用，由运行时决议。
public sealed partial class LcilEmitter
{
    private sealed class CoreApi
    {
        public MethodInfo Resolve, Call, GetField, SetField, New, NewArray, Cast, Is, ConvertGeneric, ConvertFrom, NormalizeString;
        public MethodInfo BoxTaskGeneric, BoxTask;      // Tasks.Box<T>(Task<T>)、Tasks.Box(Task)
        public FieldInfo Unspecified;
        public Func<string, object> Intern;
        public Func<object[], object> MakeList;

        public CoreApi(Assembly core)
        {
            var interop = core.GetType("IronScheme.Core.Interop", true);
            Resolve = core.GetType("IronScheme.Core.TypeResolver", true).GetMethod("Resolve", new[] { typeof(object), typeof(IEnumerable<string>) });
            Call = interop.GetMethod("Call", new[] { typeof(Type), typeof(string), typeof(object), typeof(object[]), typeof(Type[]), typeof(Type[]) });
            GetField = interop.GetMethod("GetField", new[] { typeof(Type), typeof(string), typeof(object) });
            SetField = interop.GetMethod("SetField", new[] { typeof(Type), typeof(string), typeof(object), typeof(object) });
            New = interop.GetMethod("New", new[] { typeof(Type), typeof(object[]) });
            NewArray = interop.GetMethod("NewArray", new[] { typeof(Type), typeof(object) });
            Cast = interop.GetMethod("Cast", new[] { typeof(Type), typeof(object) });
            Is = interop.GetMethod("Is", new[] { typeof(Type), typeof(object) });
            ConvertGeneric = interop.GetMethod("Convert", new[] { Type.MakeGenericMethodParameter(0) });
            ConvertFrom = interop.GetMethod("ConvertFrom", new[] { typeof(object), typeof(Type) });
            NormalizeString = core.GetType("IronScheme.Core.SchemeString", true).GetMethod("Normalize", new[] { typeof(string) });
            Unspecified = core.GetType("IronScheme.Core.Unspecified", true).GetField("Instance");
            var tasks = core.GetType("IronScheme.Core.Tasks", true);
            BoxTaskGeneric = tasks.GetMethods().First(m => m.Name == "Box" && m.IsGenericMethodDefinition);
            BoxTask = tasks.GetMethod("Box", new[] { typeof(Task) });
            var intern = core.GetType("IronScheme.Core.Symbol", true).GetMethod("Intern", new[] { typeof(string) });
            Intern = s => intern.Invoke(null, new object[] { s });
            var fromArray = core.GetType("IronScheme.Core.Cons", true).GetMethod("FromArray", new[] { typeof(object[]) });
            MakeList = xs => fromArray.Invoke(null, new object[] { xs });
        }
    }

    private CoreApi _core;
    private CoreApi Core => _core ??= new CoreApi(LoadReference("IronScheme.Core"));

    private static readonly MethodInfo s_getTypeFromHandle = typeof(Type).GetMethod("GetTypeFromHandle");
    private static readonly MethodInfo s_objectGetType = typeof(object).GetMethod("GetType");

    private Type ClrType(string name, BodyContext cx, Instr ins)
    {
        var t = (Type)Core.Resolve.Invoke(null, new object[] { GenericSpec(name), cx.Namespaces });
        return t ?? throw Err(ins.Pos, "type not found: " + name);
    }

    /// <summary>
    /// 泛型类型名 "Name&lt;A,B&lt;C&gt;&gt;" → TypeResolver 的说明 (Name A (B C))（符号组成的 Cons）；其余原样返回字符串。
    /// </summary>
    private object GenericSpec(string name)
    {
        if (name.IndexOf('<') < 0) return name;
        int pos = 0;
        object Parse()
        {
            int start = pos;
            while (pos < name.Length && name[pos] != '<' && name[pos] != ',' && name[pos] != '>') pos++;
            var head = name.Substring(start, pos - start).Trim();
            if (pos >= name.Length || name[pos] != '<') return head;
            pos++;
            var items = new List<object> { Core.Intern(head) };
            while (true)
            {
                var a = Parse();
                items.Add(a is string s ? Core.Intern(s) : a);
                if (pos >= name.Length) throw new LcilException("bad generic type name: " + name);
                char c = name[pos++];
                if (c == '>') break;
                if (c != ',') throw new LcilException("bad generic type name: " + name);
            }
            return Core.MakeList(items.ToArray());
        }
        return Parse();
    }

    private LocalBuilder Temp(BodyContext cx, int i)
    {
        while (cx.Temps.Count <= i) cx.Temps.Add(cx.IL.DeclareLocal(typeof(object)));
        return cx.Temps[i];
    }

    private static void EmitType(ILGenerator il, Type t)
    {
        il.Emit(OpCodes.Ldtoken, t);
        il.Emit(OpCodes.Call, s_getTypeFromHandle);
    }

    /// <summary>栈顶 object → t（t 为 object 时不转换）。</summary>
    private void ConvertTo(ILGenerator il, Type t)
    {
        if (t != typeof(object)) il.Emit(OpCodes.Call, Core.ConvertGeneric.MakeGenericMethod(t));
    }

    /// <summary>栈顶类型为 t 的值 → Scheme 表示（void → unspecified）。</summary>
    private void ConvertFrom(ILGenerator il, Type t)
    {
        if (t == typeof(void)) { il.Emit(OpCodes.Ldsfld, Core.Unspecified); return; }
        if (t == typeof(object) || t == typeof(ValueType))
        {
            // 声明为 object 的值按运行时类型转换（装箱的 Int64 等 → Scheme 数；Interop.ConvertFrom）
            EmitType(il, typeof(object));
            il.Emit(OpCodes.Call, Core.ConvertFrom);
            return;
        }
        // 字符串：含代理码元的转为宽串（iron-055，designs/12-strings.md §3）
        if (t == typeof(string)) { il.Emit(OpCodes.Call, Core.NormalizeString); return; }
        // Task<T> / Task → Task<object>（designs/10-async.md §2 D8）；Task<object> 原样
        if (typeof(Task).IsAssignableFrom(t))
        {
            if (t == typeof(Task<object>)) return;
            var resultType = TaskResultType(t);
            il.Emit(OpCodes.Call, resultType != null ? Core.BoxTaskGeneric.MakeGenericMethod(resultType) : Core.BoxTask);
            return;
        }
        if (!t.IsValueType) return;   // 其他引用类型 ConvertFrom 不改变值
        il.Emit(OpCodes.Box, t);
        EmitType(il, t);
        il.Emit(OpCodes.Call, Core.ConvertFrom);
    }

    /// <summary>t 是 Task&lt;X&gt;（或其子类）时返回 X，否则 null。</summary>
    private static Type TaskResultType(Type t)
    {
        for (; t != null && t != typeof(object); t = t.BaseType)
            if (t.IsGenericType && t.GetGenericTypeDefinition() == typeof(Task<>)) return t.GetGenericArguments()[0];
        return null;
    }

    /// <summary>把临时变量 from..from+n-1 装进 object[]。</summary>
    private void EmitArgArray(BodyContext cx, int from, int n)
    {
        var il = cx.IL;
        EmitInt(il, n);
        il.Emit(OpCodes.Newarr, typeof(object));
        for (int i = 0; i < n; i++)
        {
            il.Emit(OpCodes.Dup);
            EmitInt(il, i);
            il.Emit(OpCodes.Ldloc, Temp(cx, from + i));
            il.Emit(OpCodes.Stelem_Ref);
        }
    }

    private void EmitTypeArray(ILGenerator il, Type[] ts)
    {
        EmitInt(il, ts.Length);
        il.Emit(OpCodes.Newarr, typeof(Type));
        for (int i = 0; i < ts.Length; i++)
        {
            il.Emit(OpCodes.Dup);
            EmitInt(il, i);
            EmitType(il, ts[i]);
            il.Emit(OpCodes.Stelem_Ref);
        }
    }

    private static bool NoByRef(ParameterInfo[] ps) => !ps.Any(p => p.ParameterType.IsByRef || p.ParameterType.IsPointer);

    private static bool Simple(ParameterInfo[] ps) =>
      !ps.Any(p => p.ParameterType.IsByRef || p.ParameterType.IsPointer) &&
      !(ps.Length > 0 && ps[^1].IsDefined(typeof(ParamArrayAttribute), false));

    /// <summary>可静态决议的方法：显式参数类型时按类型精确匹配；否则该名字只有一个重载且参数个数相符。</summary>
    private static MethodInfo StaticMethod(Type t, string member, bool isStatic, int argc, Type[] ptypes)
    {
        if (member == "get_Item" || member == "set_Item")
        {
            // 数组下标由运行时处理；其余按 DefaultMember 映射到实际的索引器名（iron-033：hashtable-ref 等热点）
            if (t.IsArray) return null;
            var dm = t.GetCustomAttribute<DefaultMemberAttribute>();
            if (dm == null) return null;
            member = member.Substring(0, 4) + dm.MemberName;
        }
        if (!isStatic && t.IsValueType) return null;
        var flags = BindingFlags.Public | (isStatic ? BindingFlags.Static : BindingFlags.Instance) | BindingFlags.FlattenHierarchy;
        var all = t.GetMember(member, MemberTypes.Method, flags).Cast<MethodInfo>().Where(m => !m.ContainsGenericParameters).ToList();
        // 显式参数类型时 params 数组参数按数组整体传入（如 (Concat String[])），与运行时一致；原先也交给运行时，string-append 因此是热点（iron-033）
        if (ptypes != null)
            return all.FirstOrDefault(m => m.GetParameters().Select(p => p.ParameterType).SequenceEqual(ptypes) && NoByRef(m.GetParameters()));
        // 按参数个数过滤（04 §5 规则 2）：能接受 argc 个实参的重载（含 params 数组重载）恰好一个、且是普通签名时静态调用。
        // 原先要求同名只有一个重载，String.Substring(int)/(int,int) 这类按个数即可区分的调用也落到运行时（iron-033）
        var fit = all.Where(m =>
        {
            var p = m.GetParameters();
            return p.Length == argc || (p.Length > 0 && p.Length - 1 <= argc && p[^1].IsDefined(typeof(ParamArrayAttribute), false));
        }).ToList();
        if (fit.Count != 1) return null;
        var ps = fit[0].GetParameters();
        return ps.Length == argc && Simple(ps) ? fit[0] : null;
    }

    private void Clr(BodyContext cx, Instr ins)
    {
        var il = cx.IL;
        switch (ins.ClrOp)
        {
            case "call": ClrCall(cx, ins); return;
            case "field-get": ClrFieldGet(cx, ins); return;
            case "field-set": ClrFieldSet(cx, ins); return;
            case "new": ClrNew(cx, ins); return;
            case "new-array":
                {
                    var t = ClrType(ins.ClrType, cx, ins);
                    var size = Temp(cx, 0);
                    il.Emit(OpCodes.Stloc, size);
                    EmitType(il, t);
                    il.Emit(OpCodes.Ldloc, size);
                    il.Emit(OpCodes.Call, Core.NewArray);
                    return;
                }
            case "cast":
            case "is":
                {
                    var t = ClrType(ins.ClrType, cx, ins);
                    var v = Temp(cx, 0);
                    il.Emit(OpCodes.Stloc, v);
                    EmitType(il, t);
                    il.Emit(OpCodes.Ldloc, v);
                    il.Emit(OpCodes.Call, ins.ClrOp == "cast" ? Core.Cast : Core.Is);
                    return;
                }
            case "type": EmitType(il, ClrType(ins.ClrType, cx, ins)); return;
        }
        throw Err(ins.Pos, "unknown interop instruction clr-" + ins.ClrOp);
    }

    // 栈：[实例] 参数 1..n → 临时变量：0 = 实例，1..n = 参数
    private void SpillArgs(BodyContext cx, int n, bool hasInstance)
    {
        for (int i = n; i >= 1; i--) cx.IL.Emit(OpCodes.Stloc, Temp(cx, i));
        if (hasInstance) cx.IL.Emit(OpCodes.Stloc, Temp(cx, 0));
    }

    private void ClrCall(BodyContext cx, Instr ins)
    {
        var il = cx.IL;
        int n = ins.ClrArgc;
        SpillArgs(cx, n, !ins.ClrStatic);
        Type t = ins.ClrType == null ? null : ClrType(ins.ClrType, cx, ins);
        Type[] ptypes = ins.ClrParams?.Select(p => ClrType(p, cx, ins)).ToArray();
        if (ptypes != null && ptypes.Length != n) throw Err(ins.Pos, "explicit parameter types do not match argument count");
        Type[] gtypes = ins.ClrGenerics?.Select(g => ClrType(g, cx, ins)).ToArray();
        var target = t == null || gtypes != null ? null : StaticMethod(t, ins.ClrMember, ins.ClrStatic, n, ptypes);   // 泛型方法交给运行时
        if (target == null && t != null && gtypes == null && ptypes == null && ins.ClrHints != null && ins.ClrHints.Count == n)
            target = StaticMethod(t, ins.ClrMember, ins.ClrStatic, n, ins.ClrHints.Select(h => ClrType(h, cx, ins)).ToArray());
        if (target != null)
        {
            if (!ins.ClrStatic) { il.Emit(OpCodes.Ldloc, Temp(cx, 0)); ConvertTo(il, t); }
            var ps = target.GetParameters();
            for (int i = 0; i < n; i++) { il.Emit(OpCodes.Ldloc, Temp(cx, i + 1)); ConvertTo(il, ps[i].ParameterType); }
            il.Emit(ins.ClrStatic || target.DeclaringType.IsValueType ? OpCodes.Call : OpCodes.Callvirt, target);
            ConvertFrom(il, target.ReturnType);
            return;
        }
        // 运行时决议：Interop.Call(type, member, instance, args, paramTypes, genericArgs)
        if (t != null) EmitType(il, t);
        else { il.Emit(OpCodes.Ldloc, Temp(cx, 0)); il.Emit(OpCodes.Callvirt, s_objectGetType); }
        il.Emit(OpCodes.Ldstr, ins.ClrMember);
        if (ins.ClrStatic) il.Emit(OpCodes.Ldnull); else il.Emit(OpCodes.Ldloc, Temp(cx, 0));
        EmitArgArray(cx, 1, n);
        if (ptypes != null) EmitTypeArray(il, ptypes); else il.Emit(OpCodes.Ldnull);
        if (gtypes != null) EmitTypeArray(il, gtypes); else il.Emit(OpCodes.Ldnull);
        il.Emit(OpCodes.Call, Core.Call);
    }

    private FieldInfo StaticField(Type t, string name, bool isStatic) =>
      t == null || (!isStatic && t.IsValueType) ? null
        : t.GetField(name, BindingFlags.Public | (isStatic ? BindingFlags.Static : BindingFlags.Instance) | BindingFlags.FlattenHierarchy);

    private void ClrFieldGet(BodyContext cx, Instr ins)
    {
        var il = cx.IL;
        SpillArgs(cx, 0, !ins.ClrStatic);
        Type t = ins.ClrType == null ? null : ClrType(ins.ClrType, cx, ins);
        var f = StaticField(t, ins.ClrMember, ins.ClrStatic);
        if (f != null && f.IsLiteral && EmitLiteral(il, f.GetRawConstantValue(), f.FieldType)) return;
        if (f != null && !f.IsLiteral)
        {
            if (ins.ClrStatic) il.Emit(OpCodes.Ldsfld, f);
            else { il.Emit(OpCodes.Ldloc, Temp(cx, 0)); ConvertTo(il, t); il.Emit(OpCodes.Ldfld, f); }
            ConvertFrom(il, f.FieldType);
            return;
        }
        if (t != null) EmitType(il, t);
        else { il.Emit(OpCodes.Ldloc, Temp(cx, 0)); il.Emit(OpCodes.Callvirt, s_objectGetType); }
        il.Emit(OpCodes.Ldstr, ins.ClrMember);
        if (ins.ClrStatic) il.Emit(OpCodes.Ldnull); else il.Emit(OpCodes.Ldloc, Temp(cx, 0));
        il.Emit(OpCodes.Call, Core.GetField);
    }

    /// <summary>常量字段（const）直接内联值；不认识的类型返回 false，交给运行时。</summary>
    private bool EmitLiteral(ILGenerator il, object v, Type ft)
    {
        switch (v)
        {
            case string s: il.Emit(OpCodes.Ldstr, s); return true;
            case int i when !ft.IsEnum: EmitInt(il, i); break;
            case long l: il.Emit(OpCodes.Ldc_I8, l); break;
            case double d: il.Emit(OpCodes.Ldc_R8, d); break;
            case float fl: il.Emit(OpCodes.Ldc_R4, fl); break;
            case bool b: EmitInt(il, b ? 1 : 0); break;
            case char c: EmitInt(il, c); break;
            case short s16: EmitInt(il, s16); break;
            case ushort u16: EmitInt(il, u16); break;
            case byte u8: EmitInt(il, u8); break;
            case sbyte s8: EmitInt(il, s8); break;
            default: return false;
        }
        ConvertFrom(il, ft);
        return true;
    }

    private void ClrFieldSet(BodyContext cx, Instr ins)
    {
        var il = cx.IL;
        SpillArgs(cx, 1, !ins.ClrStatic);
        Type t = ins.ClrType == null ? null : ClrType(ins.ClrType, cx, ins);
        var f = StaticField(t, ins.ClrMember, ins.ClrStatic);
        if (f != null && !f.IsLiteral && !f.IsInitOnly)
        {
            if (!ins.ClrStatic) { il.Emit(OpCodes.Ldloc, Temp(cx, 0)); ConvertTo(il, t); }
            il.Emit(OpCodes.Ldloc, Temp(cx, 1));
            ConvertTo(il, f.FieldType);
            il.Emit(ins.ClrStatic ? OpCodes.Stsfld : OpCodes.Stfld, f);
            il.Emit(OpCodes.Ldsfld, Core.Unspecified);
            return;
        }
        if (t != null) EmitType(il, t);
        else { il.Emit(OpCodes.Ldloc, Temp(cx, 0)); il.Emit(OpCodes.Callvirt, s_objectGetType); }
        il.Emit(OpCodes.Ldstr, ins.ClrMember);
        if (ins.ClrStatic) il.Emit(OpCodes.Ldnull); else il.Emit(OpCodes.Ldloc, Temp(cx, 0));
        il.Emit(OpCodes.Ldloc, Temp(cx, 1));
        il.Emit(OpCodes.Call, Core.SetField);
    }

    private void ClrNew(BodyContext cx, Instr ins)
    {
        var il = cx.IL;
        int n = ins.ClrArgc;
        SpillArgs(cx, n, false);
        var t = ClrType(ins.ClrType, cx, ins);
        var ctors = t.GetConstructors();
        ConstructorInfo ctor = null;
        if (!t.IsValueType && ctors.Length == 1 && ctors[0].GetParameters().Length == n && Simple(ctors[0].GetParameters()))
            ctor = ctors[0];
        else if (!t.IsValueType && ins.ClrHints != null && ins.ClrHints.Count == n)
        {
            var hs = ins.ClrHints.Select(h => ClrType(h, cx, ins)).ToArray();
            // 提示类型与参数类型完全相同：params 数组参数收到的就是数组，整体传入（与运行时一致）
            ctor = ctors.FirstOrDefault(c => c.GetParameters().Select(p => p.ParameterType).SequenceEqual(hs) && NoByRef(c.GetParameters()));
        }
        if (ctor != null)
        {
            var ps = ctor.GetParameters();
            for (int i = 0; i < n; i++) { il.Emit(OpCodes.Ldloc, Temp(cx, i + 1)); ConvertTo(il, ps[i].ParameterType); }
            il.Emit(OpCodes.Newobj, ctor);
            return;
        }
        EmitType(il, t);
        EmitArgArray(cx, 1, n);
        il.Emit(OpCodes.Call, Core.New);
    }
}

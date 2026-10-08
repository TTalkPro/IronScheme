using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using IronScheme.Core;

namespace IronScheme.Stage0
{
  // clr-*-internal 形式（designs/03-compiler.md §7）。类型说明在分析时连同当时的命名空间列表一起保存，
  // 第一次执行时经 TypeResolver 解析并缓存；成员按实参经 Interop 决议（与编译后代码的运行时后备相同）。

  /// <summary>类型说明 + 分析时的命名空间列表；#f 表示按实例的运行时类型推断。</summary>
  sealed class TypeRef
  {
    readonly object spec;
    readonly string[] namespaces;
    Type type;

    public TypeRef(object spec, string[] namespaces) { this.spec = spec; this.namespaces = namespaces; }

    public bool Inferred => spec is bool b && !b;

    public Type Get(object instance = null)
    {
      if (Inferred) return instance?.GetType() ?? typeof(object);
      if (type != null) return type;
      type = TypeResolver.Resolve(spec, namespaces);
      if (type == null) Errors.SyntaxError("clr", "type not found", spec, RT.False);
      return type;
    }

    public static Type[] List(object specs, string[] namespaces) =>
      specs is Cons c ? c.Select(s => new TypeRef(s, namespaces).Get()).ToArray() : Type.EmptyTypes;
  }

  static class NodeHelpers
  {
    public static object[] EvalAll(Node[] nodes, Frame f)
    {
      var a = new object[nodes.Length];
      for (int i = 0; i < a.Length; i++) a[i] = nodes[i].Eval(f);
      return a;
    }
  }

  /// <summary>(clr-call-internal 'T 'member instance arg …)；instance 为 '() 表示静态调用。</summary>
  sealed class ClrCall : Node
  {
    readonly TypeRef type;
    readonly string member;
    readonly object paramSpecs, genericSpecs;   // 成员说明为 (Name [#(泛型参数 …)] 参数类型 …) 时
    readonly bool explicitParams;
    readonly string[] namespaces;
    readonly Node instance;
    readonly Node[] args;
    Type[] paramTypes, genericArgs;

    public ClrCall(TypeRef type, object memberSpec, Node instance, Node[] args, string[] namespaces)
    {
      this.type = type; this.instance = instance; this.args = args; this.namespaces = namespaces;
      switch (memberSpec)
      {
        case Symbol s: member = s.Name; break;
        case string s: member = s.IndexOf('(') is int i && i >= 0 ? s.Substring(0, i) : s; break;   // 与旧系统一样只取名字
        case Cons c:
          member = ((Symbol)c.car).Name;
          object rest = c.cdr;
          if (rest is Cons r && r.car is object[] g) { genericSpecs = Cons.FromArray(g); rest = r.cdr; }
          paramSpecs = rest;
          explicitParams = true;
          break;
        default: Errors.SyntaxError("clr-call", "invalid member", memberSpec, RT.False); break;
      }
    }

    public override object Eval(Frame f)
    {
      object inst = instance.Eval(f);
      var a = NodeHelpers.EvalAll(args, f);
      if (explicitParams && paramTypes == null)
      {
        paramTypes = TypeRef.List(paramSpecs, namespaces);
        genericArgs = genericSpecs == null ? null : TypeRef.List(genericSpecs, namespaces);
      }
      return Interop.Call(type.Get(inst), member, inst, a, paramTypes, genericArgs);
    }
  }

  sealed class ClrFieldGet : Node
  {
    readonly TypeRef type; readonly string name; readonly Node instance;
    public ClrFieldGet(TypeRef type, string name, Node instance) { this.type = type; this.name = name; this.instance = instance; }
    public override object Eval(Frame f)
    {
      object inst = instance.Eval(f);
      return Interop.GetField(type.Get(inst), name, inst);
    }
  }

  sealed class ClrFieldSet : Node
  {
    readonly TypeRef type; readonly string name; readonly Node instance, value;
    public ClrFieldSet(TypeRef type, string name, Node instance, Node value) { this.type = type; this.name = name; this.instance = instance; this.value = value; }
    public override object Eval(Frame f)
    {
      object inst = instance.Eval(f);
      return Interop.SetField(type.Get(inst), name, inst, value.Eval(f));
    }
  }

  sealed class ClrNew : Node
  {
    readonly TypeRef type; readonly Node[] args;
    public ClrNew(TypeRef type, Node[] args) { this.type = type; this.args = args; }
    public override object Eval(Frame f) => Interop.New(type.Get(), NodeHelpers.EvalAll(args, f));
  }

  sealed class ClrNewArray : Node
  {
    readonly TypeRef type; readonly Node size;
    public ClrNewArray(TypeRef type, Node size) { this.type = type; this.size = size; }
    public override object Eval(Frame f) => Interop.NewArray(type.Get(), size.Eval(f));
  }

  sealed class ClrCast : Node
  {
    readonly TypeRef type; readonly Node value;
    public ClrCast(TypeRef type, Node value) { this.type = type; this.value = value; }
    public override object Eval(Frame f) => Interop.Cast(type.Get(), value.Eval(f));
  }

  sealed class ClrIs : Node
  {
    readonly TypeRef type; readonly Node value;
    public ClrIs(TypeRef type, Node value) { this.type = type; this.value = value; }
    public override object Eval(Frame f) => Interop.Is(type.Get(), value.Eval(f));
  }

  sealed class ClrTypeOf : Node
  {
    readonly TypeRef type;
    public ClrTypeOf(TypeRef type) { this.type = type; }
    public override object Eval(Frame f) => type.Get();
  }

  static class ClrReferences
  {
    /// <summary>clr-reference：按程序集名或路径加载（分析时执行，与旧系统一样是编译期副作用）。</summary>
    public static void Load(object name)
    {
      string s = name is Symbol sym ? sym.Name : name as string;
      if (s == null) { Errors.SyntaxError("clr-reference", "reference is not a symbol or a string", name, RT.False); return; }
      Assembly asm = null;
      try { asm = File.Exists(s) ? Assembly.LoadFrom(Path.GetFullPath(s)) : Assembly.Load(s); }
      catch (FileNotFoundException) { }
      catch (FileLoadException) { }
      if (asm == null) Errors.SyntaxError("clr-reference", "assembly not found", name, RT.False);
    }
  }
}

using System.Collections.Generic;
using System.Linq;
using IronScheme.Core;

namespace IronScheme.Stage0
{
  /// <summary>
  /// 把 Lcore 核心形式（designs/03-compiler.md §2）分析成 Node 树。
  /// 词法变量解析为（层数, 下标）；不在任何词法作用域中的符号是全局变量（符号值槽，原语也在其中）。
  /// 核心关键字与 special 原语只在未被词法绑定时识别（psyntax 把所有词法变量改名为 gensym，实际不会冲突）。
  /// </summary>
  public sealed class Analyzer
  {
    sealed class Scope
    {
      public readonly List<Symbol> Vars;
      public readonly Scope Parent;
      public readonly bool Letrec;   // letrec 绑定：读取时检查是否已初始化（R6RS letrec 限制）
      public Scope(List<Symbol> vars, Scope parent, bool letrec = false) { Vars = vars; Parent = parent; Letrec = letrec; }
    }

    static Symbol S(string name) => Symbol.Intern(name);

    static readonly Symbol Quote = S("quote"), IfS = S("if"), Begin = S("begin"), SetS = S("set!"),
      CaseLambda = S("case-lambda"), AnnCaseLambda = S("annotated-case-lambda"),
      TypedCaseLambda = S("typed-case-lambda"), AnnTypedCaseLambda = S("annotated-typed-case-lambda"),
      LambdaS = S("lambda"), LetrecS = S("letrec"), LetrecStar = S("letrec*"), LibraryLetrecStar = S("library-letrec*"),
      AnnotatedCall = S("annotated-call"),
      AndP = S("$and?"), OrP = S("$or?"), ThrowP = S("$throw"), BreakP = S("$break"), TryFinallyP = S("$try/finally"),
      ClrCallI = S("clr-call-internal"), ClrFieldGetI = S("clr-field-get-internal"), ClrFieldSetI = S("clr-field-set!-internal"),
      ClrNewI = S("clr-new-internal"), ClrNewArrayI = S("clr-new-array-internal"), ClrCastI = S("clr-cast-internal"),
      ClrIsI = S("clr-is-internal"), ClrTypeOfI = S("clr-type-of-internal"), ClrUsingI = S("clr-using-internal"),
      ClrReferenceI = S("clr-reference-internal"), ClrNamespacesI = S("clr-namespaces-internal");

    static readonly HashSet<Symbol> UnsupportedForms = new HashSet<Symbol>
    {
      S("define-clr-class-internal"),   // FFI 形式是运行时原语（IronScheme.Core.Ffi，iron-032）
    };

    // clr-using 的效果：按 lambda / letrec 词法范围生效（与旧 ClrGenerator.SaveReferences 一致）
    List<string> namespaces = new List<string> { "System" };

    /// <summary>分析一个顶层形式（不在尾位置）。</summary>
    public Node AnalyzeTop(object form) => Analyze(form, null, false);

    Node Analyze(object x, Scope sc, bool tail)
    {
      switch (x)
      {
        case Symbol s: return Ref(s, sc);
        case Cons c: return AnalyzePair(c, sc, tail);
        default: return new Const(x);   // 自求值（psyntax 实际总是加 quote）
      }
    }

    Node Ref(Symbol s, Scope sc)
    {
      if (Lookup(s, sc, out int d, out int i, out bool letrec))
      {
        if (letrec) return new LetrecRef(d, i, s);
        return d == 0 ? new LocalRef0(i) : d == 1 ? new LocalRef1(i) : (Node)new LocalRef(d, i);
      }
      return new GlobalRef(s);
    }

    static bool Lookup(Symbol s, Scope sc, out int depth, out int index) => Lookup(s, sc, out depth, out index, out _);

    static bool Lookup(Symbol s, Scope sc, out int depth, out int index, out bool letrec)
    {
      depth = 0;
      for (; sc != null; sc = sc.Parent, depth++)
      {
        index = sc.Vars.LastIndexOf(s);
        if (index >= 0) { letrec = sc.Letrec; return true; }
      }
      index = -1;
      letrec = false;
      return false;
    }

    Node AnalyzePair(Cons c, Scope sc, bool tail)
    {
      object head = c.car;
      if (head is Symbol h && !Lookup(h, sc, out _, out _))
      {
        var args = c.cdr;
        if (h == Quote) return new Const(Nth(args, 0));
        if (h == IfS)
        {
          var test = Analyze(Nth(args, 0), sc, false);
          var then = Analyze(Nth(args, 1), sc, tail);
          var rest = (Cons)((Cons)args).cdr;
          return new If(test, then, rest.cdr is Cons e ? Analyze(e.car, sc, tail) : null);
        }
        if (h == Begin) return Body(args, sc, tail);
        if (h == SetS) return Assign((Symbol)Nth(args, 0), Analyze(Nth(args, 1), sc, false), sc);
        if (h == CaseLambda) return MakeLambda(args, sc, false, null);
        if (h == AnnCaseLambda) return MakeLambda(((Cons)args).cdr, sc, false, null);
        if (h == TypedCaseLambda) return MakeLambda(args, sc, true, null);
        if (h == AnnTypedCaseLambda) return MakeLambda(((Cons)args).cdr, sc, true, null);
        if (h == LambdaS) return MakeLambda(new Cons(args, null), sc, false, null);
        if (h == LetrecS || h == LetrecStar) return MakeLetrec(Nth(args, 0), ((Cons)args).cdr, sc, tail);
        if (h == LibraryLetrecStar) return MakeLibraryLetrec((Cons)args, sc, tail);
        if (h == AnnotatedCall) return Analyze(((Cons)args).cdr, sc, tail);
        if (h == AndP) return new And(AnalyzeList(args, sc));
        if (h == OrP) return new Or(AnalyzeList(args, sc));
        if (h == ThrowP) return new Throw(Analyze(Nth(args, 0), sc, false));
        if (h == BreakP) return new Break();
        if (h == TryFinallyP) return new TryFinally(Analyze(Nth(args, 0), sc, false), Analyze(Nth(args, 1), sc, false));
        var clr = AnalyzeClr(h, args, sc);
        if (clr != null) return clr;
        if (UnsupportedForms.Contains(h)) return new Unsupported(h.Name);
      }
      return new App(Analyze(head, sc, false), AnalyzeList(c.cdr, sc), tail);
    }

    Node Assign(Symbol s, Node value, Scope sc) =>
      Lookup(s, sc, out int d, out int i) ? new LocalSet(d, i, value) : (Node)new GlobalSet(s, value);

    Node[] AnalyzeList(object list, Scope sc)
    {
      var r = new List<Node>();
      for (object p = list; p is Cons c; p = c.cdr) r.Add(Analyze(c.car, sc, false));
      return r.ToArray();
    }

    Node Body(object body, Scope sc, bool tail)
    {
      var r = new List<Node>();
      for (object p = body; p is Cons c; p = c.cdr) r.Add(Analyze(c.car, sc, tail && c.cdr == null));
      if (r.Count == 0) return new Const(Unspecified.Instance);
      return r.Count == 1 ? r[0] : new Seq(r.ToArray());
    }

    /// <summary>clauses：子句列表；typed 时子句为 (fmls tspec body …)，否则 (fmls body …)。</summary>
    Node MakeLambda(object clauses, Scope sc, bool typed, string name)
    {
      var saved = new List<string>(namespaces);
      var list = new List<Clause>();
      for (object p = clauses; p is Cons c; p = c.cdr)
      {
        var clause = (Cons)c.car;
        var vars = new List<Symbol>();
        object fmls = clause.car;
        for (; fmls is Cons fc; fmls = fc.cdr) vars.Add((Symbol)fc.car);
        var cl = new Clause { Required = vars.Count, Rest = fmls is Symbol };
        if (fmls is Symbol restVar) vars.Add(restVar);
        object body = typed ? ((Cons)clause.cdr).cdr : clause.cdr;
        cl.Body = Body(body, new Scope(vars, sc), true);
        list.Add(cl);
        namespaces = new List<string>(saved);
      }
      namespaces = saved;
      return new Lambda(new LambdaInfo { Clauses = list.ToArray(), Name = name });
    }

    static bool IsLambdaForm(object x) =>
      x is Cons c && c.car is Symbol h && (h == CaseLambda || h == AnnCaseLambda || h == TypedCaseLambda || h == AnnTypedCaseLambda || h == LambdaS);

    /// <summary>右部是 lambda 时把绑定名作为过程名（错误信息与打印用）。</summary>
    Node AnalyzeBinding(object rhs, Symbol name, Scope sc)
    {
      var n = Analyze(rhs, sc, false);
      if (n is Lambda l && IsLambdaForm(rhs)) l.Info.Name ??= name.Ungensym().Name;
      return n;
    }

    Node MakeLetrec(object bindings, object body, Scope sc, bool tail)
    {
      var saved = new List<string>(namespaces);
      var vars = new List<Symbol>();
      for (object p = bindings; p is Cons c; p = c.cdr) vars.Add((Symbol)((Cons)c.car).car);
      var inner = new Scope(vars, sc, true);
      var inits = new List<Node>();
      for (object p = bindings; p is Cons c; p = c.cdr)
      {
        var b = (Cons)c.car;
        inits.Add(AnalyzeBinding(Nth(b, 1), (Symbol)b.car, inner));
      }
      var r = new Letrec(inits.ToArray(), Body(body, inner, tail));
      namespaces = saved;
      return r;
    }

    // (library-letrec* name ((x loc e) …) body …)
    Node MakeLibraryLetrec(Cons args, Scope sc, bool tail)
    {
      var saved = new List<string>(namespaces);
      bool isProgram = args.car == null;
      object bindings = Nth(args, 1);
      var vars = new List<Symbol>();
      var locs = new List<Symbol>();
      for (object p = bindings; p is Cons c; p = c.cdr)
      {
        var b = (Cons)c.car;
        vars.Add((Symbol)b.car);
        locs.Add((Symbol)Nth(b, 1));
      }
      var inner = new Scope(vars, sc, true);
      var inits = new List<Node>();
      for (object p = bindings; p is Cons c; p = c.cdr)
      {
        var b = (Cons)c.car;
        inits.Add(AnalyzeBinding(Nth(b, 2), (Symbol)b.car, inner));
      }
      var r = new LibraryLetrec(inits.ToArray(), isProgram ? null : locs.ToArray(), Body(((Cons)args.cdr).cdr, inner, tail));
      namespaces = saved;
      return r;
    }

    Node AnalyzeClr(Symbol h, object args, Scope sc)
    {
      TypeRef T() => new TypeRef(Quoted(Nth(args, 0)), namespaces.ToArray());
      if (h == ClrCallI)
        return new ClrCall(T(), Quoted(Nth(args, 1)), Analyze(Nth(args, 2), sc, false), AnalyzeList(Drop(args, 3), sc), namespaces.ToArray());
      if (h == ClrFieldGetI) return new ClrFieldGet(T(), MemberName(Quoted(Nth(args, 1))), Analyze(Nth(args, 2), sc, false));
      if (h == ClrFieldSetI) return new ClrFieldSet(T(), MemberName(Quoted(Nth(args, 1))), Analyze(Nth(args, 2), sc, false), Analyze(Nth(args, 3), sc, false));
      if (h == ClrNewI) return new ClrNew(T(), AnalyzeList(((Cons)args).cdr, sc));
      if (h == ClrNewArrayI) return new ClrNewArray(T(), Analyze(Nth(args, 1), sc, false));
      if (h == ClrCastI) return new ClrCast(T(), Analyze(Nth(args, 1), sc, false));
      if (h == ClrIsI) return new ClrIs(T(), Analyze(Nth(args, 1), sc, false));
      if (h == ClrTypeOfI) return new ClrTypeOf(T());
      if (h == ClrUsingI)
      {
        var ns = Quoted(Nth(args, 0));
        if (!(ns is Symbol nsym)) return new Const(Errors.SyntaxError("clr-using", "namespace is not a symbol", ns, RT.False));
        if (!namespaces.Contains(nsym.Name)) namespaces.Add(nsym.Name);
        return new Const(Unspecified.Instance);
      }
      if (h == ClrReferenceI)
      {
        ClrReferences.Load(Quoted(Nth(args, 0)));
        return new Const(Unspecified.Instance);
      }
      if (h == ClrNamespacesI) return new Const(Cons.FromList(namespaces.ToArray()));
      return null;
    }

    static string MemberName(object spec) => spec is Symbol s ? s.Name : spec as string;

    /// <summary>(quote d) → d；clr 形式的类型与成员说明总是被 quote。</summary>
    static object Quoted(object x) =>
      x is Cons c && ReferenceEquals(c.car, Quote) ? Nth(c.cdr, 0) : Errors.SyntaxError("clr", "expected a quoted type or member", x, RT.False);

    static object Nth(object list, int n)
    {
      for (; n > 0; n--) list = ((Cons)list).cdr;
      return ((Cons)list).car;
    }

    static object Drop(object list, int n)
    {
      for (; n > 0; n--) list = ((Cons)list).cdr;
      return list;
    }
  }
}

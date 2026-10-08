using System.Text;

namespace IronScheme.Core
{
  /// <summary>符号与全局值槽相关的原语。</summary>
  public static class SymbolPrimitives
  {
    static Symbol Sym(object o, string who) => Errors.RequiresType<Symbol>(o, who);

    [Primitive("symbol-value")]
    public static object SymbolValue(object symbol)
    {
      var s = Sym(symbol, "symbol-value");
      object v = s.Value;
      return v is Unbound ? Errors.UndefinedError(s) : v;
    }

    [Primitive("set-symbol-value!")]
    public static object SetSymbolValue(object symbol, object value)
    {
      Sym(symbol, "set-symbol-value!").Value = value;
      return Unspecified.Instance;
    }

    [Primitive("symbol-bound?")]
    public static object IsSymbolBound(object symbol) => RT.Bool(Sym(symbol, "symbol-bound?").IsBound);

    [Primitive("remove-location")]
    public static object RemoveLocation(object symbol)
    {
      Sym(symbol, "remove-location").Value = Unbound.Instance;
      return Unspecified.Instance;
    }

    [Primitive("string->symbol", Flags = PrimitiveFlags.Pure)]
    public static object StringToSymbol(object str) => str switch
    {
      string s => Symbol.Intern(s),
      StringBuilder sb => Symbol.Intern(sb.ToString()),   // 可变字符串
      _ => Errors.AssertionViolation("string->symbol", "not a string", str),
    };

    [Primitive("symbol->string", Flags = PrimitiveFlags.Pure)]
    public static object SymbolToString(object symbol) => Sym(symbol, "symbol->string").Name;

    [Primitive("gensym")]
    public static object Gensym() => Symbol.Gensym();

    [Primitive("gensym")]
    public static object Gensym(object name) => name switch
    {
      string s => Symbol.Gensym(s),
      StringBuilder sb => Symbol.Gensym(sb.ToString()),
      Symbol sym => Symbol.Gensym(sym.Ungensym().Name),
      _ => Errors.AssertionViolation("gensym", "not a string or symbol", name),
    };

    [Primitive("ungensym", Flags = PrimitiveFlags.Pure)]
    public static object Ungensym(object symbol) => Sym(symbol, "ungensym").Ungensym();
  }
}

// iron-013：检查 Scheme 源码中的 clr-* 形式能否在新运行时（IronScheme.Core + BCL）上解析。
// 用法：ClrCheck <源码根目录> <相对路径 …>
// 按文件收集 (clr-using 命名空间)，对每个 clr-* 形式解析类型并检查成员是否存在（按参数个数粗查）。
using System.Reflection;
using IronScheme.Core;

typeof(Cons).Assembly.GetTypes();   // 确保 IronScheme.Core 已加载，供 TypeResolver 查找
var root = args[0];
int forms = 0, problems = 0;
var report = new SortedSet<string>(StringComparer.Ordinal);

foreach (var rel in args.Skip(1))
{
  List<object> data;
  try { data = new SchemeReader(new StringReader(File.ReadAllText(Path.Combine(root, rel))), rel, false).ReadAll(); }
  catch (ReaderException e) { report.Add($"{rel}: read error {e.Message}"); problems++; continue; }

  var ns = new List<string>();
  void CollectUsing(object x)
  {
    if (x is Cons c)
    {
      if (c.car is Symbol s && s.Name == "clr-using" && c.cdr is Cons a && a.car is Symbol n) ns.Add(n.Name);
      for (object p = c; p is Cons pc; p = pc.cdr) CollectUsing(pc.car);
    }
    else if (x is object[] v) foreach (var e in v) CollectUsing(e);
  }
  foreach (var d in data) CollectUsing(d);

  void Check(object x)
  {
    if (x is object[] v) { foreach (var e in v) Check(e); return; }
    if (x is not Cons c) return;
    for (object p = c; p is Cons pc; p = pc.cdr) Check(pc.car);
    if (c.car is not Symbol head || !head.Name.StartsWith("clr-")) return;
    var items = c.ToList();
    string form = head.Name;
    var simple = new HashSet<string> { "clr-static-call", "clr-call", "clr-prop-get", "clr-prop-set!", "clr-static-prop-get", "clr-static-prop-set!",
      "clr-field-get", "clr-field-set!", "clr-static-field-get", "clr-static-field-set!", "clr-new", "clr-new-array", "clr-is", "clr-cast", "clr-type-of",
      "clr-static-event-add!", "clr-static-event-remove!", "clr-event-add!", "clr-event-remove!" };
    if (!simple.Contains(form) || items.Count < 2) return;
    forms++;
    var typeSpec = items[1];
    var t = TypeResolver.Resolve(typeSpec, ns);
    string where = $"{rel}: ({form} {typeSpec} {(items.Count > 2 ? items[2] : "")})";
    if (t == null) { report.Add($"{where}  => TYPE NOT FOUND"); problems++; return; }
    if (form is "clr-new-array" or "clr-is" or "clr-cast" or "clr-type-of") return;
    if (form == "clr-new")
    {
      int argc = items.Count - 2;
      if (!(t.IsValueType && argc == 0) && !t.GetConstructors().Any(k => Fits(k, argc))) { report.Add($"{where}  => no ctor with {argc} args on {t.FullName}"); problems++; }
      return;
    }
    if (items.Count < 3) return;
    string member = items[2] switch { Symbol s => s.Name, string s => s.Split('(')[0], Cons mc when mc.car is Symbol ms => ms.Name, _ => null };
    if (member == null) return;
    bool isStatic = form.StartsWith("clr-static-");
    var flags = BindingFlags.Public | (isStatic ? BindingFlags.Static : BindingFlags.Instance) | BindingFlags.FlattenHierarchy;
    bool ok = form switch
    {
      "clr-static-call" or "clr-call" => t.GetMember(member, MemberTypes.Method, flags).Cast<MethodBase>().Any(m => Fits(m, items.Count - (isStatic ? 3 : 4)))
                                          || (member is "get_Item" or "set_Item"),
      "clr-prop-get" or "clr-static-prop-get" => t.GetProperty(member, flags) != null || t.GetMethod("get_" + member, flags) != null,
      "clr-prop-set!" or "clr-static-prop-set!" => t.GetProperty(member, flags)?.CanWrite == true || t.GetMethod("set_" + member, flags) != null,
      "clr-field-get" or "clr-field-set!" or "clr-static-field-get" or "clr-static-field-set!" => t.GetField(member, flags) != null,
      _ => t.GetEvent(member, flags) != null,
    };
    if (!ok) { report.Add($"{where}  => member '{member}' not found on {t.FullName}"); problems++; }
  }
  foreach (var d in data) Check(d);
}

Console.WriteLine($"clr forms checked: {forms}, problems: {problems}");
foreach (var r in report) Console.WriteLine(r);
return problems == 0 ? 0 : 1;

static bool Fits(MethodBase m, int argc)
{
  var ps = m.GetParameters();
  bool hasParams = ps.Length > 0 && ps[^1].IsDefined(typeof(ParamArrayAttribute), false);
  return argc < 0 || ps.Length == argc || (hasParams && argc >= ps.Length - 1);
}

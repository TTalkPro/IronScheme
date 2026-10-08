// iron-010 验收：新 reader 与旧 reader 对照。
// 旧系统（legacy-stage0）已用 dump.sps 把每个文件读出并 write 成 out/<i>.dump。
// 本工具：新 reader 读原文件得 D2，读 dump 得 D1，逐个结构比较。
// 用法：ReaderCompare <files.txt> <dump 目录> <源码根目录>
using IronScheme.Core;

if (args[0] == "--spans")
{
  // 打印文件第一个顶层表单及其前 5 个子表单的注解位置，与旧系统对照
  var a = (ConsAnnotation)new SchemeReader(new StringReader(File.ReadAllText(args[1])), args[1], true).Read();
  Console.WriteLine(((Cons)a.source).cdr);
  int n = 0;
  for (object x = a.expression; x is Cons c && n < 5; x = c.cdr, n++)
    if (c.car is Annotation an) Console.WriteLine(((Cons)an.source).cdr);
  return 0;
}
var files = File.ReadAllLines(args[0]);
string dumpDir = args[1], root = args[2];
int same = 0, legacyFailed = 0, newFailed = 0, mismatched = 0, bothFailed = 0;
var report = new List<string>();

for (int i = 0; i < files.Length; i++)
{
  string dumpText = File.ReadAllText(Path.Combine(dumpDir, i + ".dump"));
  bool legacyError = dumpText.Contains("#<error>");
  dumpText = dumpText.Replace("#<error>", "");

  List<object> d2 = null, d1 = null;
  string newError = null;
  try { d2 = new SchemeReader(new StringReader(File.ReadAllText(Path.Combine(root, files[i]))), files[i], false).ReadAll(); }
  catch (ReaderException e) { newError = $"{e.Message} at ({e.Line},{e.Column})"; }

  if (legacyError && newError != null) { bothFailed++; report.Add($"BOTH-FAIL  {files[i]}: {newError}"); continue; }
  if (legacyError) { legacyFailed++; report.Add($"LEGACY-FAIL {files[i]} (new reader read {d2.Count} data)"); continue; }
  if (newError != null) { newFailed++; report.Add($"NEW-FAIL   {files[i]}: {newError}"); continue; }

  try { d1 = new SchemeReader(new StringReader(dumpText), "dump", false).ReadAll(); }
  catch (ReaderException e) { mismatched++; report.Add($"DUMP-UNREADABLE {files[i]}: {e.Message} at ({e.Line},{e.Column})"); continue; }

  string diff = d1.Count != d2.Count ? $"datum count legacy={d1.Count} new={d2.Count}" : null;
  for (int k = 0; diff == null && k < d1.Count; k++) diff = Diff(d1[k], d2[k], $"#{k}");
  if (diff == null) same++; else { mismatched++; report.Add($"MISMATCH   {files[i]}: {diff}"); }
}

Console.WriteLine($"files={files.Length} same={same} mismatched={mismatched} new-only-fail={newFailed} legacy-only-fail={legacyFailed} both-fail={bothFailed}");
foreach (var r in report) Console.WriteLine(r);
return mismatched + newFailed == 0 ? 0 : 1;

static string Show(object o) => o switch
{
  null => "()",
  string s => "\"" + s + "\"",
  char c => $"char U+{(int)c:X4}",
  SchemeChar sc => $"schemechar U+{sc.Value:X}",
  _ => $"{o} : {o.GetType().Name}",
};

static string Diff(object a, object b, string path)
{
  if (a is Cons ca && b is Cons cb)
  {
    int k = 0;
    object x = ca, y = cb;
    for (; x is Cons px && y is Cons py; x = px.cdr, y = py.cdr, k++)
    {
      var d = Diff(px.car, py.car, $"{path}/{k}");
      if (d != null) return d;
    }
    return Diff(x, y, $"{path}/tail");
  }
  if (a is object[] va && b is object[] vb)
  {
    if (va.Length != vb.Length) return $"{path}: vector length {va.Length} vs {vb.Length}";
    for (int k = 0; k < va.Length; k++) { var d = Diff(va[k], vb[k], $"{path}[{k}]"); if (d != null) return d; }
    return null;
  }
  if (a is Array aa && b is Array ab && a.GetType() == b.GetType())
    return aa.Cast<object>().SequenceEqual(ab.Cast<object>()) ? null : $"{path}: {a.GetType().Name} contents differ";
  if (a is double da && b is double db)
    return BitConverter.DoubleToInt64Bits(da) == BitConverter.DoubleToInt64Bits(db) || (double.IsNaN(da) && double.IsNaN(db)) ? null : $"{path}: {da:R} vs {db:R}";
  if (ReferenceEquals(a, b) || Equals(a, b)) return null;
  if (a != null && b != null && a.GetType() == b.GetType() && Builtins.IsEqualValue(a, b) == RT.True) return null;
  return $"{path}: legacy {Show(a)} vs new {Show(b)}";
}

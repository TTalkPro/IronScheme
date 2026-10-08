using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using System.Xml;

namespace IronScheme.Core
{
  /// <summary>运行时开关（取代旧 ScriptDomainManager.Options 中 Scheme 可见的部分）。</summary>
  public static class RuntimeOptions
  {
    public static bool StrictMode;
    public static bool DebugMode;
    public static bool CompressConstants;
    public static bool CompileToCurrentDirectory = true;
    /// <summary>旧系统的轻量调试模式。新运行时不提供调试器（02 §10），开关仅保留以兼容 Scheme 代码。</summary>
    public static bool LightweightDebugging;
    /// <summary>构建模式：gensym 按"作用域 + 计数"确定性命名（Symbol.cs，iron-014）。</summary>
    public static bool DeterministicGensym;
  }

  /// <summary>从旧 Builtins.cs 移植的杂项原语（iron-008 步骤 G）。</summary>
  public partial class Builtins
  {
    #region 版本、命令行、目录

    /// <summary>由宿主设置；默认为运行时版本。</summary>
    public static string VersionString = CoreInfo.Version;

    [Primitive("ironscheme-version")]
    public static object Version() => VersionString;

    [Primitive("ironscheme-runtime")]
    public static object GetRuntime() => RuntimeInformation.FrameworkDescription;

    /// <summary>由宿主设置。</summary>
    public static string[] CommandLineArgs = { "not set" };

    [Primitive("command-line")]
    [Primitive("get-command-line")]
    public static object CommandLine() => IronScheme.Core.Cons.FromList(CommandLineArgs);

    public static string ApplicationDirectory => Path.GetDirectoryName(typeof(Builtins).Assembly.Location);

    static readonly List<string> includepaths = new List<string>();

    public static void AddIncludePath(string path) => includepaths.Add(path);

    [Primitive("get-library-paths")]
    public static object GetLibraryPaths()
    {
      var paths = new List<string>(includepaths) { ".", Path.Combine(ApplicationDirectory, "lib"), ApplicationDirectory };
      return IronScheme.Core.Cons.FromList(paths);
    }

    #endregion

    #region 运行时开关

    static object Flag(ref bool flag) => GetBool(flag);
    static object SetFlag(ref bool flag, object value) { flag = IsTrue(value); return Unspecified; }

    [Primitive("strict-mode?")] public static object StrictMode() => Flag(ref RuntimeOptions.StrictMode);
    [Primitive("strict-mode?")] public static object StrictMode(object value) => SetFlag(ref RuntimeOptions.StrictMode, value);
    [Primitive("debug-mode?")] public static object IsDebugMode() => Flag(ref RuntimeOptions.DebugMode);
    [Primitive("debug-mode?")] public static object IsDebugMode(object value) => SetFlag(ref RuntimeOptions.DebugMode, value);
    [Primitive("compress-constants?")] public static object CompressConstants() => Flag(ref RuntimeOptions.CompressConstants);
    [Primitive("compress-constants?")] public static object CompressConstants(object value) => SetFlag(ref RuntimeOptions.CompressConstants, value);
    [Primitive("compile-to-current-directory?")] public static object CompileToCurrentDirectory() => Flag(ref RuntimeOptions.CompileToCurrentDirectory);
    [Primitive("compile-to-current-directory?")] public static object CompileToCurrentDirectory(object value) => SetFlag(ref RuntimeOptions.CompileToCurrentDirectory, value);
    [Primitive("lw-debug-mode?")] public static object IsLightWeightDebugMode() => Flag(ref RuntimeOptions.LightweightDebugging);
    [Primitive("lw-debug-mode?")] public static object IsLightWeightDebugMode(object value) => SetFlag(ref RuntimeOptions.LightweightDebugging, value);
    [Primitive("deterministic-gensym?")] public static object DeterministicGensym() => Flag(ref RuntimeOptions.DeterministicGensym);
    [Primitive("deterministic-gensym?")] public static object DeterministicGensym(object value) => SetFlag(ref RuntimeOptions.DeterministicGensym, value);

    #endregion

    #region 控制与计时

    [Primitive("void", Flags = PrimitiveFlags.Pure, Inline = "void")]
    public static object Void() => Unspecified;

    [Primitive("unspecified?")]
    public static object IsUnspecified(object o) => GetBool(o == Unspecified);

    /// <summary>
    /// (with-timeout thunk ms)。超时报 assertion-violation。
    /// 与旧实现的差别：.NET Core 不支持 Thread.Abort，超时后后台线程无法终止，只能放弃等待。
    /// </summary>
    [Primitive("with-timeout")]
    public static object WithTimeout(object proc, object duration)
    {
      int ms = RequiresNotNull<int>(duration);
      var p = RequiresNotNull<Procedure>(proc);
      var task = Task.Run(() => p.Call());
      try
      {
        if (!task.Wait(ms))
          return AssertionViolation("with-timeout", $"call exceeded limit: {ms}ms");
      }
      catch (AggregateException ae) when (ae.InnerException != null)
      {
        if (ae.InnerException is SchemeException se) return Raise(se.Condition);
        System.Runtime.ExceptionServices.ExceptionDispatchInfo.Capture(ae.InnerException).Throw();
      }
      return task.Result;
    }

    /// <summary>
    /// (time-it who thunk)：运行 thunk 并把耗时统计写到标准错误。
    /// 与旧实现的差别：旧版在 thunk 接受 1 个参数时传入 Stopwatch（依赖 Callable.Arity），Scheme 源码中未使用，此处只调用无参形式；
    /// 统计直接写 Console.Error，而不是经 Scheme 的 current-error-port。
    /// </summary>
    [Primitive("time-it")]
    public static object TimeIt(object who, object thunk)
    {
      var c = RequiresNotNull<Procedure>(thunk);
      int gc0 = GC.CollectionCount(0) + GC.CollectionCount(1) + GC.CollectionCount(2);
      var self = Process.GetCurrentProcess();
      TimeSpan total0 = self.TotalProcessorTime, user0 = self.UserProcessorTime;
      var sw = Stopwatch.StartNew();
      try
      {
        return c.Call();
      }
      finally
      {
        sw.Stop();
        self.Refresh();
        int gc1 = GC.CollectionCount(0) + GC.CollectionCount(1) + GC.CollectionCount(2);
        Console.Error.Write($@"Statistics for '{who}':
  Real Time:  {sw.Elapsed.TotalMilliseconds:f0}ms
  CPU Time:   {(self.TotalProcessorTime - total0).TotalMilliseconds:f0}ms
  User Time:  {(self.UserProcessorTime - user0).TotalMilliseconds:f0}ms
  GC's:       {gc1 - gc0}
");
      }
    }

    #endregion

    #region 列表、指针、字符串

    static object ListStarHelper(object a, object rest) =>
      rest == null ? a : new IronScheme.Core.Cons(a, ListStarHelper(Car(rest), Cdr(rest)));

    [Primitive("list*")]
    public static object ListStar(object a, params object[] rest) => ListStarHelper(a, IronScheme.Core.Cons.FromArray(rest));
    [Primitive("list*")]
    public static object ListStar(object a, object b) => new IronScheme.Core.Cons(a, b);
    [Primitive("list*")]
    public static object ListStar(object a, object b, object c) => new IronScheme.Core.Cons(a, new IronScheme.Core.Cons(b, c));
    [Primitive("list*")]
    public static object ListStar(object a, object b, object c, object d) =>
      new IronScheme.Core.Cons(a, new IronScheme.Core.Cons(b, new IronScheme.Core.Cons(c, d)));

    [Primitive("pointer+")]
    public static object PointerAdd(object ptr, object ofs) =>
      (IntPtr)((long)RequiresNotNull<IntPtr>(ptr) + RequiresNotNull<int>(ofs));

    /// <summary>
    /// (string-split str delimiter ...)。
    /// 修正旧实现的缺陷：旧版用 <c>del as string[]</c> 取分隔符，而参数数组是 object[]，转换总得到 null，
    /// 结果总是按空白切分（lib/ironscheme/web/routing.sls 按 "?"、"/" 切分的意图无法实现）。
    /// </summary>
    [Primitive("string-split")]
    public static object StringSplit(object str, params object[] del)
    {
      string s = RequiresNotNull<string>(str);
      string[] delimiters = Array.ConvertAll(del, d => RequiresNotNull<string>(d));
      return s.Split(delimiters.Length == 0 ? null : delimiters, StringSplitOptions.None);
    }

    [Primitive("string->xml")]
    public static object StringToXml(object str)
    {
      var doc = new XmlDocument();
      doc.LoadXml(RequiresNotNull<string>(str));
      return ReadElement(doc.DocumentElement);
    }

    static object ReadElement(XmlElement e)
    {
      var all = new List<object> { Symbol.Intern(e.Name) };
      foreach (XmlAttribute a in e.Attributes) all.Add(new IronScheme.Core.Cons(Symbol.Intern(a.Name), a.Value));
      foreach (XmlNode n in e.ChildNodes)
        all.Add(n.NodeType == XmlNodeType.Text ? n.InnerText : ReadElement((XmlElement)n));
      return IronScheme.Core.Cons.FromList(all);
    }

    #endregion

    #region 网络

    [Primitive("open-tcp-input/output-port")]
    public static object OpenTcpInputOutputPort(object host, object port, object maybetranscoder)
    {
      var tcp = new TcpClient();
      string h = RequiresNotNull<string>(host);
      int p = RequiresNotNull<int>(port);
      tcp.Connect(h, p);
      NetworkStream ns = tcp.GetStream();
      if (maybetranscoder is Transcoder tc)
        return new CustomTextReaderWriter(Symbol.Intern($"#<tcp-textual-input/output-port {h}:{p}>"),
          new StreamReader(ns, tc.codec), new StreamWriter(ns, tc.codec));
      return ns;
    }

    #endregion

    #region 构建脚本与 psyntax 直接调用的方法（非原语）

    /// <summary>构建脚本生成 (psyntax primlocs) 时调用：((原语名 . 位置) ...) → 哈希表。</summary>
    public static object MakePrimlocHashtable(IronScheme.Core.Cons map)
    {
      var ht = new Hashtable(1024);
      foreach (IronScheme.Core.Cons m in map) ht[m.car] = m.cdr;
      return ht;
    }

    /// <summary>旧编译器生成的库代码与 psyntax 用它设置全局位置；新运行时直接写符号值槽。</summary>
    public static void SetSymbolValueFast(object symbol, object value) => ((Symbol)symbol).Value = value;

    public static object ListToByteVector(object obj)
    {
      object[] items = ListToVector(obj);
      var buffer = new byte[items.Length];
      for (int i = 0; i < buffer.Length; i++)
      {
        try { buffer[i] = Convert.ToByte(items[i]); }
        catch (Exception ex) { return LexicalError(ex.Message, items[i]); }
      }
      return buffer;
    }

    #endregion
  }
}

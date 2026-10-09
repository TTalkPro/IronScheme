#!/usr/bin/env -S dotnet run
// IronScheme 的维护命令（.NET 10 单文件程序，Windows / Linux / macOS 通用，只需要 .NET SDK）。
// 日常构建与测试不需要它：在仓库根目录 dotnet build / dotnet test 即可，boot 镜像由 IronScheme.Host 项目的
// GenerateBootImage 目标生成（增量）。这里是常规构建之外的命令：
//
//   dotnet run tools/build.cs -- <命令> [参数]      （Linux / macOS 上也可以直接 ./tools/build.cs <命令>）
//
// 命令：
//   stage1 [输出目录]     编译 C# 项目后，stage0 执行文本种子、运行 ironscheme-buildscript-nano.sps，
//                         把 ironscheme.boot.lcil 与 ironscheme.boot.dll 输出到指定目录（自举比对用；
//                         默认 src/scheme/build/，此时等同 dotnet build，但总是重新生成）
//   seed [--stage0]       重新生成文本种子 src/scheme/boot-seed.core（05 §5）：默认在新系统上运行
//                         （需要 build/ironscheme.boot.dll），--stage0 由 stage0 执行现有种子来运行；两者产物相同
//   ilverify <dll> …      用 ILVerify 校验发射器生成的程序集（dotnet tool install -g dotnet-ilverify）
//   publish [app.sps] [-r RID] [-o 目录] [-n 名字] [-I 库目录]…
//                         自包含单文件发布（designs/07-tooling-and-embedding.md §3），目标机器不需要安装 .NET：
//                         不带 app.sps 时发布 IronScheme 宿主（boot 镜像嵌入，lib/ 在可执行文件旁）；
//                         带 app.sps 时把该程序及其用到的库编译（compile-whole-program）后嵌入，得到独立的应用。
//                         默认 RID 为当前平台，默认输出 artifacts/publish/<名字>-<RID>/
//
// 相对路径参数按调用时的当前目录解析。
using System.Diagnostics;
using System.Runtime.InteropServices;

string root = Path.GetFullPath(Path.Combine(Path.GetDirectoryName((string)AppContext.GetData("EntryPointFilePath")!)!, ".."));
string srcDir = Path.Combine(root, "src");
string solution = Path.Combine(root, "IronScheme.slnx");
string schemeDir = Path.Combine(srcDir, "scheme");
string Bin(string project, string dll) => Path.Combine(srcDir, project, "bin", "Release", "net10.0", dll);

try
{
  string command = args.Length > 0 ? args[0] : "help";
  string[] rest = args.Skip(1).ToArray();
  switch (command)
  {
    case "stage1":
      BuildCSharp();
      Stage1(rest);
      break;
    case "seed":
      Seed(rest.Contains("--stage0"));
      break;
    case "publish":
      Publish(rest);
      break;
    case "ilverify":
      if (rest.Length == 0) return Usage();
      foreach (var dll in rest) ILVerify(Path.GetFullPath(dll));
      break;
    default:
      return Usage();
  }
  return 0;
}
catch (CommandFailed e)
{
  Console.Error.WriteLine(e.Message);
  return 1;
}

int Usage()
{
  Console.Error.WriteLine("usage: dotnet run tools/build.cs -- stage1 [outdir] | seed [--stage0] | ilverify <dll>... | publish [app.sps] [-r RID] [-o dir] [-n name] [-I dir]...");
  Console.Error.WriteLine("(to build and test: dotnet build / dotnet test in the repository root)");
  return 2;
}

// stage0 执行种子 → 运行 nano 构建脚本 → stage1 boot 镜像
void Stage1(string[] a)
{
  string outDir = a.Length > 0 ? Path.GetFullPath(a[0]) : Path.Combine(schemeDir, "build");
  Run("dotnet", [Bin("IronScheme.Stage0", "stage0.dll"), "-I", "lib", "-I", "lib/nanopass-framework-scheme",
                 "boot-seed.core", "ironscheme-buildscript-nano.sps", outDir], schemeDir);
}

// 只编译 C# 项目（不经 MSBuild 生成 boot 镜像）
void BuildCSharp() => Run("dotnet", ["build", solution, "-c", "Release", "-p:BuildBootImage=false", "-v", "quiet", "-nologo"]);

void Seed(bool onStage0)
{
  BuildCSharp();
  if (onStage0)
  {
    // 脚本会覆盖 boot-seed.core，stage0 执行的是它的副本
    string tmp = Directory.CreateTempSubdirectory("ironscheme-seed").FullName;
    try
    {
      string copy = Path.Combine(tmp, "boot-seed.core");
      File.Copy(Path.Combine(schemeDir, "boot-seed.core"), copy);
      Run("dotnet", [Bin("IronScheme.Stage0", "stage0.dll"), "-I", "lib", copy, "seed-buildscript.sps", "./"], schemeDir);
    }
    finally
    {
      Directory.Delete(tmp, true);
    }
  }
  else
  {
    string boot = Path.Combine(schemeDir, "build", "ironscheme.boot.dll");
    if (!File.Exists(boot)) throw new CommandFailed($"{boot} not found: run dotnet build first, or use 'seed --stage0'");
    Run("dotnet", [Bin("IronScheme.Host", "IronScheme.Host.dll"), "--boot", boot, "-I", "lib", "seed-buildscript.sps", "./"], schemeDir);
  }
}

void ILVerify(string dll)
{
  string tool = Environment.GetEnvironmentVariable("ILVERIFY")
    ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".dotnet", "tools",
                    OperatingSystem.IsWindows() ? "ilverify.exe" : "ilverify");
  if (!File.Exists(tool)) throw new CommandFailed($"ilverify not found at {tool}: dotnet tool install -g dotnet-ilverify (or set ILVERIFY)");
  // 本程序运行在 .NET 10 上，其运行时目录就是要引用的框架程序集
  string runtimeDir = RuntimeEnvironment.GetRuntimeDirectory();
  Run(tool, [dll,
             "-r", Path.Combine(runtimeDir, "*.dll"),
             "-r", Bin("IronScheme.Core", "IronScheme.Core.dll"),
             "-r", Bin("IronScheme.Core", "Oyster.IntX.dll"),
             "-r", Bin("IronScheme.Emit", "IronScheme.Emit.dll")]);
}

void Publish(string[] a)
{
  string app = null, rid = RuntimeInformation.RuntimeIdentifier, outDir = null, name = null;
  var libs = new List<string>();
  for (int i = 0; i < a.Length; i++)
  {
    switch (a[i])
    {
      case "-r" when i + 1 < a.Length: rid = a[++i]; break;
      case "-o" when i + 1 < a.Length: outDir = Path.GetFullPath(a[++i]); break;
      case "-n" when i + 1 < a.Length: name = a[++i]; break;
      case "-I" when i + 1 < a.Length: libs.Add(Path.GetFullPath(a[++i])); break;
      default:
        if (app != null || a[i].StartsWith("-")) throw new CommandFailed("publish: unexpected argument " + a[i]);
        app = Path.GetFullPath(a[i]);
        break;
    }
  }
  name ??= app == null ? "ironscheme" : Path.GetFileNameWithoutExtension(app);
  outDir ??= Path.Combine(root, "artifacts", "publish", name + "-" + rid);
  // 常规构建（含 boot 镜像）
  Run("dotnet", ["build", solution, "-c", "Release", "-v", "quiet", "-nologo"]);
  var props = new List<string> { "-p:PublishSingleFile=true", "-p:EmbedBootImage=true", "-p:BuildBootImage=false" };
  string appDir = null;
  if (app != null)
  {
    if (!File.Exists(app)) throw new CommandFailed("publish: file not found: " + app);
    // 编译程序及其用到的库（在新宿主上运行 compile-whole-program），产物嵌入可执行文件
    appDir = Directory.CreateTempSubdirectory("ironscheme-app").FullName;
    string script = Path.Combine(appDir, "compile.sps");
    File.WriteAllText(script, "(import (ironscheme))\n(compile-whole-program " + Quote(app) + " " + Quote(Path.Combine(appDir, "out")) + ")\n");
    var hostArgs = new List<string> { Bin("IronScheme.Host", "IronScheme.Host.dll") };
    foreach (var l in libs.Append(Path.Combine(schemeDir, "lib"))) { hostArgs.Add("-I"); hostArgs.Add(l); }
    hostArgs.Add(script);
    Run("dotnet", hostArgs.ToArray(), Path.GetDirectoryName(app));
    props.Add("-p:IronSchemeApp=" + Path.Combine(appDir, "out"));
    props.Add("-p:IronSchemeAppName=" + name);
    // 单独的中间与输出目录由宿主项目按 IronSchemeAppName 设置（不作为全局属性传入，见 IronScheme.Host.csproj）
  }
  try
  {
    if (Directory.Exists(outDir)) Directory.Delete(outDir, true);
    Run("dotnet", ["publish", Path.Combine(srcDir, "IronScheme.Host", "IronScheme.Host.csproj"), "-c", "Release", "-r", rid,
                   "--self-contained", "-o", outDir, "-v", "quiet", "-nologo", .. props]);
  }
  finally
  {
    if (appDir != null) Directory.Delete(appDir, true);
  }
  // 调试符号不随发布；被引用的可执行项目（Emit、stage0）留下的 runtimeconfig 单文件发布不需要
  foreach (var f in Directory.GetFiles(outDir, "*.pdb").Concat(Directory.GetFiles(outDir, "*.runtimeconfig.json"))) File.Delete(f);
  Console.WriteLine("published " + Path.Combine(outDir, name == "ironscheme" ? "IronScheme.Host" : name) + (OperatingSystem.IsWindows() ? ".exe" : ""));
}

static string Quote(string s) => "\"" + s.Replace("\\", "\\\\").Replace("\"", "\\\"") + "\"";

// 运行子进程，继承标准输出与错误；标准输入关闭（构建脚本不读输入，REPL 模式下也不会等待）。失败时抛出 CommandFailed。
void Run(string file, string[] arguments, string? workingDir = null)
{
  // 输出被重定向时（如在测试中运行）不保留 MSBuild 节点进程：它们继承输出管道，调用方会一直等不到输出结束
  if (file == "dotnet" && arguments.Length > 0 && arguments[0] is "build" or "publish" && Console.IsOutputRedirected)
    arguments = [.. arguments, "-nodeReuse:false"];
  var psi = new ProcessStartInfo(file) { WorkingDirectory = workingDir ?? Environment.CurrentDirectory, RedirectStandardInput = true };
  foreach (var x in arguments) psi.ArgumentList.Add(x);
  using var p = Process.Start(psi) ?? throw new CommandFailed($"cannot start {file}");
  p.StandardInput.Close();
  p.WaitForExit();
  if (p.ExitCode != 0) throw new CommandFailed($"command failed (exit {p.ExitCode}): {file} {string.Join(" ", arguments)}");
}

sealed class CommandFailed(string message) : Exception(message);

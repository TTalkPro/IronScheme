using System;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;
using System.Threading;
using NUnit.Framework;

namespace IronScheme.Tests
{
  /// <summary>
  /// 嵌入示例 examples/WebServer（iron-039，designs/07-tooling-and-embedding.md §5）：启动服务，
  /// 经 HTTP 检查 C# 路由调用 Scheme 库 (bookstore)、Scheme 用 Microsoft.Data.Sqlite 查询 SQLite 的结果。
  /// </summary>
  [Order(6)]
  [Category(nameof(Examples))]
  [NonParallelizable]
  public class Examples
  {
    Process server;
    HttpClient http;
    string db;

    static string WebServerDll => Path.Combine(Paths.RepoDir, "examples", "WebServer", "bin", Paths.Configuration, Paths.Framework, "WebServer.dll");

    static int FreePort()
    {
      var l = new TcpListener(IPAddress.Loopback, 0);
      l.Start();
      int port = ((IPEndPoint)l.LocalEndpoint).Port;
      l.Stop();
      return port;
    }

    [OneTimeSetUp]
    public void Start()
    {
      if (!File.Exists(WebServerDll)) Assert.Ignore("examples/WebServer not built");
      db = Path.Combine(Path.GetTempPath(), "ironscheme-bookstore-" + Guid.NewGuid().ToString("N") + ".db");
      string url = $"http://127.0.0.1:{FreePort()}";
      var psi = new ProcessStartInfo("dotnet") { RedirectStandardOutput = true, RedirectStandardError = true, UseShellExecute = false };
      foreach (var a in new[] { WebServerDll, "--urls", url, "--Database", db }) psi.ArgumentList.Add(a);
      server = Process.Start(psi);
      server.OutputDataReceived += (s, e) => { };
      server.ErrorDataReceived += (s, e) => { if (e.Data != null) TestContext.Progress.WriteLine(e.Data); };
      server.BeginOutputReadLine();
      server.BeginErrorReadLine();
      http = new HttpClient { BaseAddress = new Uri(url), Timeout = TimeSpan.FromSeconds(30) };
      for (int i = 0; i < 240; i++)
      {
        if (server.HasExited) Assert.Fail($"WebServer exited with {server.ExitCode}");
        try
        {
          if (http.GetAsync("/api/stats").Result.IsSuccessStatusCode) return;
        }
        catch (AggregateException) { }
        Thread.Sleep(250);
      }
      Assert.Fail("WebServer did not start");
    }

    [OneTimeTearDown]
    public void Stop()
    {
      http?.Dispose();
      if (server != null && !server.HasExited) { server.Kill(true); server.WaitForExit(); }
      server?.Dispose();
      if (db != null) foreach (var f in new[] { db, db + "-wal", db + "-shm" }) if (File.Exists(f)) File.Delete(f);
    }

    JsonElement Get(string path, HttpStatusCode expected = HttpStatusCode.OK)
    {
      var r = http.GetAsync(path).Result;
      Assert.That(r.StatusCode, Is.EqualTo(expected), path);
      var text = r.Content.ReadAsStringAsync().Result;
      return text.Length == 0 ? default : JsonDocument.Parse(text).RootElement;
    }

    JsonElement Post(string path, string json, HttpStatusCode expected)
    {
      var r = http.PostAsync(path, new StringContent(json, Encoding.UTF8, "application/json")).Result;
      Assert.That(r.StatusCode, Is.EqualTo(expected), path);
      return JsonDocument.Parse(r.Content.ReadAsStringAsync().Result).RootElement;
    }

    [Test, Order(1)]
    public void SeededBooksAndStats()
    {
      var books = Get("/api/books");
      Assert.That(books.GetArrayLength(), Is.EqualTo(7));
      Assert.That(books[0].GetProperty("title").GetString(), Is.EqualTo("The Little Schemer"));   // 按年份排序
      var stats = Get("/api/stats");
      Assert.That(stats.GetProperty("count").GetInt32(), Is.EqualTo(7));
      Assert.That(stats.GetProperty("earliest").GetInt32(), Is.EqualTo(1974));
      Assert.That(stats.GetProperty("byDecade").GetArrayLength(), Is.EqualTo(4));
    }

    [Test, Order(2)]
    public void Search()
    {
      var found = Get("/api/books?q=Friedman");
      Assert.That(found.GetArrayLength(), Is.EqualTo(2));
      Assert.That(Get("/api/books?q=no-such-book").GetArrayLength(), Is.EqualTo(0));
    }

    [Test, Order(3)]
    public void AddAndFetch()
    {
      var book = Post("/api/books", "{\"title\":\"Realm of Racket\",\"author\":\"Matthias Felleisen et al.\",\"year\":2013}", HttpStatusCode.Created);
      long id = book.GetProperty("id").GetInt64();
      Assert.That(Get($"/api/books/{id}").GetProperty("year").GetInt32(), Is.EqualTo(2013));
      Assert.That(Get("/api/stats").GetProperty("latest").GetInt32(), Is.EqualTo(2013));
      Get("/api/books/999999", HttpStatusCode.NotFound);
    }

    [Test, Order(4)]
    public void SchemeErrorsBecomeBadRequest()
    {
      var r = Post("/api/books", "{\"title\":\"\",\"author\":\"x\"}", HttpStatusCode.BadRequest);
      Assert.That(r.GetProperty("error").GetString(), Does.Contain("title is required"));
    }
  }
}

// IronScheme 嵌入示例（iron-039）：ASP.NET Core 最小 API 提供 HTTP 路由，业务逻辑由 Scheme 库 (bookstore) 实现。
// C# 经 IronScheme.Hosting 取得 Scheme 过程并调用；Scheme 经 CLR 互操作使用 Microsoft.Data.Sqlite 查询 SQLite。
//
//   dotnet run --project examples/WebServer            （浏览 http://localhost:5000/）
//   GET  /api/books[?q=文本]   GET /api/books/{id}   POST /api/books {"title","author","year"}   GET /api/stats
using IronScheme.Core;
using IronScheme.Hosting;

var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

// 初始化 IronScheme：boot 镜像与 lib/ 随 IronScheme.Hosting 复制到输出目录；Scheme 库源码在输出目录的 scheme/
SchemeRuntime.Initialize(new SchemeRuntimeOptions
{
    LibraryPaths = { Path.Combine(AppContext.BaseDirectory, "scheme") },
});

var bookstore = new Bookstore(app.Configuration["Database"] ?? Path.Combine(AppContext.BaseDirectory, "bookstore.db"));

app.MapGet("/", () => Results.Content(Bookstore.HomePage, "text/html; charset=utf-8"));

app.MapGet("/api/books", (string? q) => Results.Json(bookstore.Books(q)));

app.MapGet("/api/books/{id:long}", (long id) =>
  bookstore.Book(id) is { } book ? Results.Json(book) : Results.NotFound());

app.MapPost("/api/books", (NewBook b) =>
{
    try
    {
        var book = bookstore.Add(b.Title ?? "", b.Author ?? "", b.Year);
        return Results.Created($"/api/books/{book!["id"]}", book);
    }
    catch (SchemeError e)
    {
        // Scheme 中的断言违例（如标题为空）作为 400 返回，消息由 Scheme 打印器给出
        return Results.BadRequest(new { error = e.Message });
    }
});

app.MapGet("/api/stats", () => Results.Json(bookstore.Stats()));

app.Run();

internal record NewBook(string? Title, string? Author, int? Year);

/// <summary>对 Scheme 库 (bookstore) 的包装：取得其导出的过程，调用并把结果转换为可序列化为 JSON 的 C# 值。</summary>
internal sealed class Bookstore
{
    // 交互环境与展开器不是线程安全的：对 Scheme 的调用串行进行
    private readonly object _gate = new();
    private readonly Procedure _allBooks, _findBooks, _bookById, _addBook, _stats;

    public Bookstore(string database)
    {
        // 两种取得过程的方式：Procedure，或强类型委托（参数与返回值按 CLR 互操作规则转换）
        var openStore = SchemeRuntime.GetFunction<Action<string>>("(bookstore)", "open-store");
        var initStore = SchemeRuntime.GetFunction<Action>("(bookstore)", "init-store!");
        _allBooks = SchemeRuntime.GetProcedure("(bookstore)", "all-books");
        _findBooks = SchemeRuntime.GetProcedure("(bookstore)", "find-books");
        _bookById = SchemeRuntime.GetProcedure("(bookstore)", "book-by-id");
        _addBook = SchemeRuntime.GetProcedure("(bookstore)", "add-book!");
        _stats = SchemeRuntime.GetProcedure("(bookstore)", "stats");
        lock (_gate)
        {
            openStore(database);
            initStore();
        }
    }

    private object? Call(Procedure p, params object?[] args)
    {
        lock (_gate) return SchemeJson.ToClr(SchemeRuntime.Call(p, args!));
    }

    public object? Books(string? q) => string.IsNullOrWhiteSpace(q) ? Call(_allBooks) : Call(_findBooks, q);

    public Dictionary<string, object?>? Book(long id) => Call(_bookById, id) as Dictionary<string, object?>;

    public Dictionary<string, object?>? Add(string title, string author, int? year) =>
      Call(_addBook, title, author, year.HasValue ? year.Value : false) as Dictionary<string, object?>;

    public object? Stats() => Call(_stats);

    public const string HomePage = """
    <!doctype html>
    <html><head><meta charset="utf-8"><title>IronScheme bookstore</title>
    <style>body{font-family:system-ui,sans-serif;max-width:44rem;margin:2rem auto;padding:0 1rem}td,th{padding:.2rem .6rem;text-align:left}</style>
    </head><body>
    <h1>IronScheme bookstore</h1>
    <p>HTTP routes are C# (ASP.NET Core). The data access and the statistics are Scheme
    (<code>scheme/bookstore.sls</code>), which queries SQLite through <code>Microsoft.Data.Sqlite</code>.</p>
    <input id="q" placeholder="search title or author" oninput="load()"> <span id="stats"></span>
    <table><thead><tr><th>Year</th><th>Title</th><th>Author</th></tr></thead><tbody id="books"></tbody></table>
    <script>
    async function load() {
      const q = document.getElementById('q').value;
      const books = await (await fetch('/api/books' + (q ? '?q=' + encodeURIComponent(q) : ''))).json();
      document.getElementById('books').innerHTML = books.map(b =>
        `<tr><td>${b.year ?? ''}</td><td>${b.title}</td><td>${b.author}</td></tr>`).join('');
      const s = await (await fetch('/api/stats')).json();
      document.getElementById('stats').textContent = `${s.count} books, ${s.earliest}–${s.latest}`;
    }
    load();
    </script></body></html>
    """;
}

/// <summary>
/// Scheme 值 → 可序列化为 JSON 的 C# 值：关联表 ((符号 . 值) …) → 字典；其他表与向量 → 列表；
/// 符号 → 字符串；#f → null（Scheme 侧用 #f 表示 SQL 的 NULL）；空表 → 空列表。
/// </summary>
internal static class SchemeJson
{
    public static object? ToClr(object? v) => v switch
    {
        null => new List<object?>(),
        bool b => b ? true : null,
        Cons c when IsAlist(c) => c.ToDictionary(),
        Cons c => c.Select(ToClr).ToList(),
        object[] vec => vec.Select(ToClr).ToList(),
        Symbol s => s.Name,
        System.Text.StringBuilder sb => sb.ToString(),
        int or long or double or string => v,
        _ => v.ToString(),
    };

    private static bool IsAlist(Cons c) => c.All(x => x is Cons p && p.car is Symbol);

    private static Dictionary<string, object?> ToDictionary(this Cons c) =>
      c.Cast<Cons>().ToDictionary(p => ((Symbol)p.car).Name, p => ToClr(p.cdr));
}

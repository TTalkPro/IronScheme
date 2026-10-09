using NUnit.Framework;
using IronScheme.Host;

namespace IronScheme.Core.Tests
{
  /// <summary>REPL 行编辑器的输入扫描（iron-038，designs/07-tooling-and-embedding.md §4）。交互部分需要终端，见 iron-038 结论中的手工验证。</summary>
  public class LineEditorTests
  {
    [TestCase("", true)]
    [TestCase("(+ 1 2)", true)]
    [TestCase("(define (f x)", false)]
    [TestCase("(define (f x)\n  (* x x))", true)]
    [TestCase("(display \"(\")", true)]
    [TestCase("(display \"abc", false)]
    [TestCase("(list #\\( #\\))", true)]
    [TestCase("(+ 1 ; ignore )\n 2)", true)]
    [TestCase("#| (( |# (+ 1 2)", true)]
    [TestCase("#| unfinished", false)]
    [TestCase("[let ((x 1)) x]", true)]
    public void IsComplete(string input, bool complete) =>
      Assert.That(LineEditor.IsComplete(input), Is.EqualTo(complete));

    [Test]
    public void CompletesSymbols()
    {
      var (start, library) = LineEditor.CompletionStart("(list-t");
      Assert.That((start, library), Is.EqualTo((1, false)));
      (start, library) = LineEditor.CompletionStart("(map car");
      Assert.That((start, library), Is.EqualTo((5, false)));
    }

    [Test]
    public void CompletesLibraryNamesInImport()
    {
      string s = "(import (rnrs) (srfi :1";
      var (start, library) = LineEditor.CompletionStart(s);
      Assert.That(library, Is.True);
      Assert.That(s.Substring(start), Is.EqualTo("(srfi :1"));
      // (only (lib ...) ...)：库名在修饰形式里
      s = "(import (only (rnrs b";
      (start, library) = LineEditor.CompletionStart(s);
      Assert.That(library, Is.True);
      Assert.That(s.Substring(start), Is.EqualTo("(rnrs b"));
      // 修饰形式本身的名字按符号补全
      (start, library) = LineEditor.CompletionStart("(import (on");
      Assert.That(library, Is.True);
    }

    [TestCase("(list-tail ", "list-tail")]
    [TestCase("(list-tail '(1 2) ", "list-tail")]
    [TestCase("(map (lambda (x) ", "lambda")]
    [TestCase("(list-ta", null)]
    [TestCase("(display \"(foo ", null)]
    [TestCase("x", null)]
    public void EnclosingHead(string input, string head) =>
      Assert.That(LineEditor.EnclosingHead(input), Is.EqualTo(head));
  }
}

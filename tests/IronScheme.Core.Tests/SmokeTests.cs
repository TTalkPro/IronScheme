using IronScheme.Core;
using NUnit.Framework;

namespace IronScheme.Core.Tests;

public class SmokeTests
{
    [Test]
    public void CoreAssemblyLoads()
    {
        Assert.That(CoreInfo.Version, Is.Not.Empty);
    }

    [Test]
    public void CoreDoesNotReferenceLegacyAssemblies()
    {
        var refs = typeof(CoreInfo).Assembly.GetReferencedAssemblies();
        foreach (var r in refs)
        {
            Assert.That(r.Name, Is.Not.EqualTo("IronScheme.Scripting"));
            Assert.That(r.Name, Is.Not.EqualTo("IronScheme"));
            Assert.That(r.Name, Is.Not.EqualTo("IronScheme.Closures"));
        }
    }
}

using BeagleCore.Net;
using Xunit;

namespace BeagleCore.Net.Tests;

public class FleetEndpointTests
{
    [Fact]
    public void BuildsPtyUriForAgent()
    {
        var ep = new FleetEndpoint("cockpit-1.tail21cbc4.ts.net");
        Assert.Equal("ws://cockpit-1.tail21cbc4.ts.net/pty/claude-1", ep.PtyUri("claude-1").ToString());
    }

    [Fact]
    public void UsesWssWhenTls()
    {
        var ep = new FleetEndpoint("host", tls: true);
        Assert.Equal("wss://host/pty/grok", ep.PtyUri("grok").ToString());
    }

    [Fact]
    public void RejectsUnknownAgent()
    {
        var ep = new FleetEndpoint("host");
        Assert.Throws<ArgumentException>(() => ep.PtyUri("nope"));
    }

    [Fact]
    public void RejectsEmptyHost()
    {
        Assert.Throws<ArgumentException>(() => new FleetEndpoint(""));
    }

    [Fact]
    public void ListsTheTenFleetAgents()
    {
        Assert.Equal(10, FleetEndpoint.Agents.Count);
        Assert.Contains("claude-1", FleetEndpoint.Agents);
        Assert.Contains("grok", FleetEndpoint.Agents);
    }
}

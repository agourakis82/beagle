using BeagleCore.Net;
using Xunit;

namespace BeagleCore.Net.Tests;

public class PtyProtocolTests
{
    [Theory]
    [InlineData(120, 40, "{\"resize\":[120,40]}")]
    [InlineData(80, 24, "{\"resize\":[80,24]}")]
    [InlineData(1, 1, "{\"resize\":[1,1]}")]
    public void ResizeFrameIsCanonicalJson(int cols, int rows, string expected)
    {
        Assert.Equal(expected, PtyClient.ResizeFrame(cols, rows));
    }
}

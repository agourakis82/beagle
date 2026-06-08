namespace BeagleCore.Net;

/// <summary>
/// Resolves the cockpit cluster contract for the Windows client: the fleet agent list and the
/// <c>/pty/&lt;agent&gt;</c> WebSocket URI. Mirrors the Apple <c>FleetEndpoint</c> and the agent list
/// in <c>cockpit/web/web.js</c>. Pure + unit-testable (no I/O).
/// </summary>
public sealed class FleetEndpoint
{
    /// <summary>The fleet agents, identical across all cockpit clients (Apple/Web/Windows).</summary>
    public static readonly IReadOnlyList<string> Agents = new[]
    {
        "claude-1", "claude-2", "claude-3",
        "codex-1", "codex-2", "codex-3",
        "minimax", "kimi", "cursor", "grok",
    };

    /// <summary>Default in-tailnet cockpit host.</summary>
    public const string DefaultHost = "cockpit-1.tail21cbc4.ts.net";

    private readonly string _host;
    private readonly bool _tls;

    /// <param name="host">Cockpit host (no scheme), e.g. <c>cockpit-1.tail21cbc4.ts.net</c>.</param>
    /// <param name="tls">Use <c>wss</c> when true, else <c>ws</c>.</param>
    public FleetEndpoint(string host = DefaultHost, bool tls = false)
    {
        if (string.IsNullOrWhiteSpace(host))
            throw new ArgumentException("host must be non-empty", nameof(host));
        _host = host;
        _tls = tls;
    }

    /// <summary>Builds the <c>/pty/&lt;agent&gt;</c> WebSocket URI for a known agent.</summary>
    /// <exception cref="ArgumentException">If <paramref name="agent"/> is not in <see cref="Agents"/>.</exception>
    public Uri PtyUri(string agent)
    {
        if (!Agents.Contains(agent))
            throw new ArgumentException($"unknown agent: {agent}", nameof(agent));
        var scheme = _tls ? "wss" : "ws";
        return new Uri($"{scheme}://{_host}/pty/{agent}");
    }
}

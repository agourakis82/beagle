using System.Net.WebSockets;
using System.Text;

namespace BeagleCore.Net;

/// <summary>
/// Client for the cockpit P0 <c>/pty/&lt;agent&gt;</c> gateway. Protocol (shared with Apple/Web):
/// <list type="bullet">
///   <item>binary frames (both directions) = raw PTY bytes;</item>
///   <item>client→server text frame <c>{"resize":[cols,rows]}</c> = terminal resize.</item>
/// </list>
/// Persistence is server-side (tmux): closing the socket detaches; the session survives. This type is
/// platform-agnostic (no Windows API) so it builds + tests anywhere the .NET 9 SDK runs.
/// </summary>
public sealed class PtyClient : IAsyncDisposable
{
    private readonly ClientWebSocket _ws = new();
    private CancellationTokenSource? _rxCts;
    private Task? _rxLoop;

    /// <summary>Raised with each PTY byte chunk received from the server (on the receive-loop thread).</summary>
    public event Action<ReadOnlyMemory<byte>>? OnData;

    /// <summary>Raised once when the receive loop ends (close or error). Argument is the close reason / error message.</summary>
    public event Action<string>? OnClosed;

    /// <summary>The canonical resize control frame body. Pure — unit-testable without a socket.</summary>
    public static string ResizeFrame(int cols, int rows) => $"{{\"resize\":[{cols},{rows}]}}";

    /// <summary>Connect to <paramref name="uri"/> and start the receive loop.</summary>
    public async Task ConnectAsync(Uri uri, CancellationToken ct = default)
    {
        await _ws.ConnectAsync(uri, ct).ConfigureAwait(false);
        _rxCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        _rxLoop = Task.Run(() => ReceiveLoopAsync(_rxCts.Token));
    }

    /// <summary>Send keystrokes (raw bytes) to the PTY as a binary frame.</summary>
    public ValueTask SendKeysAsync(ReadOnlyMemory<byte> data, CancellationToken ct = default) =>
        _ws.SendAsync(data, WebSocketMessageType.Binary, endOfMessage: true, ct);

    /// <summary>Send a terminal resize as a text control frame.</summary>
    public ValueTask ResizeAsync(int cols, int rows, CancellationToken ct = default)
    {
        var bytes = Encoding.UTF8.GetBytes(ResizeFrame(cols, rows));
        return _ws.SendAsync(bytes.AsMemory(), WebSocketMessageType.Text, endOfMessage: true, ct);
    }

    private async Task ReceiveLoopAsync(CancellationToken ct)
    {
        var buffer = new byte[16 * 1024];
        var reason = "closed";
        try
        {
            while (_ws.State == WebSocketState.Open && !ct.IsCancellationRequested)
            {
                var result = await _ws.ReceiveAsync(buffer, ct).ConfigureAwait(false);
                if (result.MessageType == WebSocketMessageType.Close)
                {
                    // ValueWebSocketReceiveResult has no CloseStatusDescription — read it off the socket.
                    reason = _ws.CloseStatusDescription ?? "close";
                    break;
                }
                // PTY data arrives as binary; deliver exactly the bytes received (may be a partial
                // message — terminal emulators tolerate chunk boundaries via Feed()).
                if (result.Count > 0)
                    OnData?.Invoke(new ReadOnlyMemory<byte>(buffer, 0, result.Count).ToArray());
            }
        }
        catch (OperationCanceledException) { reason = "cancelled"; }
        catch (Exception ex) { reason = ex.Message; }
        finally { OnClosed?.Invoke(reason); }
    }

    /// <summary>Close the socket (server detaches; the tmux session survives) and stop the loop.</summary>
    public async ValueTask DisposeAsync()
    {
        try { _rxCts?.Cancel(); } catch { /* ignore */ }
        try
        {
            if (_ws.State == WebSocketState.Open)
                await _ws.CloseAsync(WebSocketCloseStatus.NormalClosure, "detach", CancellationToken.None)
                    .ConfigureAwait(false);
        }
        catch { /* best-effort */ }
        try { if (_rxLoop is not null) await _rxLoop.ConfigureAwait(false); } catch { /* ignore */ }
        _rxCts?.Dispose();
        _ws.Dispose();
    }
}

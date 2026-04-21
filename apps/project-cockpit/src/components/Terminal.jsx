/**
 * Terminal — xterm.js wrapped in SolidJS.
 *
 * WebSocket bridge to the cockpit's /ws/terminal endpoint.
 * Connects to tmux session on the workspace pod.
 *
 * Props:
 *   slug: project slug
 *   expanded: boolean signal for full-height mode
 */
import { onMount, onCleanup, createSignal } from "solid-js";

export default function Terminal(props) {
  let containerRef;
  let term = null;
  let fitAddon = null;
  let ws = null;

  const [connected, setConnected] = createSignal(false);
  const [error, setError] = createSignal(null);

  onMount(async () => {
    // Dynamic imports to avoid SSR issues and reduce initial bundle
    const { Terminal: XTerm } = await import("xterm");
    const { FitAddon } = await import("xterm-addon-fit");
    await import("xterm/css/xterm.css");

    term = new XTerm({
      fontFamily: "var(--font-data, 'JetBrains Mono'), monospace",
      fontSize: 13,
      lineHeight: 1.35,
      cursorBlink: true,
      cursorStyle: "bar",
      theme: {
        background: "#0a1628",      // --surface-1
        foreground: "#eef5ff",       // --text-primary (approx)
        cursor: "#51d6bd",           // --truth-observed
        selectionBackground: "rgba(81, 214, 189, 0.2)",
        black: "#0a1628",
        red: "#ef4444",
        green: "#51d6bd",
        yellow: "#f4c15e",
        blue: "#77b8ff",
        magenta: "#c084fc",
        cyan: "#51d6bd",
        white: "#eef5ff",
        brightBlack: "#162a4a",
        brightRed: "#f87171",
        brightGreen: "#6ee7b7",
        brightYellow: "#fbbf24",
        brightBlue: "#93c5fd",
        brightMagenta: "#d8b4fe",
        brightCyan: "#67e8f9",
        brightWhite: "#ffffff",
      },
    });

    fitAddon = new FitAddon();
    term.loadAddon(fitAddon);
    term.open(containerRef);

    // Fit after a tick (container must have dimensions)
    requestAnimationFrame(() => {
      try { fitAddon.fit(); } catch (e) { /* ignore initial fit error */ }
    });

    // Connect WebSocket
    connectWs();

    // Resize observer
    const ro = new ResizeObserver(() => {
      try { fitAddon.fit(); } catch (e) { /* ignore */ }
      // Send resize to server if connected
      if (ws && ws.readyState === WebSocket.OPEN && term) {
        ws.send(JSON.stringify({
          type: "resize",
          cols: term.cols,
          rows: term.rows,
        }));
      }
    });
    ro.observe(containerRef);

    onCleanup(() => {
      ro.disconnect();
      if (ws) ws.close();
      if (term) term.dispose();
    });
  });

  function connectWs() {
    const protocol = location.protocol === "https:" ? "wss:" : "ws:";
    const sessionId = localStorage.getItem("project-cockpit-client-session-id") || crypto.randomUUID();
    localStorage.setItem("project-cockpit-client-session-id", sessionId);

    const url = `${protocol}//${location.host}/ws/terminal?project=${props.slug}&sessionId=${sessionId}`;

    try {
      ws = new WebSocket(url);
    } catch (e) {
      setError(`WebSocket error: ${e.message}`);
      return;
    }

    ws.onopen = () => {
      setConnected(true);
      setError(null);
      term.writeln("\x1b[38;2;81;214;189m● connected to workspace\x1b[0m");
      // Send initial size
      if (term) {
        ws.send(JSON.stringify({ type: "resize", cols: term.cols, rows: term.rows }));
      }
    };

    ws.onmessage = (event) => {
      try {
        const msg = JSON.parse(event.data);
        if (msg.type === "data" && msg.data) {
          term.write(msg.data);
        } else if (msg.type === "ready") {
          term.writeln("\x1b[38;2;81;214;189m● terminal ready\x1b[0m");
        } else if (msg.type === "exit") {
          term.writeln(`\x1b[38;2;159;178;205m○ session exited (code ${msg.code || 0})\x1b[0m`);
          setConnected(false);
        }
      } catch {
        // Raw data (non-JSON)
        term.write(event.data);
      }
    };

    ws.onclose = () => {
      setConnected(false);
      term.writeln("\x1b[38;2;159;178;205m○ disconnected\x1b[0m");
    };

    ws.onerror = () => {
      setError("WebSocket connection failed");
      setConnected(false);
    };

    // Forward terminal input to server
    term.onData((data) => {
      if (ws && ws.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify({ type: "input", data }));
      }
    });
  }

  return (
    <div style={{
      position: "relative",
      width: "100%",
      height: props.expanded ? "400px" : "200px",
      "min-height": "120px",
      transition: "height var(--duration-slow) var(--ease-out)",
    }}>
      {/* Connection status indicator */}
      <div style={{
        position: "absolute",
        top: "var(--space-2)",
        right: "var(--space-2)",
        "z-index": 2,
        display: "flex",
        "align-items": "center",
        gap: "var(--space-1)",
        "font-family": "var(--font-data)",
        "font-size": "var(--text-xs)",
        color: connected() ? "var(--truth-observed)" : "var(--text-tertiary)",
        opacity: 0.6,
      }}>
        <span>{connected() ? "●" : "○"}</span>
        <span>{connected() ? "live" : error() || "disconnected"}</span>
      </div>

      {/* xterm.js container */}
      <div
        ref={containerRef}
        style={{
          width: "100%",
          height: "100%",
          "border-radius": "var(--radius-sm)",
          overflow: "hidden",
        }}
      />
    </div>
  );
}

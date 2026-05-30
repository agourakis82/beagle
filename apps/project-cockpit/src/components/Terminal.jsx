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
    const probe = document.createElement("canvas").getContext("2d");
    if (!probe || typeof probe.createLinearGradient !== "function") {
      setError("terminal runtime unavailable: canvas 2D is incomplete");
      return;
    }

    // Dynamic imports to avoid SSR issues and reduce initial bundle
    let XTerm;
    let FitAddon;
    try {
      ({ Terminal: XTerm } = await import("xterm"));
      ({ FitAddon } = await import("xterm-addon-fit"));
      await import("xterm/css/xterm.css");
    } catch (e) {
      setError(`terminal runtime unavailable: ${e.message}`);
      return;
    }

    term = new XTerm({
      fontFamily: "var(--font-data, 'JetBrains Mono'), monospace",
      fontSize: 13,
      lineHeight: 1.35,
      cursorBlink: true,
      cursorStyle: "bar",
      theme: {
        background: "#000000",
        foreground: "#f2f2f2",
        cursor: "#ffffff",
        selectionBackground: "rgba(255, 255, 255, 0.22)",
        black: "#000000",
        red: "#ff7b72",
        green: "#7ee787",
        yellow: "#d6b85a",
        blue: "#79c0ff",
        magenta: "#d2a8ff",
        cyan: "#8bd3dd",
        white: "#f2f2f2",
        brightBlack: "#8b949e",
        brightRed: "#ffa198",
        brightGreen: "#9be9a8",
        brightYellow: "#e3c76f",
        brightBlue: "#a5d6ff",
        brightMagenta: "#e2c5ff",
        brightCyan: "#b7e7ee",
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
      height: props.height || (props.expanded ? "400px" : "200px"),
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
        gap: "6px",
        padding: "2px 6px",
        "border-radius": "6px",
        "font-family": "'SF Mono', ui-monospace, monospace",
        "font-size": "11px",
        background: "#000000",
        color: connected() ? "#7ee787" : "#d8d8d8",
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
          overflow: "hidden",
        }}
      />
    </div>
  );
}

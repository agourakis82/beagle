import { Show, createSignal, onCleanup, onMount } from "solid-js";

export default function AgentTerminal(props) {
  let containerRef;
  let term = null;
  let fitAddon = null;
  let ws = null;

  const [connected, setConnected] = createSignal(false);
  const [error, setError] = createSignal("");

  onMount(async () => {
    const probe = document.createElement("canvas").getContext("2d");
    if (!probe || typeof probe.createLinearGradient !== "function") {
      setError("terminal runtime unavailable");
      return;
    }

    let XTerm;
    let FitAddon;
    try {
      ({ Terminal: XTerm } = await import("xterm"));
      ({ FitAddon } = await import("xterm-addon-fit"));
      await import("xterm/css/xterm.css");
    } catch (event) {
      setError(`terminal runtime unavailable: ${event.message}`);
      return;
    }

    term = new XTerm({
      fontFamily: '"SF Mono", ui-monospace, monospace',
      fontSize: 12,
      lineHeight: 1.34,
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
    requestAnimationFrame(() => {
      try { fitAddon.fit(); } catch { /* initial layout can race */ }
    });

    connect();

    const resizeObserver = new ResizeObserver(() => {
      try { fitAddon.fit(); } catch { /* ignore fit race */ }
      if (ws?.readyState === WebSocket.OPEN && term) {
        ws.send(JSON.stringify({ type: "resize", cols: term.cols, rows: term.rows }));
      }
    });
    resizeObserver.observe(containerRef);

    onCleanup(() => {
      resizeObserver.disconnect();
      if (ws) ws.close();
      if (term) term.dispose();
    });
  });

  function connect() {
    const protocol = location.protocol === "https:" ? "wss:" : "ws:";
    const url = `${protocol}//${location.host}/ws/projects/${props.slug}/agent/${props.kind}`;

    try {
      ws = new WebSocket(url);
    } catch (event) {
      setError(`WebSocket error: ${event.message}`);
      return;
    }

    ws.onopen = () => {
      setConnected(true);
      setError("");
      term.writeln(`\x1b[38;2;170;205;191mattached to ${props.kind}\x1b[0m`);
      if (term) ws.send(JSON.stringify({ type: "resize", cols: term.cols, rows: term.rows }));
    };

    ws.onmessage = (event) => {
      try {
        const msg = JSON.parse(event.data);
        if (msg.type === "data" && msg.data) {
          term.write(msg.data);
          window.dispatchEvent(new CustomEvent("beagle-agent-terminal-output", {
            detail: { slug: props.slug, kind: props.kind, data: msg.data }
          }));
        } else if (msg.type === "stderr" && msg.data) {
          term.write(`\r\n\x1b[38;2;216;111;102m${msg.data}\x1b[0m`);
        } else if (msg.type === "ready") {
          term.writeln("\x1b[38;2;170;205;191magent bridge ready\x1b[0m");
        } else if (msg.type === "snapshot" && msg.data) {
          window.dispatchEvent(new CustomEvent("beagle-agent-terminal-snapshot", {
            detail: msg.data
          }));
        } else if (msg.type === "error") {
          setError(msg.data || "agent bridge error");
          term.writeln(`\r\n\x1b[38;2;216;111;102m${msg.data || "agent bridge error"}\x1b[0m`);
        } else if (msg.type === "exit") {
          setConnected(false);
          term.writeln(`\r\n\x1b[38;2;150;150;150magent session exited (${msg.code ?? 0})\x1b[0m`);
        }
      } catch {
        term.write(event.data);
      }
    };

    ws.onclose = () => {
      setConnected(false);
      term?.writeln("\r\n\x1b[38;2;150;150;150mdisconnected\x1b[0m");
    };

    ws.onerror = () => {
      setConnected(false);
      setError("WebSocket connection failed");
    };

    term.onData((data) => {
      if (ws?.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify({ type: "input", data }));
      }
    });
  }

  return (
    <div class="agent-terminal">
      <div class="agent-terminal-status">
        <span class={connected() ? "live" : ""}>{connected() ? "live" : "offline"}</span>
        <Show when={error()}>
          <small>{error()}</small>
        </Show>
      </div>
      <div ref={containerRef} class="agent-terminal-surface" />
    </div>
  );
}

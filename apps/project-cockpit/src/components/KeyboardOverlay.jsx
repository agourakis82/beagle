/**
 * KeyboardOverlay — ? shortcut cheat sheet.
 *
 * Shows all available keyboard shortcuts overlaid on the current view.
 * Contextual to the current page.
 */
import { createSignal, onMount, onCleanup, Show } from "solid-js";
import GlassPanel from "./GlassPanel";

const SHORTCUTS = [
  { key: "⌘K", desc: "Command palette", section: "global" },
  { key: "/", desc: "Command palette (alt)", section: "global" },
  { key: "?", desc: "Show shortcuts", section: "global" },
  { key: "g p", desc: "Go to projects", section: "navigation" },
  { key: "Esc", desc: "Close overlay / go back", section: "global" },
];

export default function KeyboardOverlay() {
  const [visible, setVisible] = createSignal(false);
  let pendingG = false;
  let gTimeout = null;

  function handleKey(e) {
    // ? to toggle overlay (when not in input)
    if (e.key === "?" && !visible() &&
        document.activeElement?.tagName !== "INPUT" &&
        document.activeElement?.tagName !== "TEXTAREA") {
      e.preventDefault();
      setVisible(true);
      return;
    }

    if (e.key === "Escape" && visible()) {
      e.preventDefault();
      setVisible(false);
      return;
    }

    // g-prefix shortcuts
    if (e.key === "g" && !pendingG &&
        document.activeElement?.tagName !== "INPUT" &&
        document.activeElement?.tagName !== "TEXTAREA") {
      pendingG = true;
      gTimeout = setTimeout(() => { pendingG = false; }, 800);
      return;
    }

    if (pendingG) {
      pendingG = false;
      clearTimeout(gTimeout);
      if (e.key === "p") {
        e.preventDefault();
        window.location.hash = "";
        window.location.pathname = "/projects";
      }
    }
  }

  onMount(() => {
    document.addEventListener("keydown", handleKey);
    onCleanup(() => {
      document.removeEventListener("keydown", handleKey);
      clearTimeout(gTimeout);
    });
  });

  return (
    <Show when={visible()}>
      <div
        style={{
          position: "fixed",
          inset: 0,
          "z-index": 200,
          display: "flex",
          "align-items": "center",
          "justify-content": "center",
          background: "rgba(5, 10, 18, 0.7)",
          "backdrop-filter": "blur(8px)",
        }}
        onClick={() => setVisible(false)}
      >
        <GlassPanel elevated style={{ "max-width": "400px", width: "90vw" }}>
          <h3 style={{
            "font-family": "var(--font-display)",
            "font-size": "var(--text-lg)",
            color: "var(--text-primary)",
            "margin-bottom": "var(--space-4)",
          }}>
            Keyboard Shortcuts
          </h3>

          <div style={{ display: "flex", "flex-direction": "column", gap: "var(--space-2)" }}>
            {SHORTCUTS.map(s => (
              <div style={{
                display: "flex",
                "justify-content": "space-between",
                "align-items": "center",
                padding: "var(--space-1) 0",
              }}>
                <span style={{
                  "font-family": "var(--font-data)",
                  "font-size": "var(--text-sm)",
                  color: "var(--truth-observed)",
                  padding: "1px var(--space-2)",
                  background: "rgba(81, 214, 189, 0.08)",
                  "border-radius": "3px",
                  "min-width": "48px",
                  "text-align": "center",
                }}>
                  {s.key}
                </span>
                <span style={{
                  "font-size": "var(--text-sm)",
                  color: "var(--text-secondary)",
                }}>
                  {s.desc}
                </span>
              </div>
            ))}
          </div>

          <div style={{
            "margin-top": "var(--space-4)",
            "font-size": "var(--text-xs)",
            color: "var(--text-tertiary)",
            "text-align": "center",
          }}>
            Press Esc or click to close
          </div>
        </GlassPanel>
      </div>
    </Show>
  );
}

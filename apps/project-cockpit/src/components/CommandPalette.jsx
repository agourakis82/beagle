/**
 * CommandPalette — ⌘K / Ctrl+K
 *
 * Not a search box — a cockpit CLI.
 * Fuzzy matching + structured commands + context-aware suggestions.
 * Bloomberg function codes meet Linear's command palette.
 *
 * Opens: ⌘K or Ctrl+K or /
 * Navigate: ↑↓
 * Execute: Enter
 * Close: Escape
 */
import { createSignal, createEffect, onMount, onCleanup, For, Show } from "solid-js";
import { useNavigate } from "@solidjs/router";
import { searchCommands, registerCommands } from "../stores/commands";

export default function CommandPalette() {
  const [open, setOpen] = createSignal(false);
  const [query, setQuery] = createSignal("");
  const [selectedIdx, setSelectedIdx] = createSignal(0);
  const [results, setResults] = createSignal([]);
  const navigate = useNavigate();
  let inputRef;

  // Register core navigation commands
  onMount(() => {
    registerCommands([
      { id: "nav:projects", label: "Go to projects", description: "Open the command bridge", category: "navigation", shortcut: "g p", action: () => navigate("/projects") },
      { id: "nav:project-os", label: "Project OS", description: "Open multi-project operating surface", category: "navigation", action: () => navigate("/projects/os") },
      { id: "nav:cluster-ops", label: "Cluster Ops", description: "Open Darwin cluster control lane", category: "navigation", action: () => navigate("/projects/cluster") },
      { id: "nav:sounio", label: "Project sounio", description: "Open Sounio control room", category: "navigation", action: () => navigate("/projects/sounio") },
      { id: "nav:sounio:control", label: "Sounio control", description: "Open Sounio control tower", category: "navigation", action: () => navigate("/projects/sounio/control") },
      { id: "nav:sounio:viewer", label: "Sounio viewer", description: "Open scientific viewport", category: "navigation", action: () => navigate("/projects/sounio/viewer") },
      { id: "nav:hsn", label: "Project HSN", description: "Open Hyperbolic Semantic Networks", category: "navigation", action: () => navigate("/projects/hyperbolic-semantic-networks") },
      { id: "nav:beagle", label: "Project beagle", description: "Open Beagle control room", category: "navigation", action: () => navigate("/projects/beagle") },
      { id: "nav:darwin-mfc", label: "Project Darwin-MFC", description: "Open Darwin-MFC workbench target", category: "navigation", action: () => navigate("/projects/darwin-mfc") },
      { id: "nav:darwin-mfc:workbench", label: "Darwin-MFC workbench", description: "Open the shared agent studio", category: "navigation", action: () => navigate("/workbench/darwin-mfc") },
      { id: "nav:darwin", label: "Project darwin-pbpk", description: "Open Darwin PBPK control room", category: "navigation", action: () => navigate("/projects/darwin-pbpk") },
      { id: "info:cluster", label: "Cluster summary", description: "Show cluster truth and node health", category: "info", action: () => navigate("/projects/cluster") },
      { id: "info:inference", label: "Inference runtime", description: "Show SGLang + Dynamo state", category: "info", action: () => navigate("/projects/sounio") },
      { id: "info:research", label: "Research latest", description: "Show latest ABIDE campaign", category: "info", action: () => navigate("/projects/sounio") },
      // Public vision surfaces
      { id: "vision:portal", label: "Public portal", description: "Open public surfaces", category: "vision", action: () => navigate("/public") },
      { id: "vision:control-room", label: "Vision control room", description: "Spatial mission control", category: "vision", action: () => navigate("/public/vision/control-room") },
      { id: "vision:apple-brief", label: "Apple brief", description: "Platform briefing", category: "vision", action: () => navigate("/public/vision/apple-brief") },
      { id: "vision:apple-launchpad", label: "Apple launchpad", description: "App launcher", category: "vision", action: () => navigate("/public/vision/apple-launchpad") },
      { id: "vision:operator-board", label: "Operator board", description: "Operator dashboard", category: "vision", action: () => navigate("/public/vision/operator-board") },
      { id: "vision:runtime-matrix", label: "Runtime matrix", description: "Platform capabilities", category: "vision", action: () => navigate("/public/vision/runtime-matrix") },
      { id: "vision:route-atlas", label: "Route atlas", description: "Navigation atlas", category: "vision", action: () => navigate("/public/vision/route-atlas") },
      { id: "vision:mission-timeline", label: "Mission timeline", description: "Operational phases", category: "vision", action: () => navigate("/public/vision/mission-timeline") },
      { id: "vision:sovereign-bridge", label: "Sovereign bridge", description: "Cross-platform continuity", category: "vision", action: () => navigate("/public/vision/sovereign-bridge") },
      { id: "vision:handoff", label: "Handoff", description: "iPhone ↔ VisionPro handoff", category: "vision", action: () => navigate("/public/vision/handoff") },
    ]);
  });

  // Update results when query changes
  createEffect(() => {
    const q = query();
    const r = searchCommands(q);
    setResults(r);
    setSelectedIdx(0);
  });

  // Global keyboard handler
  function handleGlobalKey(e) {
    // ⌘K or Ctrl+K to toggle
    if ((e.metaKey || e.ctrlKey) && e.key === "k") {
      e.preventDefault();
      setOpen(!open());
      if (!open()) {
        setQuery("");
      }
      return;
    }

    // / to open (when not in input)
    if (e.key === "/" && !open() && document.activeElement?.tagName !== "INPUT" && document.activeElement?.tagName !== "TEXTAREA") {
      e.preventDefault();
      setOpen(true);
      setQuery("");
      return;
    }

    // Escape to close
    if (e.key === "Escape" && open()) {
      e.preventDefault();
      setOpen(false);
      setQuery("");
    }
  }

  onMount(() => {
    document.addEventListener("keydown", handleGlobalKey);
    onCleanup(() => document.removeEventListener("keydown", handleGlobalKey));
  });

  // Focus input when opened
  createEffect(() => {
    if (open() && inputRef) {
      requestAnimationFrame(() => inputRef.focus());
    }
  });

  function handleInputKey(e) {
    const r = results();
    if (e.key === "ArrowDown") {
      e.preventDefault();
      setSelectedIdx(Math.min(selectedIdx() + 1, r.length - 1));
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      setSelectedIdx(Math.max(selectedIdx() - 1, 0));
    } else if (e.key === "Enter" && r.length > 0) {
      e.preventDefault();
      const selected = r[selectedIdx()];
      if (selected?.cmd?.action) {
        selected.cmd.action();
        setOpen(false);
        setQuery("");
      }
    }
  }

  return (
    <>
      {/* Trigger button (visible in header) */}
      <button
        onClick={() => { setOpen(true); setQuery(""); }}
        style={{
          display: "flex",
          "align-items": "center",
          gap: "var(--space-2)",
          padding: "var(--space-2) var(--space-4)",
          background: "rgba(255, 255, 255, 0.04)",
          border: "1px solid var(--glass-border)",
          "border-radius": "var(--radius-md)",
          color: "var(--text-tertiary)",
          "font-family": "var(--font-data)",
          "font-size": "var(--text-sm)",
          cursor: "pointer",
          transition: `all var(--duration-fast) var(--ease-out)`,
          "min-width": "200px",
        }}
      >
        <span style={{ opacity: 0.5 }}>⌘K</span>
        <span>Search, navigate, command...</span>
      </button>

      {/* Modal overlay */}
      <Show when={open()}>
        <div
          role="dialog"
          aria-modal="true"
          aria-label="Command palette"
          style={{
            position: "fixed",
            inset: 0,
            "z-index": 100,
            display: "flex",
            "align-items": "flex-start",
            "justify-content": "center",
            "padding-top": "min(20vh, 160px)",
            background: "rgba(5, 10, 18, 0.6)",
            "backdrop-filter": "blur(8px)",
          }}
          onClick={(e) => { if (e.target === e.currentTarget) { setOpen(false); setQuery(""); } }}
        >
          <div
            class="glass glass--elevated"
            role="combobox"
            aria-expanded="true"
            aria-controls="cmdk-listbox"
            aria-haspopup="listbox"
            style={{
              width: "min(560px, 90vw)",
              "max-height": "min(480px, 70vh)",
              overflow: "hidden",
              display: "flex",
              "flex-direction": "column",
              padding: 0,
            }}
          >
            {/* Input */}
            <div style={{
              display: "flex",
              "align-items": "center",
              padding: "var(--space-4)",
              "border-bottom": "1px solid var(--glass-border)",
              gap: "var(--space-3)",
            }}>
              <span style={{
                color: "var(--text-tertiary)",
                "font-family": "var(--font-data)",
                "font-size": "var(--text-sm)",
              }}>
                ⌘K
              </span>
              <input
                ref={inputRef}
                type="text"
                value={query()}
                onInput={(e) => setQuery(e.target.value)}
                onKeyDown={handleInputKey}
                placeholder="Search, navigate, command..."
                aria-label="Command input"
                aria-autocomplete="list"
                aria-controls="cmdk-listbox"
                aria-activedescendant={`cmdk-option-${selectedIdx()}`}
                autocomplete="off"
                spellcheck={false}
                style={{
                  flex: 1,
                  "font-family": "var(--font-ui)",
                  "font-size": "var(--text-base)",
                  color: "var(--text-primary)",
                  background: "transparent",
                }}
              />
            </div>

            {/* Results */}
            <div
              id="cmdk-listbox"
              role="listbox"
              aria-label="Command results"
              style={{
                "overflow-y": "auto",
                flex: 1,
                padding: "var(--space-2)",
              }}
            >
              <For each={results()}>
                {(result, idx) => (
                  <button
                    id={`cmdk-option-${idx()}`}
                    role="option"
                    aria-selected={idx() === selectedIdx()}
                    onClick={() => {
                      result.cmd.action();
                      setOpen(false);
                      setQuery("");
                    }}
                    style={{
                      display: "flex",
                      "align-items": "center",
                      "justify-content": "space-between",
                      width: "100%",
                      padding: "var(--space-2) var(--space-3)",
                      "border-radius": "var(--radius-sm)",
                      background: idx() === selectedIdx() ? "rgba(81, 214, 189, 0.08)" : "transparent",
                      "text-align": "left",
                      transition: `background var(--duration-fast)`,
                    }}
                    onMouseEnter={() => setSelectedIdx(idx())}
                  >
                    <div>
                      <div style={{
                        "font-size": "var(--text-sm)",
                        color: idx() === selectedIdx() ? "var(--text-primary)" : "var(--text-secondary)",
                        "font-weight": "var(--weight-medium)",
                      }}>
                        {result.cmd.label}
                      </div>
                      <Show when={result.cmd.description}>
                        <div style={{
                          "font-size": "var(--text-xs)",
                          color: "var(--text-tertiary)",
                          "margin-top": "1px",
                        }}>
                          {result.cmd.description}
                        </div>
                      </Show>
                    </div>
                    <Show when={result.cmd.shortcut}>
                      <span style={{
                        "font-family": "var(--font-data)",
                        "font-size": "var(--text-xs)",
                        color: "var(--text-tertiary)",
                        padding: "1px var(--space-2)",
                        background: "rgba(255, 255, 255, 0.04)",
                        "border-radius": "3px",
                      }}>
                        {result.cmd.shortcut}
                      </span>
                    </Show>
                  </button>
                )}
              </For>

              <Show when={results().length === 0 && query()}>
                <div style={{
                  padding: "var(--space-6)",
                  "text-align": "center",
                  color: "var(--text-tertiary)",
                  "font-size": "var(--text-sm)",
                }}>
                  No commands match "{query()}"
                </div>
              </Show>
            </div>

            {/* Footer hints */}
            <div style={{
              display: "flex",
              gap: "var(--space-4)",
              padding: "var(--space-2) var(--space-4)",
              "border-top": "1px solid var(--glass-border)",
              "font-family": "var(--font-data)",
              "font-size": "var(--text-xs)",
              color: "var(--text-tertiary)",
            }}>
              <span>↑↓ navigate</span>
              <span>⏎ execute</span>
              <span>esc close</span>
            </div>
          </div>
        </div>
      </Show>
    </>
  );
}

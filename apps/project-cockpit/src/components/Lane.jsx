/**
 * Lane — Collapsible horizontal strip with truth indicator.
 *
 * Each lane represents one operational domain:
 * mission control, cluster truth, research ops, inference, publication.
 */
import { createSignal } from "solid-js";
import TruthBadge from "./TruthBadge";

export default function Lane(props) {
  const [expanded, setExpanded] = createSignal(props.defaultExpanded !== false);

  return (
    <div
      class="glass lane"
      data-truth={props.truth}
      style={{
        "margin-bottom": "var(--space-3)",
        padding: "0",
        overflow: "hidden",
        "border-width": "1px",
      }}
    >
      {/* Lane header — always visible */}
      <button
        onClick={() => setExpanded(!expanded())}
        style={{
          display: "flex",
          "align-items": "center",
          "justify-content": "space-between",
          width: "100%",
          padding: "var(--space-3) var(--space-4)",
          cursor: "pointer",
          "text-align": "left",
        }}
      >
        <div style={{ display: "flex", "align-items": "center", gap: "var(--space-3)" }}>
          <span
            style={{
              "font-family": "var(--font-ui)",
              "font-size": "var(--text-sm)",
              "font-weight": "var(--weight-semibold)",
              "letter-spacing": "0.06em",
              "text-transform": "uppercase",
              color: "var(--text-secondary)",
            }}
          >
            {props.title}
          </span>
          {props.truth && <TruthBadge mode={props.truth} />}
        </div>
        <span
          style={{
            "font-size": "var(--text-xs)",
            color: "var(--text-tertiary)",
            transition: `transform var(--duration-fast) var(--ease-out)`,
            transform: expanded() ? "rotate(0deg)" : "rotate(-90deg)",
          }}
        >
          ▾
        </span>
      </button>

      {/* Lane content — collapsible */}
      {expanded() && (
        <div
          class="lane-enter"
          style={{ padding: "0 var(--space-4) var(--space-4)" }}
        >
          {props.children}
        </div>
      )}
    </div>
  );
}

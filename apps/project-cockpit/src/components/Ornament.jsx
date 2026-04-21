/**
 * Ornament — visionOS-style floating glass panel at viewport edge.
 *
 * Floats over the 3D scene. Glass material with truth border.
 * Used in the Scientific Viewport for dataset, camera, and provenance panels.
 *
 * Props:
 *   position: "top-left" | "top-right" | "bottom-left" | "bottom-right" | "bottom-center"
 *   truth: truth mode for border styling
 *   title: optional header text
 *   compact: boolean — smaller padding
 */
import GlassPanel from "./GlassPanel";
import TruthBadge from "./TruthBadge";

const POSITION_STYLES = {
  "top-left": { top: "var(--space-4)", left: "var(--space-4)" },
  "top-right": { top: "var(--space-4)", right: "var(--space-4)" },
  "bottom-left": { bottom: "var(--space-4)", left: "var(--space-4)" },
  "bottom-right": { bottom: "var(--space-4)", right: "var(--space-4)" },
  "bottom-center": { bottom: "var(--space-4)", left: "50%", transform: "translateX(-50%)" },
};

export default function Ornament(props) {
  const pos = () => POSITION_STYLES[props.position] || POSITION_STYLES["top-left"];

  return (
    <div
      class="ornament"
      style={{
        position: "absolute",
        "z-index": 10,
        "max-width": props.width || "280px",
        "min-width": "160px",
        animation: "ornament-enter 0.4s var(--ease-out) forwards",
        opacity: 0,
        ...pos(),
      }}
    >
      <style>{`
        @keyframes ornament-enter {
          from { opacity: 0; transform: ${pos().transform || "translateY(8px)"}; }
          to { opacity: 1; transform: ${pos().transform || "translateY(0)"}; }
        }
      `}</style>

      <GlassPanel
        elevated
        truth={props.truth}
        padding={props.compact ? "var(--space-3)" : "var(--space-4)"}
      >
        {props.title && (
          <div style={{
            display: "flex",
            "align-items": "center",
            "justify-content": "space-between",
            "margin-bottom": "var(--space-2)",
          }}>
            <span style={{
              "font-family": "var(--font-ui)",
              "font-size": "var(--text-xs)",
              "font-weight": "var(--weight-semibold)",
              "text-transform": "uppercase",
              "letter-spacing": "0.08em",
              color: "var(--text-tertiary)",
            }}>
              {props.title}
            </span>
            {props.truth && <TruthBadge mode={props.truth} />}
          </div>
        )}
        {props.children}
      </GlassPanel>
    </div>
  );
}

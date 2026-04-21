/**
 * Skeleton — shimmer loading placeholder.
 *
 * Glass skeleton with subtle gradient shimmer.
 * Used while data is in flight. Better than "loading..." text.
 *
 * Props:
 *   width: string (default "100%")
 *   height: string (default "16px")
 *   lines: number — render multiple stacked lines
 *   variant: "text" | "block" | "inline"
 */
import { For } from "solid-js";

export default function Skeleton(props) {
  const width = () => props.width || "100%";
  const height = () => props.height || "14px";
  const lines = () => props.lines || 1;
  const variant = () => props.variant || "text";

  const base = {
    display: variant() === "inline" ? "inline-block" : "block",
    width: width(),
    height: height(),
    "border-radius": variant() === "block" ? "var(--radius-sm)" : "3px",
    background: "linear-gradient(90deg, rgba(255,255,255,0.02) 0%, rgba(255,255,255,0.06) 50%, rgba(255,255,255,0.02) 100%)",
    "background-size": "200% 100%",
    animation: "skeleton-shimmer 1.6s ease-in-out infinite",
    "vertical-align": "middle",
  };

  return (
    <>
      <style>{`
        @keyframes skeleton-shimmer {
          0%   { background-position: 200% 0; }
          100% { background-position: -200% 0; }
        }
      `}</style>
      {lines() === 1 ? (
        <div style={base} aria-busy="true" aria-label="Loading" />
      ) : (
        <div style={{ display: "flex", "flex-direction": "column", gap: "var(--space-2)" }}>
          <For each={Array.from({ length: lines() })}>
            {(_, idx) => (
              <div
                style={{
                  ...base,
                  // Vary widths for more natural appearance
                  width: idx() === lines() - 1 ? "60%" : width(),
                }}
                aria-busy="true"
              />
            )}
          </For>
        </div>
      )}
    </>
  );
}

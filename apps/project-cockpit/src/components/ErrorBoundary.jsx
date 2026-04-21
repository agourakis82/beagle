/**
 * ErrorBoundary — graceful API failure handling.
 *
 * Two purposes:
 * 1. Catch render errors and show truth-aware fallback
 * 2. Handle stale truth with retry affordance
 *
 * Uses SolidJS ErrorBoundary primitive under the hood.
 */
import { ErrorBoundary as SolidErrorBoundary } from "solid-js";
import GlassPanel from "./GlassPanel";

function DefaultFallback(err, reset) {
  return (
    <GlassPanel
      truth="stale"
      class="error-pulse"
      style={{
        margin: "var(--space-4)",
        "max-width": "520px",
      }}
    >
      <div style={{
        display: "flex",
        "align-items": "center",
        gap: "var(--space-2)",
        "margin-bottom": "var(--space-2)",
        color: "var(--state-error)",
      }}>
        <span style={{ "font-size": "var(--text-lg)" }}>⚠</span>
        <span style={{
          "font-family": "var(--font-ui)",
          "font-size": "var(--text-xs)",
          "font-weight": "var(--weight-semibold)",
          "text-transform": "uppercase",
          "letter-spacing": "0.08em",
        }}>
          Surface error
        </span>
      </div>
      <p style={{
        "font-family": "var(--font-data)",
        "font-size": "var(--text-sm)",
        color: "var(--text-secondary)",
        "margin-bottom": "var(--space-3)",
      }}>
        {err?.message || "An unexpected error prevented this surface from rendering."}
      </p>
      <button
        onClick={reset}
        style={{
          padding: "var(--space-2) var(--space-4)",
          background: "rgba(81, 214, 189, 0.12)",
          border: "1px solid rgba(81, 214, 189, 0.25)",
          "border-radius": "var(--radius-sm)",
          color: "var(--truth-observed)",
          "font-family": "var(--font-data)",
          "font-size": "var(--text-sm)",
          cursor: "pointer",
        }}
      >
        retry
      </button>
    </GlassPanel>
  );
}

export default function ErrorBoundary(props) {
  return (
    <SolidErrorBoundary fallback={props.fallback || DefaultFallback}>
      {props.children}
    </SolidErrorBoundary>
  );
}

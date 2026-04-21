/**
 * AudioControl — persistent mute/unmute button.
 *
 * Fixed position bottom-right. Shows soundscape state.
 * Muted by default — user opts in.
 */
import { audioEnabled, toggleAudio } from "../stores/audio";

export default function AudioControl() {
  return (
    <button
      onClick={toggleAudio}
      title={audioEnabled() ? "Mute soundscape" : "Enable soundscape"}
      style={{
        position: "fixed",
        bottom: "var(--space-4)",
        right: "var(--space-4)",
        "z-index": 50,
        display: "flex",
        "align-items": "center",
        gap: "var(--space-2)",
        padding: "var(--space-2) var(--space-3)",
        background: "var(--glass-bg)",
        "backdrop-filter": "blur(var(--glass-blur))",
        border: `1px solid ${audioEnabled() ? "rgba(81, 214, 189, 0.2)" : "var(--glass-border)"}`,
        "border-radius": "var(--radius-md)",
        color: audioEnabled() ? "var(--truth-observed)" : "var(--text-tertiary)",
        "font-family": "var(--font-data)",
        "font-size": "var(--text-xs)",
        cursor: "pointer",
        transition: "all var(--duration-fast) var(--ease-out)",
        opacity: 0.8,
      }}
    >
      <span style={{ "font-size": "var(--text-sm)" }}>
        {audioEnabled() ? "\uD83D\uDD0A" : "\uD83D\uDD07"}
      </span>
      <span>{audioEnabled() ? "ambient: on" : "ambient: off"}</span>
    </button>
  );
}

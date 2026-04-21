/**
 * PostureIndicator — always-on / warm / cold visual.
 *
 * always-on: teal pulsing glow
 * warm: gold steady
 * cold: slate dim
 */
const POSTURE_MAP = {
  "always-on": { icon: "\u25CF", class: "posture-on", label: "always-on" },
  "warm":      { icon: "\u25D0", class: "posture-warm", label: "warm" },
  "cold":      { icon: "\u25CB", class: "posture-cold", label: "cold" },
};

export default function PostureIndicator(props) {
  const posture = () => POSTURE_MAP[props.mode] || POSTURE_MAP.cold;

  return (
    <span
      class={`posture-indicator ${posture().class}`}
      title={posture().label}
      style={{
        display: "inline-flex",
        "align-items": "center",
        gap: "var(--space-2)",
        "font-family": "var(--font-data)",
        "font-size": props.size === "lg" ? "var(--text-lg)" : "var(--text-sm)",
      }}
    >
      <span aria-hidden="true" style={{ "font-size": "1.1em" }}>{posture().icon}</span>
      {props.showLabel !== false && (
        <span style={{ "letter-spacing": "0.03em" }}>{posture().label}</span>
      )}
    </span>
  );
}

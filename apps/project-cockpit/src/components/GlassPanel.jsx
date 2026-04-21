/**
 * GlassPanel — Glassmorphism container floating over the GPU canvas.
 * The fundamental surface primitive of Sovereign Dark.
 */
export default function GlassPanel(props) {
  const variant = () => {
    if (props.elevated) return "glass glass--elevated";
    if (props.subtle) return "glass glass--subtle";
    return "glass";
  };

  return (
    <div
      class={`${variant()} ${props.class || ""}`}
      style={{
        padding: props.padding || "var(--space-5)",
        ...(props.style || {}),
      }}
      data-truth={props.truth}
    >
      {props.children}
    </div>
  );
}

/**
 * TruthBadge — observed/remembered/declared chip.
 *
 * The most important micro-component in the system.
 * Shows at a glance whether data is live, cached, or assumed.
 */
const TRUTH_ICONS = {
  observed: "\u25CF",    // ● solid circle — live
  remembered: "\u25D2",  // ◒ half circle — cached
  declared: "\u25CB",    // ○ open circle — policy
  stale: "\u25CC",       // ◌ dotted circle — expired
};

export default function TruthBadge(props) {
  const mode = () => props.mode || "declared";

  return (
    <span class={`truth-badge truth-badge--${mode()}`} title={`Truth: ${mode()}`}>
      <span aria-hidden="true">{TRUTH_ICONS[mode()] || TRUTH_ICONS.declared}</span>
      {mode()}
    </span>
  );
}

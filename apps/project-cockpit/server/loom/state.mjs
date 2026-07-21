// state.mjs — classify an agent session into the fixed vocabulary. v1 heuristics;
// richer waiting/idle detection is Phase 4.
export function classify({ alive, lastOutputAt = 0, now = 0, atPrompt = false, awaitingInput = false, stuckAfterMs = 120000 }) {
  if (!alive) return "exited";
  if (awaitingInput) return "waiting";
  const idleMs = now - lastOutputAt;
  if (!atPrompt && idleMs >= stuckAfterMs) return "stuck";
  if (atPrompt) return "idle";
  return "running";
}

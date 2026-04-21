/**
 * Truth Store — per-datapoint truth tracking.
 *
 * Every piece of data in the cockpit carries:
 * - value: the actual data
 * - truthMode: "observed" | "remembered" | "declared" | "stale"
 * - observedAt: ISO timestamp of when this was last observed
 * - source: where the data came from
 *
 * This maps directly to Sounio's Knowledge<T> concept:
 * a reactive container that knows both its value and its epistemic status.
 */
import { createSignal } from "solid-js";

/**
 * Create a truth-aware signal.
 * Like createSignal but carries truth metadata.
 *
 * @param {*} initialValue
 * @param {"observed"|"remembered"|"declared"} initialMode
 * @returns {[() => {value, truthMode, observedAt}, (value, mode?) => void]}
 */
export function createTruthSignal(initialValue, initialMode = "declared") {
  const [state, setState] = createSignal({
    value: initialValue,
    truthMode: initialMode,
    observedAt: initialMode === "observed" ? new Date().toISOString() : null,
    source: null,
  });

  function update(value, mode = "observed", source = null) {
    setState({
      value,
      truthMode: mode,
      observedAt: mode === "observed" ? new Date().toISOString() : state().observedAt,
      source,
    });
  }

  return [state, update];
}

/**
 * Fetch JSON and wrap result in truth metadata.
 * Returns { data, truthMode, observedAt } or { data: null, truthMode: "stale", error }.
 */
export async function fetchWithTruth(url, timeoutMs = 5000) {
  try {
    const res = await fetch(url, { signal: AbortSignal.timeout(timeoutMs) });
    if (!res.ok) throw new Error(`${res.status}`);
    const data = await res.json();
    return {
      data,
      truthMode: "observed",
      observedAt: new Date().toISOString(),
    };
  } catch (e) {
    return {
      data: null,
      truthMode: "stale",
      observedAt: null,
      error: e.message,
    };
  }
}

/**
 * Extract truth mode from API response.
 * Many cockpit endpoints include truthSummary or truth fields.
 */
export function extractTruthMode(response) {
  if (!response) return "stale";
  // Check common truth patterns in API responses
  if (response.truthSummary?.cluster?.truthMode) return response.truthSummary.cluster.truthMode;
  if (response.truth?.truthMode) return response.truth.truthMode;
  if (response.runtime?.truthMode) return response.runtime.truthMode;
  // If we got data, it's at least observed from our perspective
  return "observed";
}

/**
 * Format truth age for display.
 * "2s ago", "5m ago", "3h ago"
 */
export function formatTruthAge(isoTimestamp) {
  if (!isoTimestamp) return "—";
  const age = Date.now() - new Date(isoTimestamp).getTime();
  if (age < 60000) return `${Math.floor(age / 1000)}s ago`;
  if (age < 3600000) return `${Math.floor(age / 60000)}m ago`;
  if (age < 86400000) return `${Math.floor(age / 3600000)}h ago`;
  return `${Math.floor(age / 86400000)}d ago`;
}

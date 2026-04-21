/**
 * Audio Mappings — connect system state to soundscape parameters.
 *
 * This module reads truth modes and system state,
 * then drives the ambient + event audio layers.
 *
 * The mapping philosophy:
 * - System state → continuous ambient modulation (hum, detune, texture)
 * - Discrete events → one-shot sounds (ping, tone, beat)
 */
import { soundscape } from "./soundscape";

/**
 * Map truth modes across all lanes to a degradation level.
 *
 * @param {Object} truthModes — { lane: "observed"|"remembered"|"declared"|"stale" }
 * @returns {number} 0 (all observed) to 2 (mostly stale)
 */
export function computeTruthDegradation(truthModes) {
  if (!truthModes) return 0;
  const modes = Object.values(truthModes);
  if (modes.length === 0) return 0;

  let score = 0;
  for (const mode of modes) {
    if (mode === "stale") score += 3;
    else if (mode === "declared") score += 2;
    else if (mode === "remembered") score += 1;
    // observed = 0
  }

  const avg = score / modes.length;
  if (avg < 0.5) return 0;   // mostly observed
  if (avg < 1.5) return 1;   // some remembered
  return 2;                   // mostly stale/declared
}

/**
 * Update soundscape from current system state.
 * Call this periodically or when state changes.
 *
 * @param {Object} state
 * @param {Object} state.truthModes — per-lane truth modes
 * @param {number} state.gpuUtilization — 0..1
 * @param {string} state.clusterHealth — "healthy"|"degraded"|"down"
 */
export function updateSoundscapeFromState(state) {
  if (!soundscape.isEnabled()) return;

  // Truth degradation → hum detune
  if (state.truthModes) {
    const degradation = computeTruthDegradation(state.truthModes);
    soundscape.setTruthDegradation(degradation);
  }

  // GPU utilization → granular texture
  if (state.gpuUtilization !== undefined) {
    soundscape.setGpuUtilization(state.gpuUtilization);
  }
}

/**
 * Soundscape — master controller for all audio layers.
 *
 * Orchestrates ambient + events.
 * Manages mute state, volume, and lifecycle.
 *
 * Usage:
 *   import { soundscape } from "./audio/soundscape";
 *   soundscape.enable();     // user gesture required
 *   soundscape.onDataObserved();
 *   soundscape.onMutationActivate();
 *   soundscape.setGpuUtilization(0.75);
 *   soundscape.disable();
 */
import { initAmbient, startAmbient, stopAmbient, setGpuLevel, setTruthDetune, setMasterVolume, destroyAmbient, isInitialized } from "./ambient";
import { initEvents, pingDataObserved, toneMutationActivate, toneMutationStandby, beatError, destroyEvents } from "./events";

let enabled = false;

export const soundscape = {
  /**
   * Enable the soundscape. Must be called from user gesture.
   */
  async enable() {
    if (enabled) return;
    await initAmbient();
    initEvents();
    startAmbient();
    enabled = true;
  },

  /**
   * Disable the soundscape.
   */
  disable() {
    if (!enabled) return;
    stopAmbient();
    enabled = false;
  },

  /**
   * Full cleanup.
   */
  destroy() {
    this.disable();
    destroyAmbient();
    destroyEvents();
  },

  /**
   * Check if enabled.
   */
  isEnabled() {
    return enabled;
  },

  // ── Ambient mappings ──

  /**
   * Set GPU utilization (0..1) → modulates granular texture.
   */
  setGpuUtilization(level) {
    if (!enabled) return;
    setGpuLevel(Math.max(0, Math.min(1, level)));
  },

  /**
   * Set truth degradation level.
   * 0 = all observed (nominal hum)
   * 1 = some remembered (slight detune)
   * 2 = mostly stale (noticeable detune)
   */
  setTruthDegradation(level) {
    if (!enabled) return;
    const detune = level * 5; // 0, 5, or 10 cents
    setTruthDetune(detune);
  },

  /**
   * Set master volume (0..1).
   */
  setVolume(level) {
    setMasterVolume(level);
  },

  // ── Event triggers ──

  /** Fresh observed data arrived. */
  onDataObserved() {
    if (!enabled) return;
    pingDataObserved();
  },

  /** Habitat activation started. */
  onMutationActivate() {
    if (!enabled) return;
    toneMutationActivate();
  },

  /** Habitat standby started. */
  onMutationStandby() {
    if (!enabled) return;
    toneMutationStandby();
  },

  /** An error occurred. */
  onError() {
    if (!enabled) return;
    beatError();
  },
};

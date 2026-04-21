/**
 * Audio Store — SolidJS reactive state for the soundscape.
 *
 * Muted by default. User must opt-in.
 * Persisted in localStorage.
 *
 * Tone.js is dynamically imported only when audio is enabled,
 * keeping the initial bundle small.
 */
import { createSignal } from "solid-js";

const STORAGE_KEY = "project-cockpit-audio-enabled";

let soundscapeModule = null;

function loadPref() {
  try {
    return localStorage.getItem(STORAGE_KEY) === "true";
  } catch {
    return false;
  }
}

const [audioEnabled, setAudioEnabledRaw] = createSignal(loadPref());

async function getSoundscape() {
  if (!soundscapeModule) {
    soundscapeModule = await import("../audio/soundscape");
  }
  return soundscapeModule.soundscape;
}

/**
 * Toggle audio on/off. Must be called from user gesture.
 */
export async function toggleAudio() {
  const next = !audioEnabled();
  setAudioEnabledRaw(next);
  try { localStorage.setItem(STORAGE_KEY, String(next)); } catch {}

  const soundscape = await getSoundscape();
  if (next) {
    await soundscape.enable();
  } else {
    soundscape.disable();
  }
}

/**
 * Get the soundscape instance (lazy loaded).
 */
export async function useSoundscape() {
  return getSoundscape();
}

export { audioEnabled };

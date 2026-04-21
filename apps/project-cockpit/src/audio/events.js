/**
 * Audio Events — discrete sounds for operational events.
 *
 * These are NOT alerts. They are brief, subtle sonic cues
 * that encode specific state transitions:
 *
 * - Data ping: crystalline, when fresh observed data arrives
 * - Mutation ascend: rising tone, habitat activating
 * - Mutation descend: falling tone, habitat going standby
 * - Error beat: single dissonant low beat
 */
import * as Tone from "tone";

let dataPing = null;
let mutationSynth = null;
let errorSynth = null;
let eventGain = null;
let initialized = false;

/**
 * Initialize event sounds.
 * Call after Tone.start() from ambient.initAmbient().
 */
export function initEvents(masterDest) {
  if (initialized) return;

  eventGain = new Tone.Gain(0.5).toDestination();

  // Data ping — crystalline metallic partial, very fast decay
  dataPing = new Tone.MetalSynth({
    frequency: 800,
    envelope: {
      attack: 0.001,
      decay: 0.08,
      release: 0.05,
    },
    harmonicity: 5.1,
    modulationIndex: 16,
    resonance: 4000,
    octaves: 1.5,
    volume: -24,
  }).connect(eventGain);

  // Mutation synth — clean sine for glide tones
  mutationSynth = new Tone.Synth({
    oscillator: { type: "sine" },
    envelope: {
      attack: 0.05,
      decay: 0.3,
      sustain: 0.1,
      release: 0.2,
    },
    volume: -22,
  }).connect(eventGain);

  // Error synth — FM for dissonance
  errorSynth = new Tone.FMSynth({
    harmonicity: 1.06,  // minor second = dissonance
    modulationIndex: 3,
    envelope: {
      attack: 0.01,
      decay: 0.4,
      sustain: 0,
      release: 0.3,
    },
    modulation: {
      type: "square",
    },
    volume: -20,
  }).connect(eventGain);

  initialized = true;
}

/**
 * Brief crystalline ping — new observed data arrived.
 */
export function pingDataObserved() {
  if (!dataPing) return;
  dataPing.triggerAttackRelease("16n", Tone.now());
}

/**
 * Ascending tone — habitat activating.
 */
export function toneMutationActivate() {
  if (!mutationSynth) return;
  mutationSynth.triggerAttackRelease("C4", "8n", Tone.now());
  setTimeout(() => {
    mutationSynth.triggerAttackRelease("E4", "8n", Tone.now());
  }, 150);
  setTimeout(() => {
    mutationSynth.triggerAttackRelease("G4", "8n", Tone.now());
  }, 300);
}

/**
 * Descending tone — habitat going standby.
 */
export function toneMutationStandby() {
  if (!mutationSynth) return;
  mutationSynth.triggerAttackRelease("G4", "8n", Tone.now());
  setTimeout(() => {
    mutationSynth.triggerAttackRelease("E4", "8n", Tone.now());
  }, 150);
  setTimeout(() => {
    mutationSynth.triggerAttackRelease("C4", "8n", Tone.now());
  }, 300);
}

/**
 * Single dissonant beat — error occurred.
 */
export function beatError() {
  if (!errorSynth) return;
  errorSynth.triggerAttackRelease("C2", "4n", Tone.now());
}

/**
 * Set event volume (0.0 to 1.0).
 */
export function setEventVolume(level) {
  if (!eventGain) return;
  eventGain.gain.rampTo(level * 0.5, 0.2);
}

/**
 * Cleanup event sounds.
 */
export function destroyEvents() {
  dataPing?.dispose();
  mutationSynth?.dispose();
  errorSynth?.dispose();
  eventGain?.dispose();
  initialized = false;
}

/**
 * Ambient Soundscape — the continuous audio layer.
 *
 * Submarine + NASA control room approach:
 * a low warm hum that encodes system health.
 * When the hum changes, you notice.
 *
 * Components:
 * - Base hum: filtered sine at 80Hz + undertone at 60Hz
 * - Room tone: very quiet pink noise
 * - GPU texture: granular layer proportional to GPU utilization
 *
 * All levels are extremely subtle. This is not music — it's a
 * persistent carrier signal that your brain learns to decode.
 */
import * as Tone from "tone";

let baseHum = null;
let undertone = null;
let roomNoise = null;
let gpuGrain = null;
let masterGain = null;
let limiter = null;
let initialized = false;

/**
 * Initialize the ambient soundscape.
 * Must be called from a user gesture (click/tap) due to Web Audio policy.
 */
export async function initAmbient() {
  if (initialized) return;

  await Tone.start();

  // Master bus
  limiter = new Tone.Limiter(-3).toDestination();
  masterGain = new Tone.Gain(0.35).connect(limiter);

  // Base hum — 80Hz sine, heavily filtered
  const humFilter = new Tone.Filter({
    type: "lowpass",
    frequency: 200,
    Q: 0.7,
  }).connect(masterGain);

  baseHum = new Tone.Oscillator({
    type: "sine",
    frequency: 80,
    volume: -28,
  }).connect(humFilter);

  // Undertone — 60Hz for warmth
  undertone = new Tone.Oscillator({
    type: "sine",
    frequency: 60,
    volume: -34,
  }).connect(humFilter);

  // Room tone — pink noise at very low level
  roomNoise = new Tone.Noise({
    type: "pink",
    volume: -48,
  }).connect(masterGain);

  // GPU texture — granular noise, starts silent
  gpuGrain = new Tone.Noise({
    type: "brown",
    volume: -60,  // effectively silent until GPU activity
  });
  const gpuFilter = new Tone.Filter({
    type: "bandpass",
    frequency: 400,
    Q: 2,
  }).connect(masterGain);
  gpuGrain.connect(gpuFilter);

  initialized = true;
}

/**
 * Start the ambient soundscape.
 */
export function startAmbient() {
  if (!initialized) return;
  baseHum?.start();
  undertone?.start();
  roomNoise?.start();
  gpuGrain?.start();
}

/**
 * Stop the ambient soundscape.
 */
export function stopAmbient() {
  if (!initialized) return;
  baseHum?.stop();
  undertone?.stop();
  roomNoise?.stop();
  gpuGrain?.stop();
}

/**
 * Set GPU utilization level (0.0 to 1.0).
 * Modulates the granular texture layer.
 */
export function setGpuLevel(level) {
  if (!gpuGrain) return;
  // Map 0..1 to -60dB (silent) .. -30dB (audible)
  const db = -60 + level * 30;
  gpuGrain.volume.rampTo(db, 0.5);
}

/**
 * Apply truth degradation — detune the hum.
 * Called when truth modes shift from observed → remembered → stale.
 *
 * @param {number} detuneAmount — cents of detuning (0 = nominal, 5 = slight, 12 = noticeable)
 */
export function setTruthDetune(detuneAmount) {
  if (!baseHum) return;
  baseHum.detune.rampTo(detuneAmount, 1.0);
  undertone?.detune.rampTo(detuneAmount * 0.7, 1.2);
}

/**
 * Set master volume (0.0 to 1.0).
 */
export function setMasterVolume(level) {
  if (!masterGain) return;
  masterGain.gain.rampTo(level * 0.35, 0.3);
}

/**
 * Check if soundscape is initialized.
 */
export function isInitialized() {
  return initialized;
}

/**
 * Cleanup all audio nodes.
 */
export function destroyAmbient() {
  stopAmbient();
  baseHum?.dispose();
  undertone?.dispose();
  roomNoise?.dispose();
  gpuGrain?.dispose();
  masterGain?.dispose();
  limiter?.dispose();
  initialized = false;
}

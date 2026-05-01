// Job preset helpers.
//
// Presets are optional sugar over the explicit job submission payload. The
// server must stay bootable even when no preset catalog is configured, so this
// module deliberately defaults to an empty catalog and returns the caller's
// payload unchanged.

const PRESETS = Object.freeze({});

export function listPresets() {
  return Object.entries(PRESETS).map(([id, preset]) => ({ id, ...preset }));
}

export function applyPreset(presetId, rawOptions = {}) {
  const id = typeof presetId === "string" ? presetId.trim() : "";
  const preset = id ? PRESETS[id] : null;
  if (!preset) return { ...rawOptions };

  return {
    ...preset,
    ...rawOptions,
    labels: {
      ...(preset.labels || {}),
      ...(rawOptions.labels || {}),
      "sounio.dev/preset": id,
    },
  };
}

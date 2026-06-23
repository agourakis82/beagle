// Validate + normalize incoming Physiome batches. Pure (no I/O), testable.
const UUID_RE = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;

function num(v) {
  if (v == null || v === "") return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

export function validateHealthSample(s) {
  if (!s || !UUID_RE.test(s.uuid || "") || !s.ts || !s.type) return null;
  return {
    uuid: s.uuid,
    ts: s.ts,
    end_ts: s.end_ts || null,
    type: String(s.type),
    value: num(s.value),
    unit: s.unit || null,
    source: s.source || null,
    device: s.device || null,
    metadata: s.metadata && typeof s.metadata === "object" ? s.metadata : {},
  };
}

export function validateWeatherObs(w) {
  if (!w || !w.ts) return null;
  return {
    ts: w.ts,
    lat: num(w.lat) ?? 0,
    lon: num(w.lon) ?? 0,
    temp_c: num(w.temp_c),
    pressure_hpa: num(w.pressure_hpa),
    humidity: num(w.humidity),
    uv_index: num(w.uv_index),
    precip: num(w.precip),
    aqi: num(w.aqi),
    condition: w.condition || null,
    metadata: w.metadata && typeof w.metadata === "object" ? w.metadata : {},
  };
}

export function validateBatch(body) {
  // The iOS uploader sends health_samples + sleep_samples + workout_samples (all the same
  // shape: uuid/ts/end_ts/type/value/...) — they all land in the one health_samples table.
  const hs = [
    ...(Array.isArray(body?.health_samples) ? body.health_samples : []),
    ...(Array.isArray(body?.sleep_samples) ? body.sleep_samples : []),
    ...(Array.isArray(body?.workout_samples) ? body.workout_samples : []),
  ];
  const wo = Array.isArray(body?.weather_obs) ? body.weather_obs : [];
  return {
    health_samples: hs.map(validateHealthSample).filter(Boolean),
    weather_obs: wo.map(validateWeatherObs).filter(Boolean),
  };
}

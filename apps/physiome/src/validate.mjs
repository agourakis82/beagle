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
  // Lossless: the iOS WeatherSyncEngine sends richer fields than weather_obs has columns
  // for. Map what has a column; fold the rest into metadata JSONB so nothing is dropped.
  const base = w.metadata && typeof w.metadata === "object" ? { ...w.metadata } : {};
  for (const k of ["wind_kph", "dew_point_c", "visibility_km"]) {
    const v = num(w[k]);
    if (v != null) base[k] = v;
  }
  return {
    ts: w.ts,
    lat: num(w.lat) ?? 0,
    lon: num(w.lon) ?? 0,
    temp_c: num(w.temp_c),
    pressure_hpa: num(w.pressure_hpa),
    humidity: num(w.humidity),
    uv_index: num(w.uv_index),
    precip: num(w.precip) ?? num(w.precip_mm), // client field is precip_mm
    aqi: num(w.aqi),
    // AMBIENT (device barometer) vs the station temp_c/pressure_hpa above, + place.
    ambient_pressure_hpa: num(w.ambient_pressure_hpa),
    altitude_m: num(w.altitude_m),
    city: typeof w.city === "string" ? w.city : null,
    place: typeof w.place === "string" ? w.place : null,
    condition: w.condition || null,
    metadata: base,
  };
}

// Keep the LAST item for each key (a Map preserves insertion order; re-setting a key
// keeps its original position but updates the value — so we rebuild to last-wins order).
function dedupeBy(items, keyOf) {
  const m = new Map();
  for (const it of items) m.set(keyOf(it), it);
  return [...m.values()];
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
  const validHealth = hs.map(validateHealthSample).filter(Boolean);
  const validWeather = wo.map(validateWeatherObs).filter(Boolean);
  // Dedupe within the batch (HealthKit can re-deliver the same sample). Two rows with
  // the same conflict key in one INSERT make Postgres throw "ON CONFLICT DO UPDATE
  // cannot affect row a second time" → 500. Last occurrence wins (newest data).
  const health_samples = dedupeBy(validHealth, (s) => s.uuid);
  const weather_obs = dedupeBy(validWeather, (w) => `${w.ts}|${w.lat}|${w.lon}`);
  // Surface what was dropped so the client (and logs) can see silent loss instead of
  // a batch that quietly shrank. A non-zero `rejected` is a signal worth alerting on.
  return {
    health_samples,
    weather_obs,
    received: { health: hs.length, weather: wo.length },
    rejected: { health: hs.length - health_samples.length, weather: wo.length - weather_obs.length },
  };
}

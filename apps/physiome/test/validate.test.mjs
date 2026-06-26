import { test } from "node:test";
import assert from "node:assert/strict";
import { validateHealthSample, validateWeatherObs, validateBatch } from "../src/validate.mjs";

test("valid health sample passes + normalizes", () => {
  const s = validateHealthSample({
    uuid: "11111111-1111-1111-1111-111111111111",
    ts: "2026-06-22T08:00:00Z",
    type: "HKQuantityTypeIdentifierHeartRate",
    value: "62", unit: "count/min", source: "Watch",
  });
  assert.equal(s.type, "HKQuantityTypeIdentifierHeartRate");
  assert.equal(s.value, 62);
  assert.equal(s.uuid, "11111111-1111-1111-1111-111111111111");
});

test("rejects sample missing uuid/ts/type", () => {
  assert.equal(validateHealthSample({ value: 1 }), null);
  assert.equal(validateHealthSample({ uuid: "bad", ts: "x" }), null);
});

test("validateWeatherObs requires ts, coerces numbers", () => {
  assert.equal(validateWeatherObs({}), null);
  const w = validateWeatherObs({ ts: "2026-06-22T08:00:00Z", lat: "1.5", lon: "2.5", pressure_hpa: "1009" });
  assert.equal(w.pressure_hpa, 1009);
});

test("validateWeatherObs is lossless: precip_mm alias + extra fields folded into metadata", () => {
  // The iOS WeatherSyncEngine sends richer fields than weather_obs has columns for.
  // Nothing should be silently dropped: precip_mm → precip, the rest → metadata JSONB.
  const w = validateWeatherObs({
    ts: "2026-06-24T08:00:00Z", lat: -23.5, lon: -46.6,
    temp_c: 21, pressure_hpa: 1012, humidity: 60, uv_index: 4, condition: "Cloudy",
    precip_mm: 2.5, wind_kph: 12, dew_point_c: 14, visibility_km: 10,
  });
  assert.equal(w.temp_c, 21);
  assert.equal(w.pressure_hpa, 1012);
  assert.equal(w.precip, 2.5, "precip_mm aliased to the precip column");
  assert.equal(w.metadata.wind_kph, 12, "wind preserved in metadata");
  assert.equal(w.metadata.dew_point_c, 14, "dew point preserved in metadata");
  assert.equal(w.metadata.visibility_km, 10, "visibility preserved in metadata");
});

test("validateBatch drops invalid, keeps valid", () => {
  const r = validateBatch({
    health_samples: [
      { uuid: "x" },
      { uuid: "22222222-2222-2222-2222-222222222222", ts: "2026-06-22T08:00:00Z", type: "HKQuantityTypeIdentifierStepCount", value: 10, unit: "count" },
    ],
    weather_obs: [{ ts: "2026-06-22T08:00:00Z", lat: 0, lon: 0 }],
  });
  assert.equal(r.health_samples.length, 1);
  assert.equal(r.weather_obs.length, 1);
});

test("validateBatch merges sleep_samples + workout_samples into health_samples", () => {
  const mk = (u, t) => ({ uuid: u, ts: "2026-06-23T08:00:00Z", type: t, value: 1 });
  const r = validateBatch({
    health_samples: [mk("11111111-1111-1111-1111-111111111111", "HKQuantityTypeIdentifierStepCount")],
    sleep_samples: [mk("22222222-2222-2222-2222-222222222222", "HKCategoryTypeIdentifierSleepAnalysis")],
    workout_samples: [mk("33333333-3333-3333-3333-333333333333", "HKWorkout")],
  });
  assert.equal(r.health_samples.length, 3);
});

test("validateBatch dedupes duplicate uuids within a batch (HealthKit re-delivers) — last wins", () => {
  // Two rows with the same uuid in one INSERT make Postgres throw "ON CONFLICT DO
  // UPDATE command cannot affect row a second time" → 500. Collapse to one, last wins.
  const r = validateBatch({
    health_samples: [
      { uuid: "aaaaaaaa-0000-4000-8000-000000000001", ts: "2026-06-24T18:00:00Z", type: "HKQuantityTypeIdentifierHeartRate", value: 60 },
      { uuid: "aaaaaaaa-0000-4000-8000-000000000001", ts: "2026-06-24T18:01:00Z", type: "HKQuantityTypeIdentifierHeartRate", value: 61 },
      { uuid: "bbbbbbbb-0000-4000-8000-000000000002", ts: "2026-06-24T18:00:00Z", type: "HKQuantityTypeIdentifierHeartRate", value: 70 },
    ],
  });
  assert.equal(r.health_samples.length, 2, "duplicate uuid collapsed");
  const a = r.health_samples.find((s) => s.uuid.startsWith("aaaaaaaa"));
  assert.equal(a.value, 61, "last occurrence wins");
});

test("validateBatch dedupes weather by (ts,lat,lon) — last wins", () => {
  const r = validateBatch({
    weather_obs: [
      { ts: "2026-06-24T18:00:00Z", lat: 1, lon: 2, temp_c: 20 },
      { ts: "2026-06-24T18:00:00Z", lat: 1, lon: 2, temp_c: 21 },
    ],
  });
  assert.equal(r.weather_obs.length, 1, "duplicate (ts,lat,lon) collapsed");
  assert.equal(r.weather_obs[0].temp_c, 21, "last wins");
});

test("validateBatch reports rejected counts so the client knows what was dropped (no silent loss)", () => {
  const r = validateBatch({
    health_samples: [
      { uuid: "x" }, // bad
      { uuid: "22222222-2222-2222-2222-222222222222", ts: "2026-06-22T08:00:00Z", type: "HKQuantityTypeIdentifierStepCount", value: 10 },
    ],
    weather_obs: [{ lat: 0 }, { ts: "2026-06-22T08:00:00Z", lat: 0, lon: 0 }], // first bad (no ts)
  });
  assert.deepEqual(r.rejected, { health: 1, weather: 1 }, "counts of dropped samples surfaced");
  assert.deepEqual(r.received, { health: 2, weather: 2 }, "counts of received samples surfaced");
  assert.equal(r.health_samples.length, 1);
  assert.equal(r.weather_obs.length, 1);
});

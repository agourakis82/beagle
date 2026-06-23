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

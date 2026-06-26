import { test } from "node:test";
import assert from "node:assert/strict";
import { buildPhysiomeSummary } from "../src/digest.mjs";

test("summary mentions sleep, HRV, pressure trend, Kp; capped", () => {
  const s = buildPhysiomeSummary({
    date: "2026-06-22",
    health: { sleepHours: 5.2, hrvMs: 38, restingHr: 58, steps: 8200, activeKcal: 430 },
    weather: { tempMinC: 14, tempMaxC: 23, pressureTrendHpa: -6, uvMax: 8, aqi: 42 },
    space: { kpMax: 5, f107: 142, solarWindSpeed: 620 },
  });
  for (const frag of ["5.2", "38", "-6", "Kp", "2026-06-22"]) assert.ok(s.includes(frag), frag);
  assert.ok(s.length < 1200);
});

test("handles missing sections gracefully", () => {
  const s = buildPhysiomeSummary({ date: "2026-06-22", health: {}, weather: {}, space: {} });
  assert.ok(s.includes("2026-06-22"));
  assert.ok(typeof s === "string" && s.length > 0);
});

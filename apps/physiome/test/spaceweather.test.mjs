import { test } from "node:test";
import assert from "node:assert/strict";
import { parseKp, parseF107, parseSolarWind, mergeSpaceWeather } from "../src/spaceweather.mjs";

// NOAA SWPC products are array-of-arrays with a header row.
const KP = [
  ["time_tag", "Kp", "a_running", "station_count"],
  ["2026-06-22 00:00:00", "3.67", "20", "8"],
  ["2026-06-22 03:00:00", "5.00", "48", "8"],
];
const F107 = [
  ["time_tag", "flux"],
  ["2026-06-21 00:00:00", "139"],
  ["2026-06-22 00:00:00", "142"],
];
const PLASMA = [
  ["time_tag", "density", "speed", "temperature"],
  ["2026-06-22 11:58:00", "4.1", "615", "120000"],
  ["2026-06-22 11:59:00", "4.0", "620", "121000"],
];
const MAG = [
  ["time_tag", "bx_gsm", "by_gsm", "bz_gsm", "lon_gsm", "lat_gsm", "bt"],
  ["2026-06-22 11:59:00", "1.2", "-3.4", "-5.6", "120", "10", "6.8"],
];

test("parseKp reads time + Kp by header", () => {
  const r = parseKp(KP);
  assert.equal(r.length, 2);
  assert.equal(r[1].kp, 5.0);
});

test("parseF107 reads flux", () => {
  const r = parseF107(F107);
  assert.equal(r.at(-1).f107, 142);
});

test("parseSolarWind takes speed (plasma) + bz (mag)", () => {
  const r = parseSolarWind(PLASMA, MAG);
  assert.equal(r.speed.at(-1).value, 620);
  assert.equal(r.bz.at(-1).value, -5.6);
});

test("mergeSpaceWeather → latest snapshot row", () => {
  const row = mergeSpaceWeather({ kp: parseKp(KP), f107: parseF107(F107), ...parseSolarWind(PLASMA, MAG) });
  assert.equal(row.kp, 5.0);
  assert.equal(row.f107, 142);
  assert.equal(row.solar_wind_speed, 620);
  assert.equal(row.bz, -5.6);
  assert.ok(row.ts);
});

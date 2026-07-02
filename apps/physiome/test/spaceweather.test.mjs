import { test } from "node:test";
import assert from "node:assert/strict";
import { parseKp, parseDst, parseF107, parseSolarWind, parseHpAscii, parseNmdbAscii, mergeSpaceWeather } from "../src/spaceweather.mjs";

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
const DST = [
  ["time_tag", "dst"],
  ["2026-06-22 10:00:00", "-15"],
  ["2026-06-22 11:00:00", "-72"],
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

// NOAA also serves array-of-objects (Kp, F10.7 products).
test("parseKp/parseF107 handle array-of-objects format", () => {
  const kpObj = [
    { time_tag: "2026-06-22T00:00:00", Kp: 2.0, a_running: 7 },
    { time_tag: "2026-06-22T03:00:00", Kp: 4.33, a_running: 20 },
  ];
  const f107Obj = [{ time_tag: "2026-06-21T20:00:00", flux: 141 }, { time_tag: "2026-06-22T20:00:00", flux: 143 }];
  assert.equal(parseKp(kpObj).at(-1).kp, 4.33);
  assert.equal(parseF107(f107Obj).at(-1).f107, 143);
});

test("parseDst reads time + Dst by header", () => {
  const r = parseDst(DST);
  assert.equal(r.length, 2);
  assert.equal(r.at(-1).dst, -72);
});

test("parseDst handles array-of-objects format", () => {
  const dstObj = [
    { time_tag: "2026-06-22T10:00:00", dst: -10 },
    { time_tag: "2026-06-22T11:00:00", dst: -55 },
  ];
  assert.equal(parseDst(dstObj).at(-1).dst, -55);
});

test("mergeSpaceWeather → latest snapshot row", () => {
  const row = mergeSpaceWeather({ kp: parseKp(KP), dst: parseDst(DST), f107: parseF107(F107), ...parseSolarWind(PLASMA, MAG) });
  assert.equal(row.kp, 5.0);
  assert.equal(row.dst, -72);
  assert.equal(row.f107, 142);
  assert.equal(row.solar_wind_speed, 620);
  assert.equal(row.bz, -5.6);
  assert.ok(row.ts);
});

// GFZ Hp30 nowcast: real column layout, -1 = not-yet-observed (dropped), decimal hour → ts.
const HP30 = [
  "# YYY MM DD hh.h hh._m days days_m Hp30 ap30 D",
  "2026 07 02 16.0 16.25 34516.66667 34516.67708  1.000    4 0",
  "2026 07 02 16.5 16.75 34516.68750 34516.69792  0.667    3 0",
  "2026 07 02 17.0 17.25 34516.70833 34516.71875 -1.000   -1 0", // future → dropped
].join("\n");

test("parseHpAscii drops -1 rows and builds ts from decimal hour", () => {
  const s = parseHpAscii(HP30);
  assert.equal(s.length, 2, "only observed rows");
  assert.deepEqual(s[0], { ts: "2026-07-02T16:00:00Z", hp: 1.0, ap: 4 });
  assert.equal(s[1].ts, "2026-07-02T16:30:00Z"); // 16.5 → :30
  assert.equal(s[1].hp, 0.667);
});

test("parseNmdbAscii parses semicolon rows, skips comments/header", () => {
  const txt = "# NMDB\nstart_date_time;RCORR_E\n2026-07-02 10:00:00;6543.2\n2026-07-02 11:00:00;6551.9\n";
  const s = parseNmdbAscii(txt);
  assert.equal(s.length, 2);
  assert.deepEqual(s.at(-1), { ts: "2026-07-02T11:00:00Z", count: 6551.9 });
  assert.deepEqual(parseNmdbAscii(""), []); // fail-soft on empty/blocked body
});

test("mergeSpaceWeather carries hp30/ap30/cosmicRay", () => {
  const row = mergeSpaceWeather({
    kp: parseKp(KP), hp30: parseHpAscii(HP30),
    cosmicRay: [{ ts: "2026-07-02T11:00:00Z", count: 6551.9 }],
  });
  assert.equal(row.hp30, 0.667);
  assert.equal(row.ap30, 3);
  assert.equal(row.cosmic_ray_oulu, 6551.9);
  assert.match(row.source, /gfz/);
});

import { test } from "node:test";
import assert from "node:assert/strict";
import { fetchRecentMemories, fetchSpaceWeatherNow } from "./auth-bridge.mjs";

test("fetchRecentMemories returns results array on 200", async () => {
  const stub = async () => ({
    ok: true,
    json: async () => ({ results: [{ text: "a", occurred_at: "2026-06-25T10:00:00Z" }] }),
  });
  const out = await fetchRecentMemories("oi", { baseUrl: "http://x", token: "", k: 5, fetchImpl: stub });
  assert.deepEqual(out, [{ text: "a", occurred_at: "2026-06-25T10:00:00Z" }]);
});

test("fetchRecentMemories is fail-soft: empty array on error", async () => {
  const stub = async () => { throw new Error("down"); };
  const out = await fetchRecentMemories("oi", { baseUrl: "http://x", fetchImpl: stub });
  assert.deepEqual(out, []);
});

test("fetchRecentMemories empty query → no call, empty array", async () => {
  let called = false;
  const stub = async () => { called = true; return { ok: true, json: async () => ({ results: [] }) }; };
  const out = await fetchRecentMemories("  ", { baseUrl: "http://x", fetchImpl: stub });
  assert.equal(called, false);
  assert.deepEqual(out, []);
});

// ── fetchSpaceWeatherNow (latest space weather; best-effort, cached) ──────────

test("fetchSpaceWeatherNow parses latest + maps solar_wind_speed", async () => {
  const stub = async () => ({
    ok: true,
    json: async () => ({
      ok: true,
      latest: { ts: "2026-06-22T11:00:00Z", kp: 5.8, dst: -72, solar_wind_speed: 385, bz: -5.6 },
    }),
  });
  const out = await fetchSpaceWeatherNow({ baseUrl: "http://x", fetchImpl: stub, useCache: false });
  assert.equal(out.kp, 5.8);
  assert.equal(out.dst, -72);
  assert.equal(out.solarWind, 385);
  assert.equal(out.bz, -5.6);
  assert.equal(out.ts, "2026-06-22T11:00:00Z");
});

test("fetchSpaceWeatherNow: empty latest → null", async () => {
  const stub = async () => ({ ok: true, json: async () => ({ ok: true, latest: null }) });
  const out = await fetchSpaceWeatherNow({ baseUrl: "http://x", fetchImpl: stub, useCache: false });
  assert.equal(out, null);
});

test("fetchSpaceWeatherNow: fail-soft → null on error", async () => {
  const stub = async () => { throw new Error("down"); };
  const out = await fetchSpaceWeatherNow({ baseUrl: "http://x", fetchImpl: stub, useCache: false });
  assert.equal(out, null);
});

test("fetchSpaceWeatherNow: non-finite fields coerced to null", async () => {
  const stub = async () => ({
    ok: true,
    json: async () => ({ ok: true, latest: { ts: "t", kp: null, dst: -50, solar_wind_speed: null, bz: null } }),
  });
  const out = await fetchSpaceWeatherNow({ baseUrl: "http://x", fetchImpl: stub, useCache: false });
  assert.equal(out.kp, null);
  assert.equal(out.dst, -50);
  assert.equal(out.solarWind, null);
});

test("fetchSpaceWeatherNow: caches within TTL (second call doesn't re-fetch)", async () => {
  let calls = 0;
  const stub = async () => {
    calls++;
    return { ok: true, json: async () => ({ ok: true, latest: { ts: "t", kp: 3, dst: -10, solar_wind_speed: 300, bz: 1 } }) };
  };
  const a = await fetchSpaceWeatherNow({ baseUrl: "http://x", fetchImpl: stub });
  const b = await fetchSpaceWeatherNow({ baseUrl: "http://x", fetchImpl: stub });
  assert.equal(calls, 1, "second call served from cache");
  assert.deepEqual(a, b);
});

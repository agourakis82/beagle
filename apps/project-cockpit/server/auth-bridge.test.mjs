import { test } from "node:test";
import assert from "node:assert/strict";
import { fetchRecentMemories } from "./auth-bridge.mjs";

test("fetchRecentMemories returns results array on 200", async () => {
  const stub = async () => ({
    ok: true,
    json: async () => ({ results: [{ text: "a", occurred_at: "2026-06-25T10:00:00Z" }] }),
  });
  const out = await fetchRecentMemories("oi", { baseUrl: "http://x", token: "", k: 5, fetchImpl: stub });
  assert.deepEqual(out, [{ text: "a", occurred_at: "2026-06-25T10:00:00Z" }]);
});

test("fetchRecentMemories passes trusted_only in the /query body when requested", async () => {
  let sentBody = null;
  const stub = async (_url, opts) => {
    sentBody = JSON.parse(opts.body);
    return { ok: true, json: async () => ({ results: [] }) };
  };
  await fetchRecentMemories("oi", { baseUrl: "http://x", k: 16, trustedOnly: true, fetchImpl: stub });
  assert.equal(sentBody.trusted_only, true);
  assert.equal(sentBody.k, 16);
  // default stays false (background/broad recall must remain unfiltered)
  await fetchRecentMemories("oi", { baseUrl: "http://x", fetchImpl: stub });
  assert.equal(sentBody.trusted_only, false);
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

import { fetchSounioState, fetchSounioRelationship } from "./auth-bridge.mjs";

test("fetchSounioState: returns latest state digest on 200", async () => {
  const stub = async () => ({
    ok: true,
    text: async () => JSON.stringify({ highlights: [
      { snippet: "Sounio agora: branch ativa `feat/x`.", date: "2026-06-28T10:00:00Z" },
      { snippet: "stale", date: "2026-06-20T10:00:00Z" },
    ] }),
  });
  const out = await fetchSounioState({ token: "t", fetchImpl: stub, cache: false });
  assert.equal(out.digest, "Sounio agora: branch ativa `feat/x`.");
});

test("fetchSounioState: empty highlights → empty digest", async () => {
  const stub = async () => ({ ok: true, text: async () => JSON.stringify({ highlights: [] }) });
  const out = await fetchSounioState({ token: "t", fetchImpl: stub, cache: false });
  assert.equal(out.digest, "");
});

test("fetchSounioState: fail-soft on throw", async () => {
  const stub = async () => { throw new Error("down"); };
  const out = await fetchSounioState({ token: "t", fetchImpl: stub, cache: false });
  assert.equal(out.digest, "");
});

test("fetchSounioRelationship: returns trusted results, drops unverified", async () => {
  const stub = async () => ({
    ok: true,
    json: async () => ({ results: [
      { text: "quero que o Sounio compile a si mesmo", trust_tier: "corroborated", occurred_at: "2026-06-01T00:00:00Z" },
      { text: "memória inventada", trust_tier: "unverified", occurred_at: "2026-06-02T00:00:00Z" },
      { text: "sem tier", occurred_at: "2026-06-03T00:00:00Z" },
    ] }),
  });
  const out = await fetchSounioRelationship({ baseUrl: "http://x", fetchImpl: stub, cache: false });
  assert.deepEqual(out.map(r => r.text), [
    "quero que o Sounio compile a si mesmo",
    "sem tier",
  ]);
});

test("fetchSounioRelationship: fail-soft → empty array", async () => {
  const stub = async () => { throw new Error("down"); };
  const out = await fetchSounioRelationship({ baseUrl: "http://x", fetchImpl: stub, cache: false });
  assert.deepEqual(out, []);
});

import { fetchSpaceWeatherNow } from "./auth-bridge.mjs";

test("fetchSpaceWeatherNow: parses latest, maps solar_wind_speed→solarWind", async () => {
  const stub = async () => ({
    ok: true,
    text: async () => JSON.stringify({
      ok: true,
      latest: { ts: "2026-06-28T12:00:00Z", kp: 5.8, dst: -72, solar_wind_speed: 385, bz: -6 },
    }),
  });
  const out = await fetchSpaceWeatherNow({ baseUrl: "http://x", fetchImpl: stub, cache: false });
  assert.deepEqual(out, { kp: 5.8, dst: -72, solarWind: 385, bz: -6, ts: "2026-06-28T12:00:00Z" });
});

test("fetchSpaceWeatherNow: latest:null → null", async () => {
  const stub = async () => ({ ok: true, text: async () => JSON.stringify({ ok: true, latest: null }) });
  const out = await fetchSpaceWeatherNow({ baseUrl: "http://x", fetchImpl: stub, cache: false });
  assert.equal(out, null);
});

test("fetchSpaceWeatherNow: fail-soft → null on throw and on !ok", async () => {
  const boom = async () => { throw new Error("down"); };
  assert.equal(await fetchSpaceWeatherNow({ baseUrl: "http://x", fetchImpl: boom, cache: false }), null);
  const notOk = async () => ({ ok: false, text: async () => "500" });
  assert.equal(await fetchSpaceWeatherNow({ baseUrl: "http://x", fetchImpl: notOk, cache: false }), null);
});

import { fetchAgoraHistory } from "./auth-bridge.mjs";

test("fetchAgoraHistory: returns sky/weather/hrv arrays", async () => {
  const stub = async (url) => {
    assert.match(url, /\/api\/physiome\/agora-history\?hours=48/);
    return {
      ok: true,
      text: async () => JSON.stringify({
        ok: true, hours: 48,
        sky: [{ ts: "t", kp: 3, dst: -10, solar_wind_speed: 400, bz: -1 }],
        weather: [{ ts: "t", temp_c: 21, pressure_hpa: 1012 }],
        hrv: [{ ts: "t", value: 45 }],
      }),
    };
  };
  const out = await fetchAgoraHistory({ baseUrl: "http://x", fetchImpl: stub, cache: false });
  assert.equal(out.sky.length, 1);
  assert.equal(out.weather[0].temp_c, 21);
  assert.equal(out.hrv[0].value, 45);
});

test("fetchAgoraHistory: fail-soft → null", async () => {
  const boom = async () => { throw new Error("down"); };
  assert.equal(await fetchAgoraHistory({ baseUrl: "http://x", fetchImpl: boom, cache: false }), null);
});

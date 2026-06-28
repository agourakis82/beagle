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

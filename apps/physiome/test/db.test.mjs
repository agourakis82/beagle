import { test } from "node:test";
import assert from "node:assert/strict";
import { upsertHealthSamples, upsertWeather } from "../src/db.mjs";

// Fake pg Pool: records every query on a single checked-out client so we can assert
// chunking (no INSERT exceeds Postgres' 65535-param ceiling), transaction framing
// (BEGIN…COMMIT / ROLLBACK), and that the client is always released.
function fakePool({ failOnInsertIndex } = {}) {
  const queries = [];
  let released = false;
  let inserts = 0;
  const client = {
    query: async (sql, params) => {
      const s = String(sql).trim();
      queries.push({ sql: s, nparams: params ? params.length : 0, params: params || [] });
      if (s.startsWith("INSERT")) {
        if (failOnInsertIndex != null && inserts === failOnInsertIndex) {
          inserts++;
          throw new Error("boom");
        }
        inserts++;
      }
      return { rowCount: params ? params.length : 0 };
    },
    release: () => { released = true; },
  };
  return {
    connect: async () => client,
    queries,
    released: () => released,
  };
}

function healthRow(i) {
  return { uuid: `u${i}`, ts: "2026-06-24T00:00:00Z", end_ts: null, type: "HRV", value: i, unit: "ms", source: "Watch", device: null, metadata: {} };
}

test("upsertHealthSamples: sends one ARRAY PER COLUMN, chunked, and loses no row", async () => {
  const pool = fakePool();
  const N = 12000;
  const rows = Array.from({ length: N }, (_, i) => healthRow(i));
  const n = await upsertHealthSamples(pool, rows);

  assert.equal(n, N, "returns total rows upserted");
  const inserts = pool.queries.filter((q) => q.sql.startsWith("INSERT"));
  assert.ok(inserts.length >= 2, "large batch split into multiple INSERTs");

  // The point of unnest: params no longer scale with row count. 9 columns → 9 params,
  // whatever the batch size. Asserting "<= 65535" here would be vacuously true.
  for (const q of inserts) {
    assert.equal(q.nparams, 9, "one bound param per COLUMN, not per cell");
    assert.ok(q.params.every(Array.isArray), "every param is a column array");
    const lens = new Set(q.params.map((a) => a.length));
    assert.equal(lens.size, 1, "all column arrays same length — unnest zips them by position");
    assert.ok([...lens][0] <= 5000, "chunk stays within the transaction chunk size");
  }
  // No row silently dropped between chunks.
  const total = inserts.reduce((s, q) => s + q.params[0].length, 0);
  assert.equal(total, N, "every row reached an INSERT");
  // And the uuid array carries the actual uuids, in order.
  assert.equal(inserts[0].params[0][0], "u0");
});

test("upsertHealthSamples: wraps the inserts in a single transaction", async () => {
  const pool = fakePool();
  await upsertHealthSamples(pool, Array.from({ length: 3 }, (_, i) => healthRow(i)));
  const kinds = pool.queries.map((q) => q.sql.split(/\s/)[0]);
  assert.equal(kinds[0], "BEGIN", "opens a transaction");
  assert.equal(kinds[kinds.length - 1], "COMMIT", "commits at the end");
  assert.ok(pool.released(), "client released");
});

test("upsertHealthSamples: rolls back and rethrows if an INSERT fails, still releasing the client", async () => {
  const pool = fakePool({ failOnInsertIndex: 1 });
  const rows = Array.from({ length: 12000 }, (_, i) => healthRow(i)); // ≥2 inserts; 2nd fails
  await assert.rejects(() => upsertHealthSamples(pool, rows), /boom/);
  const kinds = pool.queries.map((q) => q.sql.split(/\s/)[0]);
  assert.ok(kinds.includes("ROLLBACK"), "rolls back on failure");
  assert.ok(!kinds.includes("COMMIT"), "does not commit a failed batch");
  assert.ok(pool.released(), "client released even on failure");
});

test("upsertHealthSamples: empty batch is a no-op (no connection taken)", async () => {
  const pool = fakePool();
  const n = await upsertHealthSamples(pool, []);
  assert.equal(n, 0);
  assert.equal(pool.queries.length, 0, "no transaction for an empty batch");
});

test("upsertWeather: chunks + transacts too (temperature/pressure firehose is robust)", async () => {
  const pool = fakePool();
  const N = 9000; // 9000 × 11 cols = 99000 params → MUST split
  const rows = Array.from({ length: N }, (_, i) => ({
    ts: "2026-06-24T00:00:00Z", lat: -23.5, lon: -46.6, temp_c: 21 + (i % 5), pressure_hpa: 1013 + (i % 7),
    humidity: 0.5, uv_index: 3, precip: 0, aqi: 40, condition: "Clear", metadata: {},
  }));
  const n = await upsertWeather(pool, rows);
  assert.equal(n, N);
  const inserts = pool.queries.filter((q) => q.sql.startsWith("INSERT"));
  assert.ok(inserts.length >= 2, "weather batch split");
  for (const q of inserts) assert.ok(q.nparams <= 65535, `weather INSERT params ${q.nparams} within ceiling`);
  const kinds = pool.queries.map((q) => q.sql.split(/\s/)[0]);
  assert.equal(kinds[0], "BEGIN");
  assert.equal(kinds[kinds.length - 1], "COMMIT");
});

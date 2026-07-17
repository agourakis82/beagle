// recentTrusted: recent non-unverified records by recency.
import { test, before, beforeEach, after } from "node:test";
import assert from "node:assert/strict";
import { makePool, ensureSchema } from "../src/db.mjs";
import { recentTrusted } from "../src/recent.mjs";

const DSN = process.env.MEMORY_PG_TEST_DSN;
if (!DSN) throw new Error("MEMORY_PG_TEST_DSN must be set (scratch DSN)");
if (!/\/[^/]*test[^/]*$/i.test(DSN)) throw new Error("Refusing: DSN name must contain 'test'");
const pool = makePool(DSN);

async function seed({ text, tier, ageDays }) {
  await pool.query(
    `INSERT INTO records (source_type, content, content_sha256, trust_tier, occurred_at)
     VALUES ('T', $1, 'sha-'||gen_random_uuid()::text, $2, now() - ($3||' days')::interval)`,
    [text, tier, String(ageDays)]);
}

before(async () => { await ensureSchema(pool); });
beforeEach(async () => { await pool.query("TRUNCATE records CASCADE"); });
after(async () => { await pool.end(); });

test("returns recent trusted records, excludes unverified and out-of-window", async () => {
  await seed({ text: "his recent claimed thought", tier: "claimed", ageDays: 1 });
  await seed({ text: "recent model noise", tier: "unverified", ageDays: 1 });
  await seed({ text: "old claimed thought", tier: "claimed", ageDays: 30 });
  const rows = await recentTrusted(pool, { windowDays: 7, limit: 10 });
  assert.deepEqual(rows.map((r) => r.text), ["his recent claimed thought"]);
  assert.equal(rows[0].trust_tier, "claimed");
});

test("orders by recency (newest first) and respects limit", async () => {
  await seed({ text: "older", tier: "claimed", ageDays: 3 });
  await seed({ text: "newer", tier: "corroborated", ageDays: 1 });
  const rows = await recentTrusted(pool, { windowDays: 7, limit: 1 });
  assert.deepEqual(rows.map((r) => r.text), ["newer"]);
});

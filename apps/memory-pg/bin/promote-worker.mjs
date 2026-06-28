#!/usr/bin/env node
// One-shot: seed fact_supports from existing facts, then recompute all trust tiers.
//   MEMORY_PG_DSN=... node bin/promote-worker.mjs
import { makePool } from "../src/db.mjs";
import { backfillFactSupports } from "../src/trust-backfill.mjs";
import { promoteFacts, promoteRecords } from "../src/promote.mjs";

const pool = makePool();
try {
  const bf = await backfillFactSupports(pool);
  await promoteRecords(pool);
  await promoteFacts(pool);
  const dist = await pool.query(
    "SELECT trust_tier, count(*) FROM facts GROUP BY 1 ORDER BY 2 DESC");
  console.log(`promote-worker: backfilled ${bf.inserted} supports`);
  for (const r of dist.rows) console.log(`  facts ${r.trust_tier}: ${r.count}`);
} finally {
  await pool.end();
}

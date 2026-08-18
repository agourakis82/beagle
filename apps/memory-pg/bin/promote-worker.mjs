#!/usr/bin/env node
// promote-worker.mjs — periodic trust-tier recompute.
//
// Usage:
//   MEMORY_PG_DSN=... node bin/promote-worker.mjs
//   MEMORY_PG_DSN=... node bin/promote-worker.mjs --full
//   MEMORY_PG_DSN=... node bin/promote-worker.mjs --initial-backfill
//   MEMORY_PG_DSN=... FULL_RECOMPUTE=1 node bin/promote-worker.mjs
//
// Flags:
//   --full / FULL_RECOMPUTE=1
//     Force the full-table path in both promoteFacts and promoteRecords, regardless
//     of any promote_watermarks row. Use weekly (e.g. via a separate CronJob schedule
//     or by rotating the env var) to catch deletions from fact_supports that the
//     incremental path cannot see (see demotion-guarantee caveat in src/promote.mjs).
//
//   --initial-backfill
//     Seed fact_supports from facts.source_record_id before promoting. Only needed
//     on the very first run or after a data-recovery event. The graph-worker now
//     populates fact_supports in real-time on normal cycles, so this is NOT run by
//     default (running it every cycle would re-hash 372K rows unnecessarily).

import { makePool } from "../src/db.mjs";
import { backfillFactSupports } from "../src/trust-backfill.mjs";
import { promoteFacts, promoteRecords } from "../src/promote.mjs";
import { measurePromoteFunnel, collapseStage } from "../src/promote-funnel.mjs";
import pg from "pg";

const args = process.argv.slice(2);
const full = args.includes("--full") || process.env.FULL_RECOMPUTE === "1";
const initialBackfill = args.includes("--initial-backfill");

const pool = makePool();
try {
  // Backfill fact_supports only when the table is empty (first run / recovery)
  // OR when --initial-backfill is explicitly requested. The graph-worker populates
  // fact_supports in real-time on normal cycles, so we do NOT run this every cycle.
  if (initialBackfill) {
    const bf = await backfillFactSupports(pool);
    console.log(`promote-worker: backfilled ${bf.inserted} supports (--initial-backfill)`);
  } else {
    const { rows } = await pool.query(
      "SELECT COUNT(*) AS n FROM fact_supports LIMIT 1");
    if (parseInt(rows[0].n, 10) === 0) {
      const bf = await backfillFactSupports(pool);
      console.log(`promote-worker: fact_supports was empty; backfilled ${bf.inserted} supports`);
    }
  }

  const mode = full ? "full" : "incremental";
  console.log(`promote-worker: running ${mode} promote cycle`);

  // Read the shared watermark ONCE before either function runs so both
  // promoteFacts and promoteRecords use the SAME baseline within this cycle.
  // If each function read it independently, the one that runs second would
  // see the freshly inserted watermark from the first function and miss items.
  const { rows: wmRows } = await pool.query(
    "SELECT MAX(ran_at) AS last_ran FROM promote_watermarks");
  const lastRan = wmRows[0]?.last_ran ?? null;

  const recordsUpdated = await promoteRecords(pool, { full, lastRan });
  const factsUpdated   = await promoteFacts(pool, { full, lastRan });

  console.log(
    `promote-worker: records_updated=${recordsUpdated} facts_updated=${factsUpdated} mode=${mode}`);

  const dist = await pool.query(
    "SELECT trust_tier, count(*) FROM facts GROUP BY 1 ORDER BY 2 DESC");
  for (const r of dist.rows) console.log(`  facts ${r.trust_tier}: ${r.count}`);

  // O funil, gravado a cada ciclo. Um zero em `corroborated` não distingue
  // critério exigente de extração parada; a série estágio a estágio distingue,
  // e nomeia onde caiu.
  const funnel = await measurePromoteFunnel(pool);
  console.log(`promote-worker: funil [${funnel.criterion}]`);
  console.log(`  fatos                ${funnel.facts_total}`);
  console.log(`  com apoio            ${funnel.with_support}`);
  console.log(`  com apoio do usuario ${funnel.with_user_support}`);
  console.log(`  apoio independente   ${funnel.independent_support}`);
  console.log(`  promovidos           ${funnel.promoted}`);
  const stage = collapseStage(funnel);
  if (stage) console.log(`  >> o funil zera em: ${stage}`);
} finally {
  await pool.end();
}

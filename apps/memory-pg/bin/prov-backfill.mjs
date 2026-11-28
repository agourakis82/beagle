#!/usr/bin/env node
// Entry point: classify historical record provenance once. Idempotent.
//   MEMORY_PG_DSN=... node bin/prov-backfill.mjs
import { makePool } from "../src/db.mjs";
import { backfillProvenance } from "../src/prov-backfill.mjs";

const pool = makePool();
try {
  const res = await backfillProvenance(pool);
  console.log(`prov-backfill: model_distilled=${res.distilled} external_import=${res.imported}`);
} finally {
  await pool.end();
}

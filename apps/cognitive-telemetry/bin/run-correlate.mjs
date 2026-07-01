#!/usr/bin/env node
// bin/run-correlate.mjs — Phase C wiring: join cognitive_telemetry (Tapestry's per-turn
// sedenion-derived measures — coherence/lr/zd/rupture) with the physiome daily series
// (HRV/sleep/resting HR/Kp/mood) by date, and run the cluster-robust correlation.
//
// This is glue only — dailyAggregate/correlateCognitivePhysiome (this app) and
// aggregateRange/flattenAggregates (physiome) already existed and were already correct;
// nothing wired them to real pools until now.
//
// Env:
//   MEMORY_PG_DSN     memory-pg connection, holds cognitive_telemetry (required)
//   PHYSIOME_PG_DSN   physiome connection, holds health_samples/weather_obs/space_weather (required)
// Usage:
//   node bin/run-correlate.mjs --days 30

import { makePool as makeMemoryPool } from "../../memory-pg/src/db.mjs";
import { makePool as makePhysiomePool } from "../../physiome/src/db.mjs";
import { aggregateRange } from "../../physiome/src/digest.mjs";
import { flattenAggregates } from "../../physiome/src/correlate.mjs";
import { dailyAggregate } from "../src/aggregate.mjs";
import { correlateCognitivePhysiome } from "../src/correlate-cog.mjs";

function arg(name, def) {
  const i = process.argv.indexOf(name);
  if (i === -1) return def;
  const v = process.argv[i + 1];
  return v && !v.startsWith("--") ? v : true;
}

async function main() {
  const memDsn = process.env.MEMORY_PG_DSN;
  if (!memDsn) throw new Error("MEMORY_PG_DSN is required");
  const physDsn = process.env.PHYSIOME_PG_DSN;
  if (!physDsn) throw new Error("PHYSIOME_PG_DSN is required");
  const days = Number(arg("--days", 30));

  const memPool = makeMemoryPool(memDsn);
  const physPool = makePhysiomePool(physDsn);

  try {
    const { rows } = await memPool.query(
      `SELECT occurred_at, coherence, lr, zd, rupture FROM cognitive_telemetry
       WHERE occurred_at IS NOT NULL ORDER BY occurred_at`,
    );
    console.log(`[run-correlate] cognitive_telemetry rows: ${rows.length}`);
    const cogDaily = dailyAggregate(rows);
    console.log(`[run-correlate] cognitive daily aggregates: ${cogDaily.length} day(s)`);

    const physAggs = await aggregateRange(physPool, days);
    const physFlat = flattenAggregates(physAggs);
    console.log(`[run-correlate] physiome daily aggregates: ${physFlat.length} day(s) (window=${days}d)`);

    const result = correlateCognitivePhysiome(cogDaily, physFlat);
    console.log(`[run-correlate] joined days=${result.days} minN=${result.minN}`);
    if (result.correlations.length === 0) {
      console.log("[run-correlate] no correlation pair reached minN yet — needs more overlapping days.");
    } else {
      for (const c of result.correlations) {
        const sig = c.robustSignificant ? " ROBUST" : "";
        console.log(
          `  ${c.cognitive} × ${c.physiome}: rho=${c.rho} CI=[${c.ciLo},${c.ciHi}] n=${c.n}${sig}`,
        );
      }
    }
    console.log(JSON.stringify(result, null, 2));
  } finally {
    await memPool.end();
    await physPool.end();
  }
}

main().catch((e) => {
  console.error(`[run-correlate] fatal: ${e.stack || e.message}`);
  process.exit(1);
});

#!/usr/bin/env node
// bin/import-healthkit.mjs — import a historical Apple Health Export into physiome.
//
// One-time: on the iPhone → Health → profile → "Export All Health Data" → unzip →
// apple_health_export/export.xml. Get it to where this runs, then:
//   PHYSIOME_PG_DSN=... node bin/import-healthkit.mjs --file export.xml
// Idempotent (deterministic uuid) — safe to re-run. Streams; handles GB-scale files.

import { createReadStream } from "node:fs";
import { makePool } from "../src/db.mjs";
import { importHealthExport } from "../src/healthkit-import.mjs";

function arg(name, def) {
  const i = process.argv.indexOf(name);
  if (i === -1) return def;
  const v = process.argv[i + 1];
  return v && !v.startsWith("--") ? v : true;
}

async function main() {
  const file = arg("--file");
  if (!file) throw new Error("provide --file <export.xml>");
  const pool = makePool();
  const t0 = Date.now();
  console.log(`[healthkit] importing ${file} …`);
  const stats = await importHealthExport(pool, createReadStream(file, "utf8"), {
    onProgress: (seen) => { if (seen % 50000 === 0) console.log(`[healthkit] seen ${seen} kept records`); },
  });
  console.log(`[healthkit] DONE in ${((Date.now() - t0) / 1000).toFixed(1)}s — kept=${stats.seen} inserted=${stats.inserted}`);
  // show the new day coverage
  const r = await pool.query("SELECT count(distinct ts::date)::int days, min(ts)::date mn, max(ts)::date mx FROM health_samples");
  console.log(`[healthkit] health_samples now spans ${r.rows[0].days} days (${r.rows[0].mn} .. ${r.rows[0].mx})`);
  await pool.end();
}

main().catch((e) => { console.error(`[healthkit] fatal: ${e.stack || e.message}`); process.exit(1); });

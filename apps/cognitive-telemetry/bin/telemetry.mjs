#!/usr/bin/env node
// bin/telemetry.mjs — Phase B runner: pull sessions → F telemetry → exocortex.
//
// Env:
//   MEMORY_PG_DSN          memory-pg connection (required)
//   COGTEL_EMBED_URL       bge-m3 embed endpoint (default the Spark tei-shim)
//   SOUNIO_REPO            sounio repo for souc (default /home/devsounio/sounio)
// Usage:
//   node bin/telemetry.mjs --jsonl /tmp/exo/conversation_passages.jsonl --limit 20

import { makePool } from "../../memory-pg/src/db.mjs"; // sibling app: shares pg + DSN helper
import { sessionsFromJsonl } from "../src/pull.mjs";
import { makeEmbed } from "../src/embed.mjs";
import { ensureTelemetrySchema } from "../src/writeback.mjs";
import { processSession } from "../src/pipeline.mjs";

function arg(name, def) {
  const i = process.argv.indexOf(name);
  if (i === -1) return def;
  const v = process.argv[i + 1];
  return v && !v.startsWith("--") ? v : true;
}

async function main() {
  const dsn = process.env.MEMORY_PG_DSN;
  if (!dsn) throw new Error("MEMORY_PG_DSN is required");
  const embedUrl = process.env.COGTEL_EMBED_URL || "http://192.168.3.43:8080/embed";
  const jsonl = arg("--jsonl");
  if (!jsonl) throw new Error("provide --jsonl <conversation_passages.jsonl>");
  const limit = Number(arg("--limit", 50));

  const pool = makePool(dsn);
  await ensureTelemetrySchema(pool);
  const embed = makeEmbed(embedUrl);

  let sessions = await sessionsFromJsonl(jsonl);
  console.log(`[telemetry] ${sessions.length} sessions in source; processing up to ${limit}`);
  sessions = sessions.slice(0, limit);

  let done = 0, turns = 0, written = 0, errors = 0;
  for (const s of sessions) {
    try {
      const r = await processSession(pool, s, { embed });
      done++; turns += r.turns; written += r.written;
      if (done % 10 === 0) console.log(`[telemetry] ${done}/${sessions.length} sessions, ${written} rows`);
    } catch (e) {
      errors++;
      console.error(`[telemetry] session ${s.session_id.slice(0, 12)} failed: ${e.message}`);
    }
  }
  console.log(`[telemetry] DONE sessions=${done} turns=${turns} rows=${written} errors=${errors}`);
  await pool.end();
}

main().catch((e) => {
  console.error(`[telemetry] fatal: ${e.stack || e.message}`);
  process.exit(1);
});

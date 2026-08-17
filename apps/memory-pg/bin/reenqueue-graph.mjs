#!/usr/bin/env node
// bin/reenqueue-graph.mjs — CLI do backfill pós-pane.
//
//   MEMORY_PG_DSN=... node bin/reenqueue-graph.mjs --since 2026-07-19
//   MEMORY_PG_DSN=... node bin/reenqueue-graph.mjs --since 2026-07-19 --apply --limit 2000
//
// Sem --apply apenas conta. O padrão é não mexer em nada.

import { makePool } from "../src/db.mjs";
import { reenqueueEmptyExtractions } from "../src/reenqueue-graph.mjs";

function arg(name, fallback = null) {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 && process.argv[i + 1] && !process.argv[i + 1].startsWith("--")
    ? process.argv[i + 1] : fallback;
}

const since = arg("since");
if (!since) {
  console.error("uso: --since <ISO> [--until <ISO>] [--limit N] [--apply]");
  console.error("  --since é obrigatório: é a janela da pane, não o corpus inteiro.");
  process.exit(2);
}
const until = arg("until");
const limitRaw = arg("limit");
const limit = limitRaw ? Number(limitRaw) : null;
const apply = process.argv.includes("--apply");

const pool = makePool();
try {
  const res = await reenqueueEmptyExtractions(pool, { since, until, apply, limit });
  console.log(`janela      : ${since} → ${until ?? "agora"}`);
  console.log(`candidatos  : ${res.candidates}  (marcados done, zero fatos)`);
  if (res.applied) {
    console.log(`reenfileirados: ${res.requeued}${limit ? ` (teto ${limit})` : ""}`);
    const left = res.candidates - res.requeued;
    if (left > 0) console.log(`restam      : ${left} — rode de novo para o próximo lote`);
  } else {
    console.log("simulação: nada foi alterado. Use --apply para reenfileirar.");
  }
} finally {
  await pool.end();
}

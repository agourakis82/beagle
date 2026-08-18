#!/usr/bin/env node
// bin/reenqueue-graph.mjs — CLI do backfill pós-pane.
//
//   node bin/reenqueue-graph.mjs --since 2026-07-19
//   node bin/reenqueue-graph.mjs --since 2026-07-19 --space personal --apply
//   node bin/reenqueue-graph.mjs --park-except personal --apply
//
// Sem --apply apenas conta. O padrão é não mexer em nada.

import { makePool } from "../src/db.mjs";
import { reenqueueEmptyExtractions, parkQueuedExcept } from "../src/reenqueue-graph.mjs";

function arg(name, fallback = null) {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 && process.argv[i + 1] && !process.argv[i + 1].startsWith("--")
    ? process.argv[i + 1] : fallback;
}

const apply = process.argv.includes("--apply");
const parkExcept = arg("park-except");
const roleArg = arg("role");
const pool = makePool();

try {
  if (parkExcept) {
    // Encolhe a fila para um único space. Reversível: o que sai volta a ser
    // encontrável por --since, porque o critério é "done, na janela, sem fatos".
    const res = await parkQueuedExcept(pool, { keepSpace: parkExcept, keepRole: roleArg, apply });
    console.log(`mantendo na fila : space='${parkExcept}'${roleArg ? ` role='${roleArg}'` : ''} -> ${res.kept} registros`);
    if (res.applied) {
      console.log(`estacionados     : ${res.parked} (voltam com --since quando for a vez)`);
    } else {
      console.log(`estacionaria     : ${res.candidates}`);
      console.log("simulação: nada foi alterado. Use --apply.");
    }
  } else {
    const since = arg("since");
    if (!since) {
      console.error("uso: --since <ISO> [--until <ISO>] [--space S] [--role R] [--limit N] [--apply]");
      console.error("     --park-except <space> [--role R] [--apply]");
      console.error("  --since é obrigatório: é a janela da pane, não o corpus inteiro.");
      process.exit(2);
    }
    const until = arg("until");
    const limitRaw = arg("limit");
    const limit = limitRaw ? Number(limitRaw) : null;
    const space = arg("space");
    const role = arg("role");

    const res = await reenqueueEmptyExtractions(pool, { since, until, apply, limit, space, role });
    console.log(`janela      : ${since} → ${until ?? "agora"}${space ? `   space='${space}'` : ""}${role ? `   role='${role}'` : ""}`);
    console.log(`candidatos  : ${res.candidates}  (marcados done, zero fatos)`);
    if (res.applied) {
      console.log(`reenfileirados: ${res.requeued}${limit ? ` (teto ${limit})` : ""}`);
      const left = res.candidates - res.requeued;
      if (left > 0) console.log(`restam      : ${left} — rode de novo para o próximo lote`);
    } else {
      console.log("simulação: nada foi alterado. Use --apply para reenfileirar.");
    }
  }
} finally {
  await pool.end();
}

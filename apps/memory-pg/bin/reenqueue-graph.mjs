#!/usr/bin/env node
// bin/reenqueue-graph.mjs — CLI do backfill pós-pane.
//
//   node bin/reenqueue-graph.mjs --since 2026-07-19
//   node bin/reenqueue-graph.mjs --since 2026-07-19 --space personal --apply
//   node bin/reenqueue-graph.mjs --park-except personal --apply
//
// Sem --apply apenas conta. O padrão é não mexer em nada.

import { makePool } from "../src/db.mjs";
import { reenqueueEmptyExtractions, parkQueuedExcept, requeueOversized, requeueFromDlq } from "../src/reenqueue-graph.mjs";

function arg(name, fallback = null) {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 && process.argv[i + 1] && !process.argv[i + 1].startsWith("--")
    ? process.argv[i + 1] : fallback;
}

const apply = process.argv.includes("--apply");
const oversized = process.argv.includes("--oversized");
const dlq = process.argv.includes("--dlq");
const parkExcept = arg("park-except");
const roleArg = arg("role");
const pool = makePool();

try {
  if (dlq) {
    // Traz de volta o que a fila morta guardou. `requeueFromDlq` existia em `src` desde o
    // conserto da DLQ e NUNCA teve entrada na CLI — mecanismo escrito sem caminho de chegada,
    // que e como 1.095 registros ficaram enterrados sem ninguem ter como tira-los de la.
    //
    // So volta o que nao tem fato nem linha na fila: reenfileirar o que ja foi extraido
    // duplicaria trabalho e, pior, poderia duplicar fato.
    const provActor = arg("prov-actor");
    const limitRaw = arg("limit");
    const res = await requeueFromDlq(pool, {
      provActor,
      limit: limitRaw ? Number(limitRaw) : null,
      apply,
    });
    console.log(`na fila morta, recuperaveis: ${res.candidates}${provActor ? ` (prov_actor=${provActor})` : ""}`);
    if (res.applied) console.log(`reenfileirados            : ${res.requeued}`);
    else console.log("simulacao: nada foi alterado. Use --apply.");
  } else if (oversized) {
    // Devolve o que ficou de fora por tamanho. `--max-chars` e um TETO DECLARADO: sem ele,
    // devolver tudo faria os grandes demais girarem e voltarem para a quarentena.
    const maxRaw = arg("max-chars");
    const limitRaw = arg("limit");
    const res = await requeueOversized(pool, {
      maxChars: maxRaw ? Number(maxRaw) : null,
      limit: limitRaw ? Number(limitRaw) : null,
      apply,
    });
    console.log(`em quarentena por tamanho: ${res.candidates}${maxRaw ? ` (ate ${maxRaw} caracteres)` : " (sem teto)"}`);
    if (res.applied) console.log(`reenfileirados           : ${res.requeued}`);
    else console.log("simulacao: nada foi alterado. Use --apply.");
  } else if (parkExcept) {
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

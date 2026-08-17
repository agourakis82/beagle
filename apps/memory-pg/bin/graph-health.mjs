#!/usr/bin/env node
// bin/graph-health.mjs — a extração está produzindo?
//
// O alarme que faltava. `memory-pg-capture-health` vigia a CAPTURA e esteve OK
// durante os 29 dias em que a EXTRAÇÃO estava morta — um alarme no lugar errado
// é pior que nenhum, porque dá sensação de cobertura.
//
//   MEMORY_PG_DSN=... node bin/graph-health.mjs [--window 3]
//
// Sai 1 quando alarma, para o Job aparecer como falho também.

import { makePool } from "../src/db.mjs";
import { graphHealth, avisar } from "../src/graph-health.mjs";

const i = process.argv.indexOf("--window");
const windowHours = i >= 0 && process.argv[i + 1] ? Number(process.argv[i + 1]) : 3;

const pool = makePool();
try {
  const h = await graphHealth(pool, { windowHours });
  console.log(
    `janela=${windowHours}h  fatos=${h.facts}  records_novos=${h.records}  ` +
    `fila=${h.pending}  dlq=${h.dlq}  ultimo_fato=${h.ultimoFato ?? "nunca"}`);

  if (h.ok) {
    console.log("OK: a extração está produzindo fatos.");
  } else {
    console.log("EXTRAÇÃO PARADA: " + h.motivo);
    await avisar(h.motivo);
    process.exitCode = 1;
  }

  // A DLQ não alarma sozinha: falha visível é o comportamento desejado, e um
  // punhado de timeouts é ruído normal. Fica no log para quem for investigar.
  if (h.dlq > 0) console.log(`  (${h.dlq} na DLQ nesta janela — ver failed_graph.last_error)`);
} finally {
  await pool.end();
}

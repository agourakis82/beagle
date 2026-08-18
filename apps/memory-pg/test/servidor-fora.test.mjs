// servidor-fora.test.mjs — o servidor sumir nao e defeito do registro.
//
// NAO e hipotetico. Em 18-ago-2026 uma janela de DOIS MINUTOS com o servidor de LLM fora do ar,
// durante um rollout, enterrou 1.095 registros validos na fila morta. Todos com o mesmo erro
// (`fetch failed`), todos no mesmo par de minutos, nenhum com problema nenhum.
//
// A causa era a politica, nao a pane: tres tentativas em rajada nao sao tres chances — sao a
// mesma chance repetida em dois segundos. Os tres workers reivindicavam o registro de volta no
// ciclo seguinte, em milissegundos, e o `retry_count` estourava antes de o pod terminar de subir.
//
// Agora espera. E o mesmo raciocinio da quarentena por tamanho, invertido: la repetir era inutil
// porque o resultado seria identico; aqui repetir FUNCIONA, so nao instantaneamente.

import { test, before, beforeEach, after } from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { makePool, ensureSchema } from "../src/db.mjs";
import { runGraphOnce } from "../src/graph-worker.mjs";
import { ehServidorFora, ServidorForaError } from "../src/graph-extract.mjs";

const DSN = process.env.MEMORY_PG_TEST_DSN;
if (!DSN) throw new Error("MEMORY_PG_TEST_DSN must be set");
const pool = makePool(DSN);

before(async () => { await ensureSchema(pool); });
beforeEach(async () => {
  await pool.query("TRUNCATE entities, facts, pending_graph, failed_graph, records CASCADE");
});
after(async () => { await pool.end(); });

async function enfileira(texto = "um registro qualquer") {
  const sha = createHash("sha256").update(texto + Math.random()).digest("hex");
  const r = await pool.query(
    "INSERT INTO records (source_type, content, content_sha256) VALUES ('note',$1,$2) RETURNING id",
    [texto, sha]);
  await pool.query("INSERT INTO pending_graph (record_id) VALUES ($1)", [r.rows[0].id]);
  return r.rows[0].id;
}

// A forma EXATA do erro real: o undici do Node devolve `fetch failed` com o codigo no `cause`.
const servidorForaLlm = async () => {
  const e = new Error("fetch failed");
  e.cause = { code: "ECONNREFUSED" };
  throw e;
};

test("reconhece transporte pelo codigo e pela mensagem", () => {
  const comCodigo = new Error("qualquer coisa");
  comCodigo.cause = { code: "ECONNREFUSED" };
  assert.equal(ehServidorFora(comCodigo), true);
  assert.equal(ehServidorFora(new Error("fetch failed")), true);
  assert.equal(ehServidorFora(new Error("router 500: upstream exploded")), false,
    "500 e resposta ruim, nao ausencia de resposta");
  assert.equal(ehServidorFora(null), false);
});

test("servidor fora NAO enterra e NAO gasta tentativa", async () => {
  const id = await enfileira();
  const stats = await runGraphOnce(pool, { llmFn: servidorForaLlm });

  assert.equal(stats.esperandoServidor, 1);
  assert.equal(stats.failed, 0);

  const dlq = await pool.query("SELECT count(*)::int n FROM failed_graph");
  assert.equal(dlq.rows[0].n, 0, "o registro nao tem defeito; a fila morta e o lugar errado");

  // `processing` com `locked_until` no futuro E a espera: a consulta de reivindicacao so
  // respeita `locked_until` neste ramo. Em `pending` o registro voltaria no mesmo instante.
  const q = await pool.query("SELECT status, retry_count, locked_until > now() AS esperando FROM pending_graph WHERE record_id=$1", [id]);
  assert.equal(q.rows[0].status, "processing");
  assert.equal(q.rows[0].esperando, true);
  assert.equal(q.rows[0].retry_count, 0, "tentativa gasta sem espera nao e tentativa");
});

test("a espera segura o registro: o ciclo seguinte nao o reivindica", async () => {
  // Este e o teste que representa a pane real. Sem o `locked_until`, os workers pegavam o mesmo
  // registro de volta em milissegundos e queimavam as 3 tentativas antes de o pod subir.
  await enfileira();
  await runGraphOnce(pool, { llmFn: servidorForaLlm });

  const segunda = await runGraphOnce(pool, { llmFn: servidorForaLlm });
  assert.equal(segunda.claimed, 0, "ainda dentro da espera");
});

test("passada a espera, ele volta a ser tentado — e da certo quando o servidor voltou", async () => {
  // Esperar so vale se a espera terminar. Um registro que espera para sempre foi enterrado com
  // outro nome.
  await enfileira("Demetrios builds Sounio.");
  await runGraphOnce(pool, { llmFn: servidorForaLlm, esperaServidorSegundos: 0 });

  const saudavel = async () => JSON.stringify({
    entities: [{ name: "Demetrios", type: "person" }],
    facts: [{ subject: "Demetrios", predicate: "builds", object_literal: "Sounio",
              statement: "Demetrios builds Sounio", confidence: 0.9 }],
  });
  const segunda = await runGraphOnce(pool, { llmFn: saudavel });
  assert.equal(segunda.claimed, 1);
  assert.equal(segunda.processed, 1);

  const q = await pool.query("SELECT count(*)::int n FROM pending_graph WHERE status='done'");
  assert.equal(q.rows[0].n, 1);
});

test("erro COMUM continua indo para a fila morta", async () => {
  // A guarda so vale se discrimina. Se toda falha virasse espera, uma pane de verdade — resposta
  // impossivel de parsear, modelo inexistente — giraria em silencio para sempre.
  const quebrado = async () => { throw new Error("router 500: No fallback model group found"); };
  const id = await enfileira();
  for (let i = 0; i < 4; i++) await runGraphOnce(pool, { llmFn: quebrado });

  const dlq = await pool.query("SELECT count(*)::int n FROM failed_graph WHERE record_id=$1", [id]);
  assert.equal(dlq.rows[0].n, 1);
});

test("ServidorForaError carrega o kind que a politica le", () => {
  assert.equal(new ServidorForaError("x").kind, "servidor_fora");
});

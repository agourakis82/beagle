// graph-worker.test.mjs — the drain loop had no test at all, which is how it
// ran 29 days emitting facts=0 on every cycle without anyone noticing.
//
// The failure mode was not a crash. extractGraph converted every error into an
// empty extraction, so the worker saw a successful run with nothing in it,
// marked the record done, and moved on. The queue drained perfectly. Nothing
// reached the DLQ. Nothing was logged. The only visible symptom was a counter
// reading zero, which looks exactly like a quiet corpus.
//
// So these tests assert the distinction the pipeline lost: a record whose
// extraction BROKE must not be marked done, and the reason must be recoverable.

import { test, before, beforeEach, after } from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { makePool, ensureSchema } from "../src/db.mjs";
import { runGraphOnce } from "../src/graph-worker.mjs";

const DSN = process.env.MEMORY_PG_TEST_DSN;
if (!DSN) throw new Error("MEMORY_PG_TEST_DSN must be set");
const pool = makePool(DSN);

before(async () => { await ensureSchema(pool); });
beforeEach(async () => {
  await pool.query("TRUNCATE entities, facts, pending_graph, failed_graph, records CASCADE");
});
after(async () => { await pool.end(); });

/** Insert a record and enqueue it for extraction, mirroring captureRecord. */
async function enqueue(content) {
  const sha = createHash("sha256").update(content).digest("hex");
  const r = await pool.query(
    "INSERT INTO records (source_type, content, content_sha256) VALUES ('note', $1, $2) RETURNING id",
    [content, sha],
  );
  const id = r.rows[0].id;
  await pool.query("INSERT INTO pending_graph (record_id) VALUES ($1)", [id]);
  return id;
}

const healthyLlm = async () => JSON.stringify({
  entities: [{ name: "Demetrios", type: "person" }, { name: "Sounio", type: "project" }],
  facts: [{ subject: "Demetrios", predicate: "builds", object: "Sounio",
            statement: "Demetrios builds Sounio", confidence: 0.9 }],
});

// The exact shape of the outage: the router answers, but with an error body.
const deadRouterLlm = async () => {
  throw new Error("router 500: No fallback model group found for original model_group=r1-distill-70b");
};

// The other half: the model answers with prose that carries no JSON at all.
const babblingLlm = async () => "I'm sorry, I can't help with that request.";

test("healthy LLM: record is processed, marked done, facts land", async () => {
  await enqueue("Demetrios builds Sounio.");
  const stats = await runGraphOnce(pool, { llmFn: healthyLlm });

  assert.equal(stats.claimed, 1);
  assert.equal(stats.processed, 1);
  assert.equal(stats.failed, 0);
  assert.ok(stats.facts >= 1, "at least one fact inserted");

  const q = await pool.query("SELECT status FROM pending_graph");
  assert.equal(q.rows[0].status, "done");
});

test("dead LLM: the record is NOT marked done and stays claimable", async () => {
  await enqueue("something worth extracting");
  const stats = await runGraphOnce(pool, { llmFn: deadRouterLlm });

  assert.equal(stats.claimed, 1);
  // The whole point: a broken extraction is not a processed record.
  assert.equal(stats.processed, 0, "a failed extraction must not count as processed");
  assert.equal(stats.facts, 0);

  const q = await pool.query("SELECT status, retry_count FROM pending_graph");
  assert.equal(q.rows[0].status, "pending", "must go back in the queue, not to done");
  assert.equal(q.rows[0].retry_count, 1);

  assert.ok(stats.errors.length === 1, "the failure is reported, not swallowed");
  assert.match(stats.errors[0], /router 500/);
});

test("babbling LLM: unparseable output is a failure, not an empty success", async () => {
  await enqueue("something worth extracting");
  const stats = await runGraphOnce(pool, { llmFn: babblingLlm });

  assert.equal(stats.processed, 0);
  const q = await pool.query("SELECT status FROM pending_graph");
  assert.equal(q.rows[0].status, "pending");
  assert.match(stats.errors[0], /unparseable/);
});

test("after maxRetries the record reaches the DLQ carrying its reason", async () => {
  await enqueue("something worth extracting");

  // maxRetries = 1: first run bumps retry_count to 1, second exceeds it.
  await runGraphOnce(pool, { llmFn: deadRouterLlm, maxRetries: 1 });
  const stats = await runGraphOnce(pool, { llmFn: deadRouterLlm, maxRetries: 1 });
  assert.equal(stats.failed, 1);

  const pend = await pool.query("SELECT count(*)::int n FROM pending_graph");
  assert.equal(pend.rows[0].n, 0, "removed from the live queue");

  const dlq = await pool.query("SELECT record_id, last_error FROM failed_graph");
  assert.equal(dlq.rowCount, 1);
  // A DLQ you can only count is a DLQ you cannot diagnose.
  assert.match(dlq.rows[0].last_error, /router 500/);
});

// A DLQ que so diz PORQUE ainda nao diz DESDE QUANDO.
//
// `created_at` e copiado da fila — hora do ENFILEIRAMENTO, nao da falha. Medido em producao
// (17-ago-2026): as 9 falhas ocorridas naquele dia carregavam created_at de 04-jul a 17-ago.
// Perguntar "quando isto comecou a quebrar?" pela DLQ dava a data errada por semanas.
//
// O teste faz a distincao doer: o registro e enfileirado com um created_at ANTIGO e falha
// AGORA. Se alguem voltar a copiar created_at para failed_at, ou preencher failed_at pelo
// default da tabela, esta asercao quebra.
test("a DLQ registra QUANDO falhou, nao quando foi enfileirado", async () => {
  await enqueue("something worth extracting");
  await pool.query("UPDATE pending_graph SET created_at = now() - interval '30 days'");

  await runGraphOnce(pool, { llmFn: deadRouterLlm, maxRetries: 1 });
  await runGraphOnce(pool, { llmFn: deadRouterLlm, maxRetries: 1 });

  const d = await pool.query(
    `SELECT created_at, failed_at,
            extract(epoch FROM (now() - failed_at)) seg_desde_falha,
            extract(epoch FROM (now() - created_at)) seg_desde_fila
       FROM failed_graph`);
  const r = d.rows[0];
  assert.ok(r.failed_at, "failed_at foi gravado");
  assert.ok(Number(r.seg_desde_falha) < 120, "a falha foi agora");
  assert.ok(Number(r.seg_desde_fila) > 86400, "o enfileiramento foi ha muito tempo");
  // As duas colunas respondem perguntas diferentes e nao podem colapsar numa so.
  assert.ok(Number(r.seg_desde_fila) - Number(r.seg_desde_falha) > 86400,
    "created_at mede espera na fila; failed_at mede quando quebrou");
});

test("well-formed but empty extraction is still a success", async () => {
  // Silence must be allowed to mean silence: a record with nothing in it is
  // processed and done, and that is not what the outage looked like.
  await enqueue("...");
  const emptyLlm = async () => JSON.stringify({ entities: [], facts: [] });
  const stats = await runGraphOnce(pool, { llmFn: emptyLlm });

  assert.equal(stats.processed, 1);
  assert.equal(stats.facts, 0);
  assert.equal(stats.errors.length, 0);
  const q = await pool.query("SELECT status FROM pending_graph");
  assert.equal(q.rows[0].status, "done");
});

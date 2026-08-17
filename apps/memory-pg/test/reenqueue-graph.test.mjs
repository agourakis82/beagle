// reenqueue-graph.test.mjs — o backfill que devolve à fila o que a pane engoliu.
//
// O risco desta ferramenta não é falhar: é acertar demais. Um registro sem fatos
// pode ser um registro sem nada a extrair, e uma seleção frouxa transformaria um
// conserto de 29 dias numa varredura de todo o corpus contra um modelo de 70B.
// Por isso a janela é obrigatória e a simulação é o padrão.

import { test, before, beforeEach, after } from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { makePool, ensureSchema } from "../src/db.mjs";
import { reenqueueEmptyExtractions } from "../src/reenqueue-graph.mjs";
import { resolveEntity } from "../src/graph.mjs";

const DSN = process.env.MEMORY_PG_TEST_DSN;
if (!DSN) throw new Error("MEMORY_PG_TEST_DSN must be set");
const pool = makePool(DSN);

before(async () => { await ensureSchema(pool); });
beforeEach(async () => { await pool.query("TRUNCATE entities, facts, pending_graph, records CASCADE"); });
after(async () => { await pool.end(); });

/** Registro + linha de fila já `done`, com data controlada. */
async function done(content, createdAt) {
  const sha = createHash("sha256").update(content).digest("hex");
  const r = await pool.query(
    "INSERT INTO records (source_type, content, content_sha256, created_at) VALUES ('note',$1,$2,$3) RETURNING id",
    [content, sha, createdAt],
  );
  const id = r.rows[0].id;
  await pool.query("INSERT INTO pending_graph (record_id, status) VALUES ($1,'done')", [id]);
  return id;
}

async function giveFact(recordId) {
  const { id: subj } = await resolveEntity(pool, { name: "X", type: "thing" });
  await pool.query(
    `INSERT INTO facts (subject_id, predicate, statement, source_record_id, content_sha256)
     VALUES ($1,'p','s',$2,$3)`,
    [subj, recordId, createHash("sha256").update(recordId).digest("hex")],
  );
}

const DENTRO = "2026-07-25T12:00:00Z";
const FORA = "2026-06-01T12:00:00Z";
const JANELA = "2026-07-19T00:00:00Z";

test("simulação é o padrão: conta os candidatos e não altera nada", async () => {
  await done("engolido", DENTRO);
  const res = await reenqueueEmptyExtractions(pool, { since: JANELA });

  assert.equal(res.candidates, 1);
  assert.equal(res.applied, false);
  assert.equal(res.requeued, 0);
  const q = await pool.query("SELECT status FROM pending_graph");
  assert.equal(q.rows[0].status, "done", "nada foi tocado sem --apply");
});

test("--apply devolve o registro à fila com as tentativas zeradas", async () => {
  const id = await done("engolido", DENTRO);
  await pool.query("UPDATE pending_graph SET retry_count = 2, last_error = 'antigo' WHERE record_id=$1", [id]);

  const res = await reenqueueEmptyExtractions(pool, { since: JANELA, apply: true });
  assert.equal(res.requeued, 1);

  const q = await pool.query("SELECT status, retry_count, last_error FROM pending_graph");
  assert.equal(q.rows[0].status, "pending");
  // A falha foi da infraestrutura, não deste registro: herdar tentativas o
  // mandaria para a DLQ cedo demais.
  assert.equal(q.rows[0].retry_count, 0);
  assert.equal(q.rows[0].last_error, null);
});

test("registro que JÁ produziu fato não é reprocessado", async () => {
  const id = await done("saudavel", DENTRO);
  await giveFact(id);

  const res = await reenqueueEmptyExtractions(pool, { since: JANELA, apply: true });
  assert.equal(res.candidates, 0);
  const q = await pool.query("SELECT status FROM pending_graph");
  assert.equal(q.rows[0].status, "done");
});

// A janela é a única coisa que separa "conserto da pane" de "reprocessa tudo".
test("fora da janela nada é tocado, mesmo sem fatos", async () => {
  await done("vazio antigo e legitimo", FORA);
  const res = await reenqueueEmptyExtractions(pool, { since: JANELA, apply: true });
  assert.equal(res.candidates, 0);
  const q = await pool.query("SELECT status FROM pending_graph");
  assert.equal(q.rows[0].status, "done");
});

test("--limit drena em lotes e informa o que sobra", async () => {
  await done("a", "2026-07-20T00:00:00Z");
  await done("b", "2026-07-21T00:00:00Z");
  await done("c", "2026-07-22T00:00:00Z");

  const res = await reenqueueEmptyExtractions(pool, { since: JANELA, apply: true, limit: 2 });
  assert.equal(res.candidates, 3);
  assert.equal(res.requeued, 2);

  const q = await pool.query("SELECT count(*)::int n FROM pending_graph WHERE status='pending'");
  assert.equal(q.rows[0].n, 2);
});

test("sem janela a ferramenta se recusa a rodar", async () => {
  await assert.rejects(() => reenqueueEmptyExtractions(pool, { apply: true }), /since/);
});

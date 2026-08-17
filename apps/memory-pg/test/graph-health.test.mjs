// graph-health.test.mjs — o alarme que faltava.
//
// A extracao passou 29 dias emitindo facts=0 e ninguem soube. Havia um alarme, e
// ele esteve OK o tempo todo: `capture-health` vigia a CAPTURA, que nunca parou.
// O que parou foi a etapa seguinte. Alarme no lugar errado e pior que nenhum,
// porque da sensacao de cobertura.
//
// O teste central aqui e o FALSO POSITIVO: zero fatos numa noite quieta, sem
// material novo, NAO pode tocar. Alarme que toca a toa e silenciado, e e assim
// que alarmes morrem — depois ninguem olha quando ele estiver certo.

import { test, before, beforeEach, after } from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { makePool, ensureSchema } from "../src/db.mjs";
import { resolveEntity } from "../src/graph.mjs";
import { graphHealth } from "../src/graph-health.mjs";

const DSN = process.env.MEMORY_PG_TEST_DSN;
if (!DSN) throw new Error("MEMORY_PG_TEST_DSN must be set");
const pool = makePool(DSN);

before(async () => { await ensureSchema(pool); });
beforeEach(async () => {
  await pool.query("TRUNCATE entities, facts, records, pending_graph, failed_graph CASCADE");
});
after(async () => { await pool.end(); });

/** Registro criado agora (dentro da janela) ou antigo (fora dela). */
async function record({ antigo = false } = {}) {
  const sha = createHash("sha256").update("r" + Math.random()).digest("hex");
  const r = await pool.query(
    `INSERT INTO records (source_type, content, content_sha256, created_at)
     VALUES ('note','x',$1, now() - ($2 || ' hours')::interval) RETURNING id`,
    [sha, antigo ? 48 : 0]);
  return r.rows[0].id;
}

async function fato(recordId) {
  const { id: subj } = await resolveEntity(pool, { name: "X", type: "thing" });
  const sha = createHash("sha256").update("f" + Math.random()).digest("hex");
  await pool.query(
    `INSERT INTO facts (subject_id, predicate, statement, source_record_id, content_sha256)
     VALUES ($1,'p','s',$2,$3)`, [subj, recordId, sha]);
}

const enfileirar = (id, status = "pending") =>
  pool.query("INSERT INTO pending_graph (record_id, status) VALUES ($1,$2)", [id, status]);

// A assinatura exata dos 29 dias: material entrando, nada saindo.
test("ALARMA quando entra material novo e nao sai fato nenhum", async () => {
  await record(); await record(); await record();
  const h = await graphHealth(pool, { windowHours: 3 });
  assert.equal(h.ok, false);
  assert.match(h.motivo, /3 registros novos/);
  assert.match(h.motivo, /ZERO fatos/);
});

// O falso positivo que mataria o alarme.
test("NAO alarma na noite quieta: sem material novo e sem fila", async () => {
  await record({ antigo: true });
  const h = await graphHealth(pool, { windowHours: 3 });
  assert.equal(h.ok, true, "zero fatos sem nada a extrair e correto, nao pane");
  assert.equal(h.motivo, null);
});

test("nao alarma quando ha fato na janela", async () => {
  const id = await record();
  await fato(id);
  const h = await graphHealth(pool, { windowHours: 3 });
  assert.equal(h.ok, true);
  assert.equal(h.facts, 1);
});

// O caso das replicas mortas: worker vivo, fila cheia, nada saindo. Nenhum
// registro novo precisa chegar para isso ser pane.
test("ALARMA com fila acumulada e nenhum fato, mesmo sem material novo", async () => {
  const id = await record({ antigo: true });
  await enfileirar(id);
  const h = await graphHealth(pool, { windowHours: 3 });
  assert.equal(h.ok, false);
  assert.match(h.motivo, /1 registros na fila/);
});

test("fila drenada e sem material novo continua sendo OK", async () => {
  const id = await record({ antigo: true });
  await enfileirar(id, "done");
  const h = await graphHealth(pool, { windowHours: 3 });
  assert.equal(h.ok, true);
});

// A DLQ nao alarma sozinha: falha VISIVEL e o comportamento desejado deste PR, e
// um punhado de timeouts e ruido normal. Ela informa, nao acusa.
test("DLQ e informada mas nao dispara o alarme", async () => {
  const id = await record();
  await fato(id);
  await enfileirar(id, "done");
  await pool.query(
    `INSERT INTO failed_graph (record_id, status, retry_count, created_at, last_error)
     VALUES ($1,'failed',4, now(), 'timeout')`, [id]);
  const h = await graphHealth(pool, { windowHours: 3 });
  assert.equal(h.ok, true, "houve fato: o pipeline esta vivo");
  assert.equal(h.dlq, 1, "mas a DLQ aparece no relatorio");
});

test("relata o ultimo fato conhecido, para dimensionar ha quanto tempo parou", async () => {
  const id = await record();
  await fato(id);
  await pool.query("UPDATE facts SET recorded_at = now() - interval '30 days'");
  const h = await graphHealth(pool, { windowHours: 3 });
  assert.equal(h.ok, false, "fato antigo nao conta como producao recente");
  assert.ok(h.ultimoFato, "mas o ultimo fato conhecido vai no aviso");
  assert.match(h.motivo, /último fato/);
});

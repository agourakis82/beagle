// promote-funnel.test.mjs — o funil que torna o colapso visível.
//
// Zero corroborados foi lido como rigor por semanas. Não era: o funil zera em
// 54.740 -> 0 porque nenhum fato tem sequer dois apoiadores `user_stated`. O
// critério de quórum nunca teve o que contar, e o número final não distinguia
// isso de extração parada nem de apoio que não acumula.

import { test, before, beforeEach, after } from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { makePool, ensureSchema } from "../src/db.mjs";
import { measurePromoteFunnel, collapseStage, CRITERION_ID } from "../src/promote-funnel.mjs";
import { resolveEntity } from "../src/graph.mjs";

const DSN = process.env.MEMORY_PG_TEST_DSN;
if (!DSN) throw new Error("MEMORY_PG_TEST_DSN must be set");
const pool = makePool(DSN);

before(async () => { await ensureSchema(pool); });
beforeEach(async () => {
  await pool.query("TRUNCATE entities, facts, fact_supports, records, promote_funnel CASCADE");
});
after(async () => { await pool.end(); });

async function mkRecord(actor, sessionId, day) {
  const sha = createHash("sha256").update(actor + sessionId + day + Math.random()).digest("hex");
  const r = await pool.query(
    `INSERT INTO records (source_type, content, content_sha256, prov_actor, metadata, created_at)
     VALUES ('note','c',$1,$2,$3::jsonb,$4) RETURNING id`,
    [sha, actor, JSON.stringify({ session_id: sessionId }), day],
  );
  return r.rows[0].id;
}

async function mkFact(recordId) {
  const { id: subj } = await resolveEntity(pool, { name: "Demetrios", type: "person" });
  const sha = createHash("sha256").update(String(Math.random())).digest("hex");
  const f = await pool.query(
    `INSERT INTO facts (subject_id, predicate, statement, source_record_id, content_sha256)
     VALUES ($1,'p','s',$2,$3) RETURNING id`,
    [subj, recordId, sha],
  );
  return f.rows[0].id;
}

const support = (factId, recordId) =>
  pool.query("INSERT INTO fact_supports (fact_id, source_record_id) VALUES ($1,$2)", [factId, recordId]);

test("o funil grava uma linha e carrega o identificador do critério", async () => {
  const out = await measurePromoteFunnel(pool);
  assert.equal(out.criterion, CRITERION_ID);
  const q = await pool.query("SELECT criterion, facts_total FROM promote_funnel");
  assert.equal(q.rowCount, 1);
  assert.equal(q.rows[0].criterion, CRITERION_ID);
});

// A forma exata do corpus real: muito apoio, um único apoiador por fato.
test("um só apoiador user_stated: o funil zera na independência", async () => {
  const rec = await mkRecord("user_stated", "s1", "2026-08-01");
  const fact = await mkFact(rec);
  await support(fact, rec);

  const f = await measurePromoteFunnel(pool);
  assert.equal(f.facts_total, 1);
  assert.equal(f.with_support, 1);
  assert.equal(f.with_user_support, 1);
  assert.equal(f.independent_support, 0);
  // O estágio nomeado é o diagnóstico, não o zero final.
  assert.equal(collapseStage(f), "independent_support");
});

test("dois apoiadores em sessões e dias distintos satisfazem o critério vigente", async () => {
  const r1 = await mkRecord("user_stated", "s1", "2026-08-01");
  const r2 = await mkRecord("user_stated", "s2", "2026-08-05");
  const fact = await mkFact(r1);
  await support(fact, r1);
  await support(fact, r2);

  const f = await measurePromoteFunnel(pool);
  assert.equal(f.with_user_support, 1);
  assert.equal(f.independent_support, 1);
  assert.equal(collapseStage(f), "promoted", "conta como independente, mas ainda não foi promovido");
});

// Repetição não é independência: a mesma sessão, no mesmo dia, é uma boca só.
test("dois apoios na MESMA sessão e dia não contam como independentes", async () => {
  const r1 = await mkRecord("user_stated", "s1", "2026-08-01");
  const r2 = await mkRecord("user_stated", "s1", "2026-08-01");
  const fact = await mkFact(r1);
  await support(fact, r1);
  await support(fact, r2);

  const f = await measurePromoteFunnel(pool);
  assert.equal(f.with_user_support, 1);
  assert.equal(f.independent_support, 0);
});

// A causa que o funil precisa separar do critério: apoio existe, mas nenhum é do
// usuário. Isso é proveniência, não quórum.
test("apoio só de model_generated zera antes, em with_user_support", async () => {
  const rec = await mkRecord("model_generated", "s1", "2026-08-01");
  const fact = await mkFact(rec);
  await support(fact, rec);

  const f = await measurePromoteFunnel(pool);
  assert.equal(f.with_support, 1);
  assert.equal(f.with_user_support, 0);
  assert.equal(collapseStage(f), "with_user_support");
});

test("record:false mede sem gravar", async () => {
  await measurePromoteFunnel(pool, { record: false });
  const q = await pool.query("SELECT count(*)::int n FROM promote_funnel");
  assert.equal(q.rows[0].n, 0);
});

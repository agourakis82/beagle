// occurred-at-imputed.test.mjs — a hora do evento veio do texto ou da fala?
//
// As duas valem, mas nao valem o mesmo. Medido nos auto-relatos sem hora:
//
//   "Estou ansioso hj"              presente — a hora da fala serve
//   "Peito apertado de angustia"    presente — serve
//   "acordei com o peito apertado"  ACORDOU HA HORAS — a hora da fala erra
//
// Com janela de +-60min contra a fisiologia, errar por horas nao e ruido: e
// confrontar o relato com o corpo de outro momento. Por isso a hora imputada e
// MARCADA. A Fase 5 escolhe se a aceita, e essa escolha so existe se a distincao
// estiver gravada.

import { test, before, beforeEach, after } from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { makePool, ensureSchema } from "../src/db.mjs";
import { applyExtraction } from "../src/graph-extract.mjs";

const DSN = process.env.MEMORY_PG_TEST_DSN;
if (!DSN) throw new Error("MEMORY_PG_TEST_DSN must be set");
const pool = makePool(DSN);
const FALANTE = { role: "user", prov_actor: "user_stated" };
const FALA_EM = "2026-08-03T02:19:00.000Z";

before(async () => { await ensureSchema(pool); });
beforeEach(async () => { await pool.query("TRUNCATE entities, facts, records CASCADE"); });
after(async () => { await pool.end(); });

async function mkRecord() {
  const sha = createHash("sha256").update("r" + Math.random()).digest("hex");
  return (await pool.query(
    `INSERT INTO records (source_type, content, content_sha256, occurred_at)
     VALUES ('ConversationPassage','x',$1,$2) RETURNING id`, [sha, FALA_EM])).rows[0].id;
}

const fato = (over = {}) => ({
  subject: "Demetrios", predicate: "feels", statement: "estou ansioso",
  self_report: true, state_channel: "arousal", ...over,
});

test("hora vinda da fala e' marcada como imputada", async () => {
  const rid = await mkRecord();
  await applyExtraction(pool,
    { entities: [{ name: "Demetrios", type: "person" }], facts: [fato()] },
    { recordId: rid, speaker: FALANTE, occurredAt: FALA_EM, model: "m" });

  const q = await pool.query("SELECT occurred_at, occurred_at_imputed FROM facts");
  assert.equal(new Date(q.rows[0].occurred_at).toISOString(), FALA_EM);
  assert.equal(q.rows[0].occurred_at_imputed, true, "nao veio do texto");
});

test("hora declarada no texto NAO e' imputada", async () => {
  const rid = await mkRecord();
  const ontem = "2026-08-02T06:00:00.000Z";
  await applyExtraction(pool,
    { entities: [{ name: "Demetrios", type: "person" }],
      facts: [fato({ occurred_at: ontem })] },
    { recordId: rid, speaker: FALANTE, occurredAt: FALA_EM, model: "m" });

  const q = await pool.query("SELECT occurred_at, occurred_at_imputed FROM facts");
  assert.equal(new Date(q.rows[0].occurred_at).toISOString(), ontem);
  assert.equal(q.rows[0].occurred_at_imputed, false);
});

// Sem hora em lugar nenhum nao ha o que imputar — e a marca nao pode mentir
// dizendo que houve.
test("sem hora no registro, nada e' imputado", async () => {
  const sha = createHash("sha256").update("s" + Math.random()).digest("hex");
  const rid = (await pool.query(
    "INSERT INTO records (source_type, content, content_sha256) VALUES ('note','x',$1) RETURNING id",
    [sha])).rows[0].id;
  await applyExtraction(pool,
    { entities: [{ name: "Demetrios", type: "person" }], facts: [fato()] },
    { recordId: rid, speaker: FALANTE, model: "m" });

  const q = await pool.query("SELECT occurred_at, occurred_at_imputed FROM facts");
  // occurred_at cai para now() no INSERT (COALESCE), mas a marca acompanha a
  // origem: nao houve hora de fala para herdar.
  assert.equal(q.rows[0].occurred_at_imputed, false);
});

// A consulta que a Fase 5 vai querer: so horas declaradas.
test("da para separar declaradas de imputadas na consulta", async () => {
  const r1 = await mkRecord();
  const r2 = await mkRecord();
  await applyExtraction(pool,
    { entities: [{ name: "Demetrios", type: "person" }], facts: [fato()] },
    { recordId: r1, speaker: FALANTE, occurredAt: FALA_EM, model: "m" });
  await applyExtraction(pool,
    { entities: [{ name: "Demetrios", type: "person" }],
      facts: [fato({ statement: "outro", occurred_at: "2026-08-01T10:00:00Z" })] },
    { recordId: r2, speaker: FALANTE, occurredAt: FALA_EM, model: "m" });

  const q = await pool.query(
    `SELECT occurred_at_imputed imp, count(*)::int n FROM facts
      WHERE self_report AND occurred_at IS NOT NULL GROUP BY 1 ORDER BY 1`);
  assert.deepEqual(q.rows, [{ imp: false, n: 1 }, { imp: true, n: 1 }]);
});

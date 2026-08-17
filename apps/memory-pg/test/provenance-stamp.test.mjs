// provenance-stamp.test.mjs — quem extraiu vai junto do fato, carimbado pelo
// sistema.
//
// Duas coisas motivaram isto, e a segunda e' mais grave que a primeira.
//
// A pratica: para saber qual modelo produziu o primeiro auto-relato com canal,
// foi preciso cruzar `facts.recorded_at` com a data de criacao dos ReplicaSets do
// worker. Funcionou porque a janela era limpa — o fato caiu 18 minutos depois da
// troca. Nao e' auditoria; e' inferencia por coincidencia de horario.
//
// A grave: a coluna `provenance` recebia `f.provenance`, o objeto que o PROPRIO
// MODELO emitiu. Num sistema cuja tese inteira e' que uma alegacao carrega como
// veio a ser acreditada, o extrator estava assinando o proprio atestado. O que o
// modelo diz sobre si agora fica em quarentena sob `model_claimed`; o topo e'
// escrito por quem observou a chamada.

import { test, before, beforeEach, after } from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { makePool, ensureSchema } from "../src/db.mjs";
import { applyExtraction, stampProvenance } from "../src/graph-extract.mjs";

const DSN = process.env.MEMORY_PG_TEST_DSN;
if (!DSN) throw new Error("MEMORY_PG_TEST_DSN must be set");
const pool = makePool(DSN);

before(async () => { await ensureSchema(pool); });
beforeEach(async () => { await pool.query("TRUNCATE entities, facts, records CASCADE"); });
after(async () => { await pool.end(); });

async function mkRecord(content) {
  const sha = createHash("sha256").update(content + Math.random()).digest("hex");
  const r = await pool.query(
    "INSERT INTO records (source_type, content, content_sha256) VALUES ('note',$1,$2) RETURNING id",
    [content, sha],
  );
  return r.rows[0].id;
}

const umFato = (over = {}) => ({
  subject: "Demetrios", predicate: "felt_tense", object_literal: "sim",
  statement: "estava tenso no plantão", self_report: true, state_channel: "arousal",
  occurred_at: "2026-08-10T22:00:00Z", ...over,
});

test("o modelo que extraiu fica gravado no fato", async () => {
  const rid = await mkRecord("estava tenso");
  await applyExtraction(pool,
    { entities: [{ name: "Demetrios", type: "person" }], facts: [umFato()] },
    { recordId: rid, model: "qwen2.5-coder:32b" });

  const q = await pool.query("SELECT provenance FROM facts");
  assert.equal(q.rows[0].provenance.extracted_by.model, "qwen2.5-coder:32b");
  assert.ok(q.rows[0].provenance.extracted_by.at, "carrega o instante da extracao");
});

// O ponto central: o modelo nao pode forjar a propria proveniencia.
test("o modelo NAO consegue forjar extracted_by", async () => {
  const rid = await mkRecord("tentativa de forja");
  await applyExtraction(pool,
    { entities: [{ name: "Demetrios", type: "person" }],
      facts: [umFato({ provenance: { extracted_by: { model: "modelo-que-eu-inventei" } } })] },
    { recordId: rid, model: "qwen2.5-coder:32b" });

  const p = (await pool.query("SELECT provenance FROM facts")).rows[0].provenance;
  assert.equal(p.extracted_by.model, "qwen2.5-coder:32b", "vale o que o sistema observou");
  assert.equal(p.model_claimed.extracted_by.model, "modelo-que-eu-inventei",
    "o que ele alegou fica visivel, mas em quarentena");
});

test("o que o modelo alega e' preservado, so que separado", async () => {
  const rid = await mkRecord("x");
  await applyExtraction(pool,
    { entities: [{ name: "Demetrios", type: "person" }],
      facts: [umFato({ provenance: { inferido: true, base: "frase anterior" } })] },
    { recordId: rid, model: "m1" });

  const p = (await pool.query("SELECT provenance FROM facts")).rows[0].provenance;
  assert.equal(p.model_claimed.inferido, true);
  assert.equal(p.model_claimed.base, "frase anterior");
  assert.equal(p.extracted_by.model, "m1");
});

test("sem alegacao do modelo, so o carimbo do sistema", async () => {
  const rid = await mkRecord("x");
  await applyExtraction(pool,
    { entities: [{ name: "Demetrios", type: "person" }], facts: [umFato()] },
    { recordId: rid, model: "m1" });

  const p = (await pool.query("SELECT provenance FROM facts")).rows[0].provenance;
  assert.equal(p.model_claimed, undefined);
  assert.equal(p.extracted_by.model, "m1");
});

test("sem modelo informado o campo fica null, nunca ausente", async () => {
  // Um fato sem modelo declarado tem de ser distinguivel de um fato antigo,
  // anterior ao carimbo — por isso null explicito, e nao a chave faltando.
  const rid = await mkRecord("x");
  await applyExtraction(pool,
    { entities: [{ name: "Demetrios", type: "person" }], facts: [umFato()] },
    { recordId: rid });

  const p = (await pool.query("SELECT provenance FROM facts")).rows[0].provenance;
  assert.ok("extracted_by" in p);
  assert.equal(p.extracted_by.model, null);
});

test("stampProvenance ignora alegacao que nao e' objeto", () => {
  for (const lixo of ["texto", 42, ["a"], null, undefined]) {
    const p = stampProvenance(lixo, { model: "m" });
    assert.equal(p.model_claimed, undefined, `descarta ${JSON.stringify(lixo)}`);
    assert.equal(p.extracted_by.model, "m");
  }
});

// A consulta que a auditoria vai querer fazer.
test("da para contar auto-relatos com canal POR modelo", async () => {
  const r1 = await mkRecord("a");
  const r2 = await mkRecord("b");
  await applyExtraction(pool,
    { entities: [{ name: "Demetrios", type: "person" }], facts: [umFato()] },
    { recordId: r1, model: "qwen2.5-coder:32b" });
  await applyExtraction(pool,
    { entities: [{ name: "Demetrios", type: "person" }],
      facts: [umFato({ statement: "outro", state_channel: null })] },
    { recordId: r2, model: "r1-distill-70b" });

  const q = await pool.query(
    `SELECT provenance->'extracted_by'->>'model' m,
            count(*) FILTER (WHERE state_channel IS NOT NULL)::int com_canal,
            count(*)::int total
       FROM facts WHERE self_report GROUP BY 1 ORDER BY 1`);
  assert.deepEqual(q.rows, [
    { m: "qwen2.5-coder:32b", com_canal: 1, total: 1 },
    { m: "r1-distill-70b", com_canal: 0, total: 1 },
  ]);
});

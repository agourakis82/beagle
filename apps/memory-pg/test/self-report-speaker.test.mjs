// self-report-speaker.test.mjs — um auto-relato so vale se quem falou for O SUJEITO.
//
// Medido em producao antes de escrever isto: os QUATRO primeiros auto-relatos com
// canal que chegaram ao banco vinham de registros `role=assistant`,
// `prov_actor=model_generated`. Eram o companion falando:
//
//   "o corpo esta mais acelerado que o de costume"   (descrevendo a cena)
//   "nao tenho humor, tenho postura"                 (falando de SI MESMO)
//   "voce me disse que estava irritado comigo"       (lembrando o que ELE disse)
//
// O "self" do auto-relato era a maquina. Corroborar isso contra a fisiologia dele
// seria confrontar a prosa do companion com a HRV de um humano.
//
// A proporcao torna a guarda obrigatoria e nao cosmetica: na fila pessoal ha
// 3.072 registros `assistant` para 31 `user`. Sem isto, ~99% do "substrato" da
// Fase 2 seria a propria voz do sistema voltando como evidencia sobre o corpo.

import { test, before, beforeEach, after } from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { makePool, ensureSchema } from "../src/db.mjs";
import { applyExtraction, speakerIsSubject } from "../src/graph-extract.mjs";

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

const fatoDele = {
  subject: "Demetrios", predicate: "felt_tense", object_literal: "sim",
  statement: "estava tenso no plantão", self_report: true, state_channel: "arousal",
  occurred_at: "2026-08-10T22:00:00Z",
};

async function aplicar(speaker) {
  const rid = await mkRecord("texto " + Math.random());
  await applyExtraction(pool,
    { entities: [{ name: "Demetrios", type: "person" }], facts: [fatoDele] },
    { recordId: rid, model: "m", speaker });
  return (await pool.query("SELECT self_report, state_channel FROM facts")).rows[0];
}

test("fala do companion NAO vira auto-relato, por mais convincente que pareca", async () => {
  const r = await aplicar({ role: "assistant", prov_actor: "model_generated" });
  assert.equal(r.self_report, false, "o self do auto-relato nao pode ser a maquina");
  assert.equal(r.state_channel, null, "sem canal: nao e' corroboravel contra a fisiologia dele");
});

test("fala dele vira auto-relato com canal", async () => {
  const r = await aplicar({ role: "user", prov_actor: "user_stated" });
  assert.equal(r.self_report, true);
  assert.equal(r.state_channel, "arousal");
});

// Sem role declarado, o ator do registro decide.
test("sem role, prov_actor=user_stated e' aceito", async () => {
  const r = await aplicar({ role: null, prov_actor: "user_stated" });
  assert.equal(r.self_report, true);
});

test("sem role, model_generated e' recusado", async () => {
  const r = await aplicar({ role: null, prov_actor: "model_generated" });
  assert.equal(r.self_report, false);
});

// Quem nao sabe de quem e' a fala nao pode autorizar uma alegacao sobre o estado
// dele. O silencio do chamador nao pode virar permissao.
test("chamador sem speaker recusa por omissao", async () => {
  const rid = await mkRecord("sem speaker");
  await applyExtraction(pool,
    { entities: [{ name: "Demetrios", type: "person" }], facts: [fatoDele] },
    { recordId: rid, model: "m" });
  const r = (await pool.query("SELECT self_report, state_channel FROM facts")).rows[0];
  assert.equal(r.self_report, false);
  assert.equal(r.state_channel, null);
});

// O fato em si sobrevive — muda o que ele PODE sustentar, nao se existe.
test("o fato continua gravado, so deixa de ser auto-relato", async () => {
  const rid = await mkRecord("companion falando");
  await applyExtraction(pool,
    { entities: [{ name: "Demetrios", type: "person" }], facts: [fatoDele] },
    { recordId: rid, model: "m", speaker: { role: "assistant" } });
  const q = await pool.query("SELECT statement, self_report FROM facts");
  assert.equal(q.rowCount, 1, "o fato nao e' descartado");
  assert.equal(q.rows[0].statement, "estava tenso no plantão");
  assert.equal(q.rows[0].self_report, false);
});

test("speakerIsSubject: role manda sobre prov_actor", () => {
  // Um registro com role=assistant e' do companion mesmo que o ator diga outra
  // coisa: role e' a declaracao mais especifica sobre quem falou.
  assert.equal(speakerIsSubject({ role: "assistant", prov_actor: "user_stated" }), false);
  assert.equal(speakerIsSubject({ role: "user", prov_actor: "model_generated" }), true);
  assert.equal(speakerIsSubject({ role: "USER" }), true, "case-insensitive");
  assert.equal(speakerIsSubject({ role: " user " }), true, "tolera espaco");
  assert.equal(speakerIsSubject({ role: "system" }), false);
  assert.equal(speakerIsSubject({}), false, "sem nada, recusa");
});

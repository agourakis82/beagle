// self-report.test.mjs — Fase 2: o substrato da corroboração multimodal.
//
// Medido antes de escrever isto: dos 54.739 fatos `user_stated` do corpus, os
// predicados dominantes são `contains`, `has_field`, `implements`. São fatos
// sobre código. Só 63 mencionam corpo ou afeto. O extrator nunca foi instruído a
// capturar estado próprio, então não capturou — e uma medida fisiológica não tem
// o que corroborar.
//
// Duas coisas passam a ser declaradas na extração, nunca inferidas depois:
// se o fato é um auto-relato, e QUAL grandeza mensurável poderia testá-lo.
// Inferir isso a posteriori a partir do texto seria alimentar o juízo com
// inferência de máquina — exatamente o que a quarentena de proveniência existe
// para impedir.

import { test, before, beforeEach, after } from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { makePool, ensureSchema } from "../src/db.mjs";
import { applyExtraction, buildExtractionPrompt, SELF_STATE_CHANNELS, coerceTimestamp } from "../src/graph-extract.mjs";

const DSN = process.env.MEMORY_PG_TEST_DSN;
if (!DSN) throw new Error("MEMORY_PG_TEST_DSN must be set");
const pool = makePool(DSN);

before(async () => { await ensureSchema(pool); });
beforeEach(async () => { await pool.query("TRUNCATE entities, facts, records CASCADE"); });
after(async () => { await pool.end(); });

async function mkRecord(content) {
  const sha = createHash("sha256").update(content + Math.random()).digest("hex");
  const r = await pool.query(
    "INSERT INTO records (source_type, content, content_sha256) VALUES ('note', $1, $2) RETURNING id",
    [content, sha],
  );
  return r.rows[0].id;
}

const selfFact = (over = {}) => ({
  subject: "Demetrios", predicate: "slept_badly", object_literal: "4h",
  statement: "Demetrios dormiu mal na noite do plantão",
  occurred_at: "2026-08-10T06:00:00Z",
  self_report: true, state_channel: "sleep", ...over,
});

test("o prompt instrui auto-relato, canal e tempo do EVENTO", () => {
  const p = buildExtractionPrompt("dormi mal");
  assert.match(p, /SELF-REPORTS/);
  assert.match(p, /self_report=true/);
  for (const c of SELF_STATE_CHANNELS) assert.ok(p.includes(c), `canal ${c} citado no prompt`);
  // A distinção que faz a corroboração ser por evento, e não por tema.
  assert.match(p, /WHEN THE STATE HAPPENED, not when it was said/);
  // Sem tempo, o fato não deve existir — melhor perder o fato que inventar a hora.
  assert.match(p, /omit the fact rather/);
});

test("auto-relato com canal é persistido com self_report e state_channel", async () => {
  const rid = await mkRecord("dormi mal");
  await applyExtraction(pool, { entities: [{ name: "Demetrios", type: "person" }], facts: [selfFact()] },
    { recordId: rid });

  const q = await pool.query("SELECT self_report, state_channel, occurred_at FROM facts");
  assert.equal(q.rowCount, 1);
  assert.equal(q.rows[0].self_report, true);
  assert.equal(q.rows[0].state_channel, "sleep");
  assert.ok(q.rows[0].occurred_at, "corroboração é por evento: sem occurred_at não há o que casar");
});

// O modelo propõe, o esquema decide. Se ele pudesse cunhar um canal, poderia
// inventar em silêncio uma espécie nova de evidência.
test("canal fora do vocabulário fechado é descartado, não gravado", async () => {
  const rid = await mkRecord("astrologia");
  await applyExtraction(pool,
    { entities: [{ name: "Demetrios", type: "person" }],
      facts: [selfFact({ state_channel: "signo_solar", statement: "canal inventado" })] },
    { recordId: rid });

  const q = await pool.query("SELECT self_report, state_channel FROM facts");
  assert.equal(q.rows[0].self_report, true, "continua sendo auto-relato");
  assert.equal(q.rows[0].state_channel, null, "mas sem canal: não é corroborável por medida");
});

test("fato sobre código não vira auto-relato", async () => {
  const rid = await mkRecord("o parser usa recursive descent");
  await applyExtraction(pool,
    { entities: [{ name: "parser", type: "system" }, { name: "recursive_descent", type: "concept" }],
      facts: [{ subject: "parser", predicate: "uses", object: "recursive_descent",
                statement: "o parser usa recursive descent" }] },
    { recordId: rid });

  const q = await pool.query("SELECT self_report, state_channel FROM facts");
  assert.equal(q.rows[0].self_report, false);
  assert.equal(q.rows[0].state_channel, null);
});

// state_channel só tem sentido preso a um auto-relato: um canal num fato sobre o
// mundo abriria a porta para medir o corpo dele e chamar isso de evidência sobre
// outra coisa.
test("canal sem auto-relato é descartado", async () => {
  const rid = await mkRecord("x");
  await applyExtraction(pool,
    { entities: [{ name: "Demetrios", type: "person" }],
      facts: [selfFact({ self_report: false })] },
    { recordId: rid });

  const q = await pool.query("SELECT self_report, state_channel FROM facts");
  assert.equal(q.rows[0].self_report, false);
  assert.equal(q.rows[0].state_channel, null);
});

test("o índice da Fase 2 encontra auto-relatos com canal e tempo", async () => {
  const rid = await mkRecord("mistura");
  await applyExtraction(pool,
    { entities: [{ name: "Demetrios", type: "person" }],
      facts: [
        selfFact(),
        selfFact({ predicate: "felt_tense", state_channel: "arousal",
                   statement: "estava tenso no plantão", occurred_at: "2026-08-11T22:00:00Z" }),
        selfFact({ predicate: "felt_tense", state_channel: null, occurred_at: null,
                   statement: "sem canal e sem hora" }),
      ] },
    { recordId: rid });

  const q = await pool.query(
    `SELECT state_channel FROM facts
      WHERE self_report AND state_channel IS NOT NULL AND occurred_at IS NOT NULL
      ORDER BY state_channel`);
  assert.deepEqual(q.rows.map((r) => r.state_channel), ["arousal", "sleep"]);
});

// Achado em producao na primeira hora depois do conserto: o modelo devolveu
// occurred_at="cinco e quinze". Sob o codigo antigo isso seria mais um facts=0
// mudo; com o erro visivel, virou um bug consertavel.
test("instante em prosa vira null e o fato sobrevive", async () => {
  const rid = await mkRecord("dormi mal");
  await applyExtraction(pool,
    { entities: [{ name: "Demetrios", type: "person" }],
      facts: [selfFact({ occurred_at: "cinco e quinze" })] },
    { recordId: rid });

  const q = await pool.query("SELECT occurred_at, state_channel FROM facts");
  assert.equal(q.rowCount, 1, "o fato nao pode ser perdido por causa de um campo");
  assert.equal(q.rows[0].occurred_at, null);
  assert.equal(q.rows[0].state_channel, "sleep");
});

test("coerceTimestamp: aceita instante, recusa prosa e ano absurdo", () => {
  assert.equal(coerceTimestamp("2026-08-10T06:00:00Z"), "2026-08-10T06:00:00.000Z");
  assert.equal(coerceTimestamp("cinco e quinze"), null);
  assert.equal(coerceTimestamp(""), null);
  assert.equal(coerceTimestamp(null), null);
  assert.equal(coerceTimestamp("0001-01-01T00:00:00Z"), null, "ano absurdo = alucinacao de formato");
});

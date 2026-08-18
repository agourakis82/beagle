// judge.test.mjs — o último elo: aplicar a regra congelada e gravar o veredito.
//
// O risco aqui não é errar um julgamento: é o julgador virar placar de vitórias. Se ele só
// gravasse o que concorda, contar linhas daria 100% de acerto por construção. Metade destes
// testes existe para garantir que DISCORDA e INCONCLUSIVO chegam ao banco.

import { test, before, beforeEach, after } from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { makePool, ensureSchema } from "../src/db.mjs";
import { resolveEntity } from "../src/graph.mjs";
import { judgeAll } from "../src/judge.mjs";
import { PREREG_VERSION, PREREG_SHA256 } from "../src/agreement.mjs";

const DSN = process.env.MEMORY_PG_TEST_DSN;
if (!DSN) throw new Error("MEMORY_PG_TEST_DSN must be set");
const pool = makePool(DSN);

const RAIZ = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const PREREG = join(RAIZ, "docs", "PREREG_FASE2_DIRECAO_v1.md");
const HR = "HKQuantityTypeIdentifierHeartRate";
const SDNN = "HKQuantityTypeIdentifierHeartRateVariabilitySDNN";

before(async () => { await ensureSchema(pool); });
beforeEach(async () => {
  await pool.query("TRUNCATE entities, facts, fact_measurements, fact_agreement CASCADE");
});
after(async () => { await pool.end(); });

/** Auto-relato pronto para confronto + a medida que o testa. */
async function relato({ channel = "arousal", polarity = "alta", pct = 0.95,
                        measure = HR, n = 5, baselineN = 100, independent = true } = {}) {
  const { id: subj } = await resolveEntity(pool, { name: "ele", type: "person" });
  const sha = createHash("sha256").update("f" + Math.random()).digest("hex");
  const f = await pool.query(
    `INSERT INTO facts (subject_id, predicate, statement, content_sha256,
                        self_report, state_channel, state_polarity, occurred_at)
     VALUES ($1,'estava','uma sentenca',$2,true,$3,$4, now()) RETURNING id`,
    [subj, sha, channel, polarity]);
  const id = f.rows[0].id;
  await pool.query(
    `INSERT INTO fact_measurements
       (fact_id, channel, measure_type, window_minutes, n_samples, baseline_pct,
        baseline_n, independent, mapping_version)
     VALUES ($1,$2,$3,60,$4,$5,$6,$7,'physio-map-v1')`,
    [id, channel, measure, n, pct, baselineN, independent]);
  return id;
}

test("simulacao e o padrao: conta e nao grava", async () => {
  await relato();
  const r = await judgeAll(pool, { prereg: PREREG });
  assert.equal(r.candidatos, 1);
  assert.equal(r.contagem.CONCORDA, 1);
  assert.equal(r.applied, false);
  const q = await pool.query("SELECT count(*)::int n FROM fact_agreement");
  assert.equal(q.rows[0].n, 0, "nada gravado sem --apply");
});

test("com apply, o veredito e gravado com versao E hash do pre-registro", async () => {
  await relato();
  const r = await judgeAll(pool, { prereg: PREREG, apply: true });
  assert.equal(r.gravados, 1);
  const q = await pool.query("SELECT * FROM fact_agreement");
  assert.equal(q.rows[0].verdict, "CONCORDA");
  assert.equal(q.rows[0].prereg_version, PREREG_VERSION);
  // O hash na LINHA, nao so no codigo: quem ler isto daqui a um ano precisa poder verificar
  // sob qual texto exato o veredito saiu, sem confiar no arquivo do repositorio.
  assert.equal(q.rows[0].prereg_sha256, PREREG_SHA256);
});

// 🚨 O teste que impede o julgador de virar placar de vitorias.
test("DISCORDA e gravado, nao descartado", async () => {
  await relato({ pct: 0.02 });   // ativado, mas FC na cauda BAIXA
  const r = await judgeAll(pool, { prereg: PREREG, apply: true });
  assert.equal(r.contagem.DISCORDA, 1);
  const q = await pool.query("SELECT verdict, motivo FROM fact_agreement");
  assert.equal(q.rows[0].verdict, "DISCORDA");
  assert.match(q.rows[0].motivo, /cauda inferior/);
});

test("INCONCLUSIVO tambem chega ao banco — ausencia de evidencia e um dado", async () => {
  await relato({ pct: 0.5 });
  await judgeAll(pool, { prereg: PREREG, apply: true });
  const q = await pool.query("SELECT verdict FROM fact_agreement");
  assert.equal(q.rows[0].verdict, "INCONCLUSIVO");
});

test("os tres vereditos convivem numa mesma rodada", async () => {
  await relato({ pct: 0.95 });   // CONCORDA
  await relato({ pct: 0.02 });   // DISCORDA
  await relato({ pct: 0.50 });   // INCONCLUSIVO
  const r = await judgeAll(pool, { prereg: PREREG, apply: true });
  assert.equal(r.contagem.CONCORDA, 1);
  assert.equal(r.contagem.DISCORDA, 1);
  assert.equal(r.contagem.INCONCLUSIVO, 1);
  assert.equal(r.gravados, 3);
});

// 🚨 Julgar sob uma regra que mudou sem ninguem declarar seria pior que nao julgar: produziria
// numeros com aparencia de rigor.
test("pre-registro alterado FAZ o julgamento parar", async () => {
  await relato();
  await assert.rejects(
    () => judgeAll(pool, { prereg: join(RAIZ, "README.md"), apply: true }),
    /pré-registro ALTERADO/);
  const q = await pool.query("SELECT count(*)::int n FROM fact_agreement");
  assert.equal(q.rows[0].n, 0, "nada foi gravado sob regra nao verificada");
});

test("rejulgar sob a MESMA regra nao duplica nem reescreve", async () => {
  await relato();
  await judgeAll(pool, { prereg: PREREG, apply: true });
  const segunda = await judgeAll(pool, { prereg: PREREG, apply: true });
  assert.equal(segunda.gravados, 0, "ON CONFLICT DO NOTHING");
  const q = await pool.query("SELECT count(*)::int n FROM fact_agreement");
  assert.equal(q.rows[0].n, 1);
});

// Sem sinal nao ha o que confrontar — e o candidato nem entra na consulta.
test("auto-relato sem polaridade nao vira candidato", async () => {
  const id = await relato();
  await pool.query("UPDATE facts SET state_polarity = NULL WHERE id = $1", [id]);
  const r = await judgeAll(pool, { prereg: PREREG });
  assert.equal(r.candidatos, 0);
});

// A mesma boca com dois microfones nao pode produzir veredito conclusivo.
test("medida nao independente nao concorda nem discorda", async () => {
  await relato({ independent: false });
  const r = await judgeAll(pool, { prereg: PREREG, apply: true });
  assert.equal(r.contagem.CONCORDA, 0);
  assert.equal(r.contagem.DISCORDA, 0);
  const q = await pool.query("SELECT verdict FROM fact_agreement");
  assert.equal(q.rows[0].verdict, "INELEGIVEL");
});

test("secundaria concordante e contada como reforco", async () => {
  const id = await relato({ pct: 0.95 });                       // primaria CONCORDA
  await pool.query(
    `INSERT INTO fact_measurements
       (fact_id, channel, measure_type, window_minutes, n_samples, baseline_pct,
        baseline_n, independent, mapping_version)
     VALUES ($1,'arousal',$2,60,5,0.05,100,true,'physio-map-v1')`, [id, SDNN]);
  await judgeAll(pool, { prereg: PREREG, apply: true });
  const q = await pool.query("SELECT verdict, reforco FROM fact_agreement");
  assert.equal(q.rows[0].verdict, "CONCORDA");
  assert.equal(q.rows[0].reforco, 1);
});

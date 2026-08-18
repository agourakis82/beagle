// agreement.test.mjs — a regra congelada do pré-registro `direcao-v2`.
//
// O risco de um julgador de concordância não é errar: é NUNCA DISCORDAR. Uma regra que só
// sabe confirmar transforma qualquer dado em apoio, e o funil vira um carimbo. Metade destes
// testes existe para provar que ela falha quando deve.

import { test } from "node:test";
import assert from "node:assert/strict";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import {
  julgar, julgarRelato, verificarPrereg, DIRECOES, PREREG_VERSION, PREREG_SHA256,
} from "../src/agreement.mjs";

const RAIZ = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const DOC = join(RAIZ, "docs", "PREREG_FASE2_DIRECAO_v2.md");

const HR = "HKQuantityTypeIdentifierHeartRate";
const SDNN = "HKQuantityTypeIdentifierHeartRateVariabilitySDNN";
const RR = "HKQuantityTypeIdentifierRespiratoryRate";
const SONO = "HKCategoryTypeIdentifierSleepAnalysis";

/** Linha de fact_measurements elegível por padrão; sobrescreva o que o teste precisa. */
const med = (o = {}) => ({
  channel: "arousal", measure_type: HR, n_samples: 5, baseline_pct: 0.9,
  baseline_n: 100, independent: true, ...o,
});

// 🚨 O documento congelado E o codigo tem que continuar dizendo a mesma coisa. Se alguem
// editar o pre-registro sem versionar, isto quebra — que e o unico jeito de um pre-registro
// significar algo.
test("o pre-registro no disco bate com o hash congelado no codigo", async () => {
  const r = await verificarPrereg(DOC);
  assert.equal(r.sha256, PREREG_SHA256);
  assert.equal(r.versao, PREREG_VERSION);
});

test("documento alterado FAZ o julgamento parar, nao seguir em silencio", async () => {
  await assert.rejects(() => verificarPrereg(join(RAIZ, "README.md")), /pré-registro ALTERADO/);
});

// --- A direção, nos dois sentidos ---

test("ativado + FC na cauda ALTA => CONCORDA", () => {
  const j = julgar(med({ baseline_pct: 0.95 }), "alta");
  assert.equal(j.veredito, "CONCORDA");
  assert.equal(j.papel, "primaria");
});

// 🚨 O teste que impede a regra de virar carimbo.
test("ativado + FC na cauda BAIXA => DISCORDA", () => {
  const j = julgar(med({ baseline_pct: 0.05 }), "alta");
  assert.equal(j.veredito, "DISCORDA");
});

test("calmo + FC na cauda BAIXA => CONCORDA (a direcao inverte com a polaridade)", () => {
  const j = julgar(med({ baseline_pct: 0.05 }), "baixa");
  assert.equal(j.veredito, "CONCORDA");
});

test("dormiu MAL + sono curto => CONCORDA; dormiu mal + sono longo => DISCORDA", () => {
  const base = { channel: "sleep", measure_type: SONO };
  assert.equal(julgar(med({ ...base, baseline_pct: 0.10 }), "baixa").veredito, "CONCORDA");
  assert.equal(julgar(med({ ...base, baseline_pct: 0.95 }), "baixa").veredito, "DISCORDA");
});

// --- A faixa central ---

// Morno NAO e apoio. Colapsar [0,30–0,70] em "nao discorda" transformaria ruido em
// confirmacao — e como quase toda medida cai no meio, isso sozinho inventaria corroboracao.
test("percentil no meio => INCONCLUSIVO, nunca CONCORDA", () => {
  for (const p of [0.31, 0.5, 0.69]) {
    assert.equal(julgar(med({ baseline_pct: p }), "alta").veredito, "INCONCLUSIVO");
  }
});

test("os limiares sao estritos nas bordas", () => {
  assert.equal(julgar(med({ baseline_pct: 0.70 }), "alta").veredito, "INCONCLUSIVO");
  assert.equal(julgar(med({ baseline_pct: 0.71 }), "alta").veredito, "CONCORDA");
});

// --- Elegibilidade ---

// A mesma boca com dois microfones. HKStateOfMindType e ELE declarando o proprio humor.
test("medida NAO independente e inelegivel", () => {
  const j = julgar(med({ independent: false }), "alta");
  assert.equal(j.veredito, "INELEGIVEL");
  assert.match(j.motivo, /nao independente/);
});

test("valence, pain e oncall sao inelegiveis por construcao", () => {
  for (const c of ["valence", "pain", "oncall"]) {
    const j = julgar(med({ channel: c }), "alta");
    assert.equal(j.veredito, "INELEGIVEL");
    assert.match(j.motivo, /excluido por construcao/);
  }
  for (const c of ["valence", "pain", "oncall"]) {
    assert.equal(DIRECOES[c], undefined, `${c} nao pode ter direcao`);
  }
});

test("sem cobertura no instante => INELEGIVEL, e isso nao e concordancia", () => {
  assert.equal(julgar(med({ n_samples: 0 }), "alta").veredito, "INELEGIVEL");
});

test("linha de base curta => INELEGIVEL (percentil de punhado nao e percentil)", () => {
  assert.equal(julgar(med({ baseline_n: 29 }), "alta").veredito, "INELEGIVEL");
  assert.equal(julgar(med({ baseline_n: 30 }), "alta").veredito, "CONCORDA");
});

// 🚨 O estado de TODO o corpus quando o pre-registro foi congelado: `facts` guardava o canal
// e nao o sinal. Sem polaridade nao ha o que confrontar — e e justamente por isso que estas
// direcoes nao puderam ser ajustadas a dados ja vistos.
test("auto-relato sem polaridade e INELEGIVEL", () => {
  for (const p of [null, undefined, "", "meh"]) {
    const j = julgar(med(), p);
    assert.equal(j.veredito, "INELEGIVEL");
    assert.match(j.motivo, /sem polaridade/);
  }
});

// --- Primária vs secundária ---

test("exploratoria nunca conta", () => {
  const j = julgar(med({ channel: "sleep", measure_type: RR, baseline_pct: 0.99 }), "alta");
  assert.equal(j.veredito, "EXPLORATORIO");
});

// 🚨 Deixar qualquer medida do canal decidir seria escolher, depois do fato, a que deu certo.
test("secundaria NAO salva quando a primaria discorda", () => {
  const r = julgarRelato([
    med({ measure_type: HR, baseline_pct: 0.05 }),           // primaria: DISCORDA
    med({ measure_type: SDNN, baseline_pct: 0.02 }),          // secundaria: concordaria
  ], "alta");
  assert.equal(r.veredito, "DISCORDA", "quem decide e a primaria");
});

test("secundaria REFORCA quando concorda com a primaria", () => {
  const r = julgarRelato([
    med({ measure_type: HR, baseline_pct: 0.95 }),            // primaria: CONCORDA
    med({ measure_type: SDNN, baseline_pct: 0.05 }),          // secundaria: SDNN baixa
  ], "alta");
  assert.equal(r.veredito, "CONCORDA");
  assert.equal(r.reforco, 1);
});

test("sem primaria nao ha veredito, mesmo com secundaria perfeita", () => {
  const r = julgarRelato([med({ measure_type: SDNN, baseline_pct: 0.01 })], "alta");
  assert.equal(r.veredito, "INELEGIVEL");
  assert.match(r.motivo, /sem medida primaria/);
});

test("todo veredito carrega a versao do pre-registro", () => {
  assert.equal(julgar(med(), "alta").versao, "direcao-v2");
  assert.equal(julgarRelato([med()], "alta").versao, "direcao-v2");
});

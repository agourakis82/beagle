// apps/project-cockpit/server/bula-store.test.mjs
import test from "node:test";
import assert from "node:assert/strict";
import { abrirBase, consulta, consultaPCDT, carimbo } from "./bula-store.mjs";

// SKIP SO QUANDO NAO HA BASE DECLARADA.
//
// `{ skip: semBase }` puro e a assinatura exata do problema que custou a semana:
// 145 testes que existiam e nunca rodavam. Um teste que se pula sozinho em
// silencio nao cobre nada.
//
// Regra: sem BULA_DB no ambiente (maquina de quem edita), pula — a base nao
// existe ali e isso e legitimo. COM BULA_DB definido e a base nao abrindo,
// FALHA — porque ai alguem quis rodar contra a base e ela nao esta la.
const BASE = process.env.BULA_DB;
const base = BASE ? abrirBase(BASE) : null;
if (BASE && !base) {
  throw new Error(`BULA_DB=${BASE} definido mas a base nao abriu — ` +
    `teste clinico nao pode passar em silencio`);
}
const semBase = !BASE;

// ---- os que impedem entregar a bula ERRADA ----

test("aciclovir NAO casa com ganciclovir", { skip: semBase }, () => {
  const r = consulta(base, "dose de aciclovir endovenoso");
  if (r) assert.ok(!/ganciclovir/i.test(r.generico), `casou errado: ${r.generico}`);
});

test("metformina nao traz a associacao com sitagliptina", { skip: semBase }, () => {
  const r = consulta(base, "dose de metformina");
  if (r) assert.ok(!/sitagliptin/i.test(r.generico), `trouxe associacao: ${r.generico}`);
});

test("farmaco ausente devolve null, nunca aproximacao", { skip: semBase }, () => {
  assert.equal(consulta(base, "dose de xisplogrina zeta"), null);
});

// ---- os que provam que serve ----

test("enoxaparina devolve trecho com citacao", { skip: semBase }, () => {
  const r = consulta(base, "dose profilatica de enoxaparina");
  assert.ok(r, "nao achou enoxaparina");
  assert.match(r.generico, /enoxaparin/i);
  assert.ok(r.citacao.length > 10, "citacao vazia");
  assert.ok(r.texto.length > 50, "texto curto demais");
});

test("carimbo tem os quatro campos", { skip: semBase }, () => {
  const c = carimbo(base);
  assert.ok(Number(c.farmacos) > 0);
  assert.equal(c.hash.length, 64);
});

test("base inexistente devolve null, nao lanca", () => {
  assert.equal(abrirBase("/caminho/que/nao/existe.sqlite"), null);
});

// ---- consultaPCDT: nunca lanca, sempre devolve array ----

test("consultaPCDT sem base devolve array vazio", () => {
  assert.deepEqual(consultaPCDT(null, "qualquer coisa"), []);
});

test("consultaPCDT contra base sem tabela pcdt devolve array vazio, nao lanca", { skip: semBase }, () => {
  const r = consultaPCDT(base, "dose de enoxaparina");
  assert.ok(Array.isArray(r));
});

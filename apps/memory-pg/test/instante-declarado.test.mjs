// instante-declarado.test.mjs — a data que o modelo inventa quando o texto so da a hora.
//
// Sob a `direcao-v2` so hora DECLARADA entra no confronto. Isso torna o instante declarado o
// unico caminho para o funil — e portanto o unico lugar onde uma alucinacao vira evidencia.
//
// O caso abaixo NAO e hipotetico. Medido em 18-ago-2026 contra o servidor de producao
// (qwen2.5-14b-l4 na L4 do r770), com o prompt vigente:
//
//   entrada : "Hoje acordei as 5h20 com o peito apertado e muita angustia."
//   saida   : occurred_at = "2023-10-04T05:20:00Z"
//
// Hora certa, data tres anos no passado. Sem esta guarda, esse fato entraria como hora
// declarada e seria confrontado contra a fisiologia de 2023.
//
// A mesma sonda mostrou que o prompt NAO e omisso: com a data no texto
// ("Ontem, 17 de agosto de 2026, as 22h30") ele devolveu o instante correto, e nos controles
// (presente puro, evento sem hora) devolveu null como deveria. O defeito e a data inventada,
// nao a falta de extracao.

import { test } from "node:test";
import assert from "node:assert/strict";
import { instanteDeclaradoPlausivel, JANELA_INSTANTE_DIAS } from "../src/graph-extract.mjs";

const FALA = "2026-08-18T08:20:00Z";

test("recusa a data alucinada do caso real (2023 contra uma fala de 2026)", () => {
  const r = instanteDeclaradoPlausivel("2023-10-04T05:20:00Z", FALA);
  assert.equal(r.ok, false);
  assert.match(r.motivo, /dias da fala/);
});

test("aceita o instante quando o texto deu a data", () => {
  // "Ontem, 17 de agosto de 2026, as 22h30" com a fala em 18-ago.
  const r = instanteDeclaradoPlausivel("2026-08-17T22:30:00Z", FALA);
  assert.equal(r.ok, true);
  assert.equal(r.at, "2026-08-17T22:30:00Z");
});

test("aceita o mesmo dia, algumas horas antes", () => {
  const r = instanteDeclaradoPlausivel("2026-08-18T05:20:00Z", FALA);
  assert.equal(r.ok, true);
});

test("sem ancora NAO da para validar, e a resposta e recusar", () => {
  // Confiar aqui deixaria passar justamente o caso que a guarda existe para pegar. O custo de
  // recusar e perder um caso; o de confiar e um instante inventado parecer declarado.
  const r = instanteDeclaradoPlausivel("2023-10-04T05:20:00Z", null);
  assert.equal(r.ok, false);
  assert.match(r.motivo, /sem ancora/);
});

test("instante ausente nao e o mesmo que instante recusado", () => {
  assert.equal(instanteDeclaradoPlausivel(null, FALA).motivo, "ausente");
});

test("instante ilegivel nao passa", () => {
  assert.equal(instanteDeclaradoPlausivel("cinco e quinze", FALA).ok, false);
});

test("a borda da janela e simetrica: futuro tambem e recusado", () => {
  // Um relato de estado que aponta para depois da fala e tao implausivel quanto um de 2023.
  const futuro = new Date(Date.parse(FALA) + (JANELA_INSTANTE_DIAS + 1) * 86400000).toISOString();
  assert.equal(instanteDeclaradoPlausivel(futuro, FALA).ok, false);
});

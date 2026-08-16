import { test } from "node:test";
import assert from "node:assert/strict";
import { direcaoDeAtuacao, quadrante, anotar, semDirecao, VALIDADE_MS }
  from "../server/direcao-de-atuacao.mjs";

const AGORA = Date.parse("2026-08-16T03:00:00Z");
const fresco = new Date(AGORA - 60_000).toISOString();
const velho  = new Date(AGORA - VALIDADE_MS - 1000).toISOString();

// --- O QUE IMPEDE A MENTIRA -------------------------------------------------

test("sem vetor a direcao e NEUTRA e marcada como declarada, nunca uma emocao chutada", () => {
  const d = direcaoDeAtuacao({ agora: AGORA });
  assert.equal(d.procedencia, "declarado");
  assert.equal(d.quadrante, null);
});

test("vetor VELHO nao dirige: corpo de duas horas atras nao descreve o agora", () => {
  const d = direcaoDeAtuacao({ valencia: -0.8, ativacao: 0.9, medidoEm: velho, agora: AGORA });
  assert.equal(d.procedencia, "declarado");
  assert.equal(d.quadrante, null, "nao pode afirmar 'aflito' com medida vencida");
});

test("um eixo faltando ja e insuficiente — nao se completa vetor por conta propria", () => {
  const so = direcaoDeAtuacao({ valencia: -0.8, medidoEm: fresco, agora: AGORA });
  assert.equal(so.procedencia, "declarado");
});

test("vetor medido e fresco dirige, e diz que foi observado", () => {
  const d = direcaoDeAtuacao({ valencia: -0.7, ativacao: 0.85, medidoEm: fresco, agora: AGORA });
  assert.equal(d.procedencia, "observado");
  assert.equal(d.quadrante, "aflito");
  assert.match(d.direcao, /lento|baixa/);
});

// --- OS QUADRANTES ----------------------------------------------------------

test("os quatro quadrantes do circumplexo", () => {
  assert.equal(quadrante(-0.7, 0.9), "aflito");
  assert.equal(quadrante(-0.7, 0.1), "abatido");
  assert.equal(quadrante( 0.7, 0.9), "aceso");
  assert.equal(quadrante( 0.7, 0.1), "sereno");
});

test("valencia neutra nao vira emocao: cai em alerta/quieto pela ativacao", () => {
  assert.equal(quadrante(0.0, 0.9), "alerta");
  assert.equal(quadrante(0.0, 0.1), "quieto");
  assert.equal(quadrante(0.0, 0.5), "estável");
});

// --- A ARMADILHA DO GUARDA --------------------------------------------------

test("semDirecao tira os colchetes — SEM ISTO o guarda descartaria todo audio dirigido", () => {
  const { anotado } = anotar("Respira comigo.", { valencia: -0.7, ativacao: 0.9, medidoEm: fresco, agora: AGORA });
  assert.ok(anotado.startsWith("["), "a direcao vai como prefixo entre colchetes");
  assert.equal(semDirecao(anotado), "Respira comigo.",
    "comparar contra ISTO, nunca contra o texto anotado");
});

test("multiplas marcacoes no meio da frase tambem saem", () => {
  assert.equal(semDirecao("[baixa] Ei. [pausa] Estou aqui."), "Ei. Estou aqui.");
});

test("texto sem marcacao passa intacto", () => {
  assert.equal(semDirecao("Estou aqui."), "Estou aqui.");
});

test("a anotacao NAO altera as palavras que serao ditas", () => {
  const t = "Você dormiu quatro horas e meia.";
  for (const v of [{ valencia: -0.9, ativacao: 0.9 }, { valencia: 0.9, ativacao: 0.1 }, {}]) {
    const { anotado } = anotar(t, { ...v, medidoEm: fresco, agora: AGORA });
    assert.equal(semDirecao(anotado), t, "o vetor muda a ENTREGA, nunca o texto");
  }
});

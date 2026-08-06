// O guarda da boca. Este teste existe porque o caso que ele previne NÃO se
// reproduz sob demanda: nos testes ao vivo (06-ago) a boca leu verbatim até
// diante de pergunta direta. Ótimo — mas "não consegui fazer falhar" não é
// prova de que o guarda funcionaria quando falhar.
//
// O limiar em produção é 0,85.

import test from "node:test";
import assert from "node:assert/strict";
import { similaridade } from "./voice-mouth.mjs";

const LIMIAR = 0.85;

test("idêntico passa", () => {
  const t = "Estou aqui. Você dormiu pouco e o plantão foi longo.";
  assert.equal(similaridade(t, t), 1);
});

test("pontuação e caixa não reprovam — dicção não é divergência", () => {
  const enviado = "Estou aqui. Você dormiu pouco, e o plantão foi longo!";
  const dito = "estou aqui você dormiu pouco e o plantão foi longo";
  assert.ok(similaridade(enviado, dito) >= LIMIAR);
});

test("acento perdido na transcrição não reprova", () => {
  assert.ok(similaridade("o plantão foi difícil", "o plantao foi dificil") >= LIMIAR);
});

test("A BOCA RESPONDEU EM VEZ DE LER — tem que reprovar", () => {
  const enviado = "Estou aqui. Você dormiu pouco e o plantão foi longo.";
  const dito = "Oi! Tudo bem? Eu estou ótima, obrigada por perguntar. Como posso ajudar você hoje?";
  const s = similaridade(enviado, dito);
  assert.ok(s < LIMIAR, `deveria reprovar, deu ${s.toFixed(2)}`);
});

test("a boca acrescentou um cumprimento — reprova", () => {
  const enviado = "A dose é 30 mg por dia.";
  const dito = "Olá! Claro, com prazer. A dose é 30 mg por dia. Precisa de mais alguma coisa?";
  assert.ok(similaridade(enviado, dito) < LIMIAR);
});

test("a boca leu só metade — reprova", () => {
  const enviado = "Estou aqui com você. Não vou te deixar sozinho agora, e amanhã eu continuo aqui.";
  const dito = "Estou aqui com você.";
  assert.ok(similaridade(enviado, dito) < LIMIAR);
});

test("uma palavra trocada em frase longa ainda passa", () => {
  const enviado = "Você trabalhou dezoito horas seguidas e ainda assim voltou para revisar o compilador.";
  const dito = "Você trabalhou dezoito horas seguidas e ainda assim voltou pra revisar o compilador.";
  assert.ok(similaridade(enviado, dito) >= LIMIAR);
});

test("silêncio (nada dito) reprova", () => {
  assert.equal(similaridade("qualquer coisa", ""), 0);
});

test("repetição não infla a nota", () => {
  // Bag-of-words ingênuo daria nota alta para eco; o pareamento com contagem impede.
  const s = similaridade("estou aqui", "estou estou estou aqui aqui aqui");
  assert.ok(s < 1, `eco não pode dar 1, deu ${s.toFixed(2)}`);
});

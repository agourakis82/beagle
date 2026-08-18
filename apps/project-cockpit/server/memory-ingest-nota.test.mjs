// memory-ingest-nota.test.mjs — nota avulsa: ele diz algo e ninguem responde.
//
// Toda a espinha de memoria pressupunha troca conversacional. `/ingest` exigia
// userText E assistantText, entao uma captura rapida do widget — que e uma nota
// solta — batia num 400 e morria. Medido: das superficies do app, so o chat do
// `companion-ios` gravava fala dele; voz e widget nao apareciam como
// prov_surface nenhuma.
//
// E nota avulsa e justamente o formato mais provavel de um auto-relato: "peito
// apertado", "dormi mal", dito as tres da manha sem querer conversa. Sem ela, o
// substrato da Fase 2 depende de ele estar disposto a conversar.

import { test } from "node:test";
import assert from "node:assert/strict";
import {
  buildVerbatimPayload, handleIngestRequest, ingestPersonalTurn,
} from "./memory-ingest.mjs";

test("o contrato de entrada aceita nota sem resposta", async () => {
  let recebido = null;
  const r = await handleIngestRequest(
    { userText: "peito apertado" },
    { ingestFn: async (x) => { recebido = x; }, tokenFn: null });
  assert.equal(r.status, 202);
  assert.equal(recebido.userText, "peito apertado");
  // `clean()` normaliza ausencia para string vazia; o que importa e ser falsy,
  // porque e assim que todo o caminho abaixo testa.
  assert.ok(!recebido.assistantText, "sem lado do companion");
});

test("sem texto dele nao ha o que capturar", async () => {
  const r = await handleIngestRequest({ assistantText: "so a maquina falando" }, {});
  assert.equal(r.status, 400);
  assert.match(r.body.error, /userText required/);
});

// O turno do assistente e OMITIDO, nunca preenchido com vazio: um turno fantasma
// do companion no historico seria a voz da maquina entrando onde nao deve.
test("a nota nao inventa turno do companion", () => {
  const p = buildVerbatimPayload({ userText: "dormi mal", sessionId: "s1" });
  assert.equal(p.turns.length, 1);
  assert.equal(p.turns[0].role, "user");
  assert.ok(!p.turns.some((t) => t.role === "assistant"), "sem turno fantasma");
});

test("com os dois lados continua sendo um par", () => {
  const p = buildVerbatimPayload({ userText: "oi", assistantText: "oi voce" });
  assert.deepEqual(p.turns.map((t) => t.role), ["user", "assistant"]);
});

/** Coleta o que a ingestao gravaria, sem tocar em rede. */
async function capturar(entrada) {
  const gravados = [];
  let destilou = false;
  await ingestPersonalTurn(entrada, {
    captureFn: async (rec) => { gravados.push(rec); return { id: "r1" }; },
    distillFn: async () => { destilou = true; return ["atomo"]; },
    fetchImpl: async () => ({ ok: true, json: async () => ({}) }),
    tokenFn: null,
  });
  return { gravados, destilou };
}

test("a nota grava UM registro, dele, com hora", async () => {
  const { gravados } = await capturar({
    userText: "acordei com o peito apertado",
    clientTime: "2026-08-17T03:12:00.000Z",
  });
  const passagens = gravados.filter((g) => g.source_type === "ConversationPassage");
  assert.equal(passagens.length, 1, "so o turno dele");
  assert.equal(passagens[0].prov_actor, "user_stated");
  assert.equal(passagens[0].metadata.role, "user", "a guarda de falante exige isto");
  assert.equal(passagens[0].occurred_at, "2026-08-17T03:12:00.000Z",
    "sem hora do evento a nota fica fora da junta com a fisiologia");
});

// Proveniencia e sobre COMO a alegacao veio a ser acreditada: "digitou sozinho no
// widget" nao e a mesma coisa que "respondeu ao companion".
test("a superficie distingue nota de turno de chat", async () => {
  const nota = await capturar({ userText: "dormi mal" });
  assert.equal(nota.gravados[0].prov_surface, "companion-ios-nota");
  assert.equal(nota.gravados[0].metadata.standalone, true);

  const par = await capturar({ userText: "oi", assistantText: "oi voce" });
  const dele = par.gravados.find((g) => g.metadata?.role === "user");
  assert.equal(dele.prov_surface, "companion-ios");
  assert.equal(dele.metadata.standalone, undefined);
});

// Destilar tres palavras produziria um atomo `model_distilled` que e a maquina
// parafraseando — ruido com aparencia de conhecimento, e um segundo registro
// sobre o mesmo evento que nao e modalidade nova nenhuma.
test("nota avulsa NAO e destilada", async () => {
  const { gravados, destilou } = await capturar({ userText: "peito apertado" });
  assert.equal(destilou, false);
  assert.equal(gravados.filter((g) => g.source_type === "MemoryAtom").length, 0);
});

test("o par continua sendo destilado", async () => {
  const { gravados, destilou } = await capturar({ userText: "oi", assistantText: "oi voce" });
  assert.equal(destilou, true);
  assert.ok(gravados.some((g) => g.source_type === "MemoryAtom"));
});

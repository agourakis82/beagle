// memory-ingest-voz.test.mjs — a modalidade sobrevive à porta de entrada.
//
// Medido em 17-ago-2026: os 120 turnos DELE que chegaram ao memory-pg via `companion-ios`
// carregavam exatamente três chaves de metadata — role, session_id, space. Nenhuma marca de
// que o turno foi FALADO. O app sabia (VoiceTurnController produz a String, SpeechRecognizer
// mede ritmo e pausa) e a informação morria na porta.
//
// Isso importa porque proveniencia e sobre COMO a alegacao veio a ser acreditada. Um turno
// ditado no corredor de um plantao e um turno digitado sentado nao sao a mesma evidencia
// sobre o mesmo homem, e depois de gravados ficam indistinguiveis para sempre.
//
// ⚠️ E o que este teste NAO autoriza: falado e digitado sao o MESMO canal — auto-relato —
// em duas formas. Marcar a modalidade serve para auditar e estratificar. Nunca para contar
// como corroboracao: a independencia que a Fase 2 exige vem do corpo, nao do teclado.

import { test } from "node:test";
import assert from "node:assert/strict";
import { provSurfaceDoTurno, handleIngestRequest, ingestPersonalTurn } from "./memory-ingest.mjs";

test("as quatro combinacoes tem superficies distintas", () => {
  assert.equal(provSurfaceDoTurno({}), "companion-ios");
  assert.equal(provSurfaceDoTurno({ standalone: true }), "companion-ios-nota");
  assert.equal(provSurfaceDoTurno({ spoken: true }), "companion-ios-voz");
  assert.equal(provSurfaceDoTurno({ spoken: true, standalone: true }), "companion-ios-nota-voz");

  // Quatro entradas, quatro saidas: nenhuma colide, senao a distincao nao existe.
  const todas = [{}, { standalone: true }, { spoken: true }, { spoken: true, standalone: true }]
    .map(provSurfaceDoTurno);
  assert.equal(new Set(todas).size, 4);
});

/** Coleta o que a ingestao gravaria, sem tocar em rede. */
async function capturar(entrada) {
  const gravados = [];
  await ingestPersonalTurn(entrada, {
    captureFn: async (rec) => { gravados.push(rec); return { id: "r1" }; },
    distillFn: async () => [],
    fetchImpl: async () => ({ ok: true, json: async () => ({}) }),
    tokenFn: null,
  });
  return gravados;
}

test("a nota falada chega marcada, com a hora do evento", async () => {
  const g = await capturar({
    userText: "acordei com o peito apertado", spoken: true,
    clientTime: "2026-08-17T03:12:00.000Z",
  });
  const dele = g.find((x) => x.metadata?.role === "user");
  assert.equal(dele.prov_surface, "companion-ios-nota-voz");
  assert.equal(dele.metadata.spoken, true);
  assert.equal(dele.metadata.standalone, true);
  assert.equal(dele.prov_actor, "user_stated");
  assert.equal(dele.occurred_at, "2026-08-17T03:12:00.000Z");
});

test("turno de chat falado e chat, mas marcado", async () => {
  const g = await capturar({ userText: "to cansado", assistantText: "quer parar?", spoken: true });
  const dele = g.find((x) => x.metadata?.role === "user");
  assert.equal(dele.prov_surface, "companion-ios-voz");
  assert.equal(dele.metadata.spoken, true);
  assert.equal(dele.metadata.standalone, undefined, "nao e nota: houve resposta");
});

// A maquina nao fala sobre ele. Se o TTS leu a resposta em voz alta, isso e a boca do
// companion — nao e evidencia nenhuma sobre como ELE se expressou.
test("a marca de fala NAO contamina o turno do assistente", async () => {
  const g = await capturar({ userText: "oi", assistantText: "oi voce", spoken: true });
  const maquina = g.find((x) => x.metadata?.role === "assistant");
  assert.equal(maquina.prov_surface, "companion-ios");
  assert.equal(maquina.metadata.spoken, undefined);
  assert.equal(maquina.prov_actor, "model_generated");
});

test("turno digitado continua sem marca nenhuma", async () => {
  const g = await capturar({ userText: "digitei isto", assistantText: "ok" });
  const dele = g.find((x) => x.metadata?.role === "user");
  assert.equal(dele.prov_surface, "companion-ios");
  assert.equal(dele.metadata.spoken, undefined,
    "ausencia, nao `false`: a chave so existe quando ha o que afirmar");
});

// 🚨 O modo de falha que interessa. `Boolean("false")` e true em JS, entao um cliente que
// mandasse a string "false" marcaria como falado um turno digitado — a maquina afirmando
// algo sobre como ele se expressou. A guarda e por valor, nao por veracidade.
test("valores que NAO sao fala nao marcam", async () => {
  for (const lixo of [undefined, null, false, 0, "", "nao", "False", 1, {}]) {
    const r = await handleIngestRequest({ userText: "x", spoken: lixo },
      { ingestFn: async (e) => { assert.equal(e.spoken, false, `spoken=${JSON.stringify(lixo)}`); } });
    assert.equal(r.status, 202);
  }
});

test("so `true` e a string 'true' marcam", async () => {
  for (const bom of [true, "true"]) {
    await handleIngestRequest({ userText: "x", spoken: bom },
      { ingestFn: async (e) => { assert.equal(e.spoken, true, `spoken=${JSON.stringify(bom)}`); } });
  }
});

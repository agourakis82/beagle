// contexto-excedido.test.mjs — "o registro nao coube" tem que ser distinguivel de "o servidor
// falhou", porque as duas coisas pedem politicas OPOSTAS.
//
// Falha de infraestrutura e transitoria: repetir tem chance de dar certo, e depois de N
// tentativas o registro vai para a fila morta porque algo esta quebrado.
//
// Falha por tamanho e deterministica: o registro tem o tamanho que tem, repetir queima GPU
// para obter o resultado identico, e a fila morta e o lugar errado — nao ha nada quebrado, so
// um teto que ainda nao subiu o suficiente.
//
// Os corpos abaixo sao TRANSCRITOS de respostas reais dos dois servidores do cluster, colhidas
// em 18-ago-2026 provocando o estouro de proposito. Fixture inventada aqui nao provaria nada:
// o detector existe justamente para casar com o formato que cada servidor de fato emite.

import { test } from "node:test";
import assert from "node:assert/strict";
import { detectaContextoExcedido, ContextTooLargeError, makeRouterLlmFn } from "../src/graph-extract.mjs";

// llama.cpp na L4 do r770, `-c 40960 --parallel 4`
const CORPO_LLAMACPP = JSON.stringify({
  error: {
    code: 400,
    message: "request (60031 tokens) exceeds the available context size (10240 tokens), try increasing it",
    type: "exceed_context_size_error",
    n_prompt_tokens: 60031,
    n_ctx: 10240,
  },
});

// LiteLLM na frente do vLLM do r1-distill-70b: embrulha a excecao do provedor numa string e
// nao tem campo estruturado proprio.
const CORPO_LITELLM = JSON.stringify({
  error: {
    message:
      "litellm.ContextWindowExceededError: litellm.BadRequestError: ContextWindowExceededError: " +
      "OpenAIException - request (20007 tokens) exceeds the available context size (8192 tokens), " +
      "try increasing it\nmodel=r1-distill-70b. context_window_fallbacks=None.",
  },
});

test("le o campo estruturado do llama.cpp, com os dois numeros", () => {
  const r = detectaContextoExcedido(400, CORPO_LLAMACPP);
  assert.ok(r);
  assert.equal(r.promptTokens, 60031);
  assert.equal(r.ctxTokens, 10240);
});

test("reconhece o LiteLLM, que so tem prosa", () => {
  const r = detectaContextoExcedido(400, CORPO_LITELLM);
  assert.ok(r);
  assert.equal(r.promptTokens, 20007);
  assert.equal(r.ctxTokens, 8192);
});

test("NAO dispara em erro comum de servidor", () => {
  assert.equal(detectaContextoExcedido(500, "Connection error."), null);
  assert.equal(detectaContextoExcedido(503, JSON.stringify({ error: { message: "no healthy upstream" } })), null);
  assert.equal(detectaContextoExcedido(400, JSON.stringify({ error: { message: "invalid model" } })), null);
});

test("NAO dispara em 500 que por acaso menciona contexto", () => {
  // Um upstream que morre no meio pode ecoar a frase. Tratar como quarentena mandaria uma
  // falha transitoria para o limbo, onde ela nao seria retentada nunca.
  const corpo = JSON.stringify({ error: { message: "upstream crashed: exceeds the available context size" } });
  assert.equal(detectaContextoExcedido(500, corpo), null);
});

test("corpo nao-JSON nao derruba o detector", () => {
  assert.equal(detectaContextoExcedido(400, "<html>502 Bad Gateway</html>"), null);
  assert.equal(detectaContextoExcedido(400, ""), null);
});

test("o llmFn lanca ContextTooLargeError, com kind proprio", async () => {
  const fetchFalso = async () => ({ ok: false, status: 400, text: async () => CORPO_LLAMACPP });
  const llmFn = makeRouterLlmFn("http://x", { model: "m", fetchImpl: fetchFalso });
  await assert.rejects(
    () => llmFn("prompt gigante"),
    (err) => {
      assert.ok(err instanceof ContextTooLargeError);
      assert.equal(err.kind, "exceed_context");
      assert.equal(err.promptTokens, 60031);
      assert.equal(err.ctxTokens, 10240);
      return true;
    },
  );
});

test("erro comum continua sendo erro comum, e nao vira quarentena", async () => {
  const fetchFalso = async () => ({ ok: false, status: 503, text: async () => "no healthy upstream" });
  const llmFn = makeRouterLlmFn("http://x", { model: "m", fetchImpl: fetchFalso });
  await assert.rejects(
    () => llmFn("p"),
    (err) => {
      assert.ok(!(err instanceof ContextTooLargeError));
      assert.notEqual(err.kind, "exceed_context");
      return true;
    },
  );
});

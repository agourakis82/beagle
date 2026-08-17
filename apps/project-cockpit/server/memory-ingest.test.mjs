import { test } from "node:test";
import assert from "node:assert/strict";
import {
  buildVerbatimPayload,
  ingestVerbatim,
  buildDistillPrompt,
  parseDistillAtoms,
  distillSalient,
  ingestPersonalTurn,
} from "./memory-ingest.mjs";

// --- Task 1: verbatim payload builder ---

test("buildVerbatimPayload shapes a beagle-core ingest_chat session", () => {
  const p = buildVerbatimPayload({
    sessionId: "sess-1",
    userText: "amanhã tenho consulta às 9h",
    assistantText: "anotado, te lembro de manhã",
    clientTime: "2026-06-27T08:00:00Z",
    timezone: "America/Sao_Paulo",
  });
  assert.equal(p.source, "companion-personal");
  assert.equal(p.session_id, "sess-1");
  assert.deepEqual(p.turns, [
    { role: "user", content: "amanhã tenho consulta às 9h" },
    { role: "assistant", content: "anotado, te lembro de manhã" },
  ]);
  assert.deepEqual(p.tags, ["companion", "personal", "verbatim"]);
  assert.equal(p.metadata.space, "personal");
  assert.equal(p.metadata.client_time, "2026-06-27T08:00:00Z");
  assert.equal(p.metadata.timezone, "America/Sao_Paulo");
});

// O contrato deixou de ser simetrico, de proposito. Sem a fala DELE nao ha o que
// capturar; sem a resposta do companion ha — e uma nota avulsa, o formato mais
// provavel de um auto-relato ("peito apertado" as tres da manha). Exigir o par
// fazia toda nota solta morrer num 400.
test("buildVerbatimPayload exige a fala dele, mas nao a resposta", () => {
  assert.equal(buildVerbatimPayload({ sessionId: "s", userText: "", assistantText: "hi" }), null);

  const nota = buildVerbatimPayload({ sessionId: "s", userText: "hi", assistantText: "" });
  assert.ok(nota, "nota avulsa e capturavel");
  assert.deepEqual(nota.turns.map((t) => t.role), ["user"],
    "sem turno fantasma do companion no historico");
});

// --- Task 2: verbatim ingest IO ---

test("ingestVerbatim POSTs to beagle-core ingest_chat with operator auth", async () => {
  let captured = null;
  const fetchImpl = async (url, opts) => {
    captured = { url, opts };
    return { ok: true, status: 200, text: async () => '{"status":"ok"}' };
  };
  const tokenFn = async () => ({ token: "tok-123" });
  const payload = { source: "companion-personal", session_id: "s", turns: [], tags: [], metadata: {} };
  const ok = await ingestVerbatim(payload, { baseUrl: "http://beagle-core", fetchImpl, tokenFn });
  assert.equal(ok, true);
  assert.equal(captured.url, "http://beagle-core/api/memory/ingest_chat");
  assert.equal(captured.opts.method, "POST");
  assert.equal(captured.opts.headers.Authorization, "Bearer tok-123");
  assert.equal(captured.opts.headers["X-Beagle-Consumer"], "beagle-operator");
  assert.deepEqual(JSON.parse(captured.opts.body), payload);
});

test("ingestVerbatim is best-effort: returns false on error, never throws", async () => {
  const fetchImpl = async () => { throw new Error("network down"); };
  const tokenFn = async () => ({ token: "t" });
  const ok = await ingestVerbatim({ turns: [] }, { baseUrl: "http://x", fetchImpl, tokenFn });
  assert.equal(ok, false);
});

test("ingestVerbatim returns false when no token", async () => {
  const ok = await ingestVerbatim({ turns: [] }, {
    baseUrl: "http://x",
    fetchImpl: async () => ({ ok: true }),
    tokenFn: async () => ({ token: "", error: "no token" }),
  });
  assert.equal(ok, false);
});

// --- Task 3: distill prompt + parser ---

test("buildDistillPrompt instructs []-by-default selective extraction", () => {
  const p = buildDistillPrompt({ userText: "oi", assistantText: "ola!" });
  assert.match(p, /\[\]/);
  assert.match(p, /oi/);
  assert.match(p, /ola!/);
});

test("parseDistillAtoms reads a JSON array of strings", () => {
  assert.deepEqual(parseDistillAtoms('["consulta amanhã 9h","prefere chá a café"]'),
    ["consulta amanhã 9h", "prefere chá a café"]);
});

test("parseDistillAtoms tolerates prose-wrapped JSON and caps at 4", () => {
  const out = parseDistillAtoms('claro:\n["a","b","c","d","e","f"]\nfim');
  assert.deepEqual(out, ["a", "b", "c", "d"]);
});

test("parseDistillAtoms returns [] for junk / empty / non-array", () => {
  assert.deepEqual(parseDistillAtoms("[]"), []);
  assert.deepEqual(parseDistillAtoms("não sei"), []);
  assert.deepEqual(parseDistillAtoms('{"x":1}'), []);
  assert.deepEqual(parseDistillAtoms(""), []);
});

// --- Task 4: distill IO ---

test("distillSalient calls the sovereign model and returns atoms", async () => {
  let captured = null;
  const fetchImpl = async (url, opts) => {
    captured = { url, body: JSON.parse(opts.body) };
    return { ok: true, json: async () => ({ choices: [{ message: { content: '["consulta 9h"]' } }] }) };
  };
  const atoms = await distillSalient(
    { userText: "consulta amanhã 9h", assistantText: "anotado" },
    { routerUrl: "http://router:4000", model: "qwen2.5-14b", fetchImpl });
  assert.deepEqual(atoms, ["consulta 9h"]);
  assert.equal(captured.url, "http://router:4000/v1/chat/completions");
  assert.equal(captured.body.model, "qwen2.5-14b");
});

test("distillSalient returns [] on error (best-effort)", async () => {
  const fetchImpl = async () => { throw new Error("spark down"); };
  const atoms = await distillSalient({ userText: "x", assistantText: "y" },
    { routerUrl: "http://r", model: "qwen2.5-14b", fetchImpl });
  assert.deepEqual(atoms, []);
});

// --- Task 5: orchestrator ---

test("ingestPersonalTurn ingests verbatim then distilled atoms", async () => {
  const posted = [];
  const deps = {
    baseUrl: "http://bc",
    routerUrl: "http://rt",
    model: "qwen2.5-14b",
    tokenFn: async () => ({ token: "t" }),
    fetchImpl: async (url, opts) => {
      if (url.endsWith("/api/memory/ingest_chat")) {
        posted.push(JSON.parse(opts.body));
        return { ok: true, status: 200, text: async () => "ok" };
      }
      return { ok: true, json: async () => ({ choices: [{ message: { content: '["fato X"]' } }] }) };
    },
  };
  await ingestPersonalTurn(
    { sessionId: "s1", userText: "guarda o fato X", assistantText: "guardado" }, deps);
  const verb = posted.find((p) => p.tags.includes("verbatim"));
  const dist = posted.find((p) => p.tags.includes("distill"));
  assert.ok(verb, "verbatim ingested");
  assert.ok(dist, "distill ingested");
  assert.equal(dist.turns[0].content, "fato X");
});

test("ingestPersonalTurn never throws even if everything fails", async () => {
  await ingestPersonalTurn(
    { sessionId: "s", userText: "a", assistantText: "b" },
    { baseUrl: "http://x", routerUrl: "http://y", tokenFn: async () => { throw new Error("boom"); },
      fetchImpl: async () => { throw new Error("boom"); } });
  assert.ok(true);
});

test("ingestPersonalTurn skips when a side is empty (no posts)", async () => {
  let calls = 0;
  await ingestPersonalTurn({ sessionId: "s", userText: "", assistantText: "b" },
    { baseUrl: "http://x", routerUrl: "http://y", tokenFn: async () => ({ token: "t" }),
      fetchImpl: async () => { calls++; return { ok: true }; } });
  assert.equal(calls, 0);
});

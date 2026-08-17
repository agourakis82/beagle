// graph-extract.test.mjs — Phase 4, Task 4.3: sovereign-LLM graph extraction +
// bi-temporal apply. The LLM is STUBBED (no cluster, deterministic): it returns
// known entities + temporally-scoped facts. We assert the parse, entity
// resolution, fact insertion, idempotency, and — the heart of the bi-temporal
// model — that a contradicting fact INVALIDATES the prior one (valid_to set)
// rather than deleting it, so history is preserved.

import { test, before, beforeEach, after } from "node:test";
import assert from "node:assert/strict";
import { makePool, ensureSchema } from "../src/db.mjs";
import { extractGraph, applyExtraction, GraphExtractionError, buildExtractionPrompt } from "../src/graph-extract.mjs";

const DSN = process.env.MEMORY_PG_TEST_DSN;
if (!DSN) throw new Error("MEMORY_PG_TEST_DSN must be set");
const pool = makePool(DSN);

before(async () => { await ensureSchema(pool); });
beforeEach(async () => { await pool.query("TRUNCATE entities, facts, pending_graph CASCADE"); });
after(async () => { await pool.end(); });

// stub llmFn: returns whatever JSON the test wired, ignoring the prompt.
function stubLlm(json) {
  return async () => (typeof json === "string" ? json : JSON.stringify(json));
}

test("extractGraph parses entities + facts from the LLM JSON", async () => {
  const llmFn = stubLlm({
    entities: [{ name: "Demetrios", type: "person" }, { name: "Lisbon", type: "place" }],
    facts: [
      { subject: "Demetrios", predicate: "located_in", object: "Lisbon",
        statement: "Demetrios is located in Lisbon", occurred_at: "2026-06-01", confidence: 0.9 },
    ],
  });
  const out = await extractGraph({ content: "Demetrios moved to Lisbon." }, { llmFn });
  assert.equal(out.entities.length, 2);
  assert.equal(out.facts.length, 1);
  assert.equal(out.facts[0].predicate, "located_in");
});

test("extractGraph tolerates LLM prose and fences around the JSON", async () => {
  const wrapped = "Sure! Here is the graph:\n```json\n" +
    JSON.stringify({ entities: [{ name: "Sounio", type: "project" }], facts: [] }) + "\n```\nDone.";
  const out = await extractGraph({ content: "x" }, { llmFn: stubLlm(wrapped) });
  assert.equal(out.entities[0].name, "Sounio");
});

// The assertion below used to be the opposite: unparseable output returned an
// empty extraction and never threw. That made a dead LLM indistinguishable from
// a record with nothing in it — the worker marked both done and moved on. The
// graph pipeline ran 29 days that way, emitting facts=0 every cycle with an
// empty DLQ, because every failure was being recorded as a success.
test("extractGraph THROWS on unparseable output — broken is not empty", async () => {
  await assert.rejects(
    () => extractGraph({ content: "x" }, { llmFn: stubLlm("not json at all") }),
    (err) => err instanceof GraphExtractionError && err.kind === "unparseable",
  );
});

test("extractGraph THROWS when the LLM call itself fails", async () => {
  const dead = async () => { throw new Error("router 500: no backend for model_group"); };
  await assert.rejects(
    () => extractGraph({ content: "x" }, { llmFn: dead }),
    (err) => err instanceof GraphExtractionError && err.kind === "llm" && /router 500/.test(err.message),
  );
});

// The one case that legitimately produces nothing: the model answered, the
// answer parsed, and it genuinely found no entities or facts. Silence must
// still be allowed to mean silence.
test("extractGraph returns empty for well-formed output with nothing in it", async () => {
  const out = await extractGraph({ content: "..." }, { llmFn: stubLlm({ entities: [], facts: [] }) });
  assert.deepEqual(out, { entities: [], facts: [] });
});

test("applyExtraction resolves entities + inserts facts (idempotent)", async () => {
  const extraction = {
    entities: [{ name: "Demetrios", type: "person" }, { name: "Beagle", type: "project" }],
    facts: [{ subject: "Demetrios", predicate: "built", object: "Beagle",
              statement: "Demetrios built Beagle", confidence: 1.0 }],
  };
  const r1 = await applyExtraction(pool, extraction, { recordId: null });
  assert.equal(r1.entitiesResolved, 2);
  assert.equal(r1.factsInserted, 1);
  // re-apply: same content_sha256 → no new facts, entities reused
  const r2 = await applyExtraction(pool, extraction, { recordId: null });
  assert.equal(r2.factsInserted, 0, "idempotent on re-apply");
  assert.equal((await pool.query("SELECT count(*)::int n FROM facts")).rows[0].n, 1);
  assert.equal((await pool.query("SELECT count(*)::int n FROM entities")).rows[0].n, 2);
});

test("a contradicting fact INVALIDATES the prior one (valid_to set, not deleted)", async () => {
  // (Demetrios, located_in, São Paulo) then later (Demetrios, located_in, Lisbon).
  await applyExtraction(pool, {
    entities: [{ name: "Demetrios", type: "person" }, { name: "São Paulo", type: "place" }],
    facts: [{ subject: "Demetrios", predicate: "located_in", object: "São Paulo",
              statement: "Demetrios is located in São Paulo", valid_from: "2025-01-01" }],
  }, { recordId: null });

  const second = await applyExtraction(pool, {
    entities: [{ name: "Demetrios", type: "person" }, { name: "Lisbon", type: "place" }],
    facts: [{ subject: "Demetrios", predicate: "located_in", object: "Lisbon",
              statement: "Demetrios is located in Lisbon", valid_from: "2026-06-01" }],
  }, { recordId: null });
  assert.equal(second.factsInvalidated, 1, "the São Paulo fact was invalidated");

  // both rows still exist — history preserved
  assert.equal((await pool.query("SELECT count(*)::int n FROM facts")).rows[0].n, 2);
  // exactly one CURRENT fact for (Demetrios, located_in), and it's Lisbon
  const cur = await pool.query(
    `SELECT f.statement FROM facts f WHERE f.predicate='located_in' AND f.valid_to IS NULL`);
  assert.equal(cur.rowCount, 1);
  assert.match(cur.rows[0].statement, /Lisbon/);
  // the invalidated one has valid_to set to the new fact's valid_from
  const inv = await pool.query(
    `SELECT valid_to FROM facts WHERE statement LIKE '%São Paulo%'`);
  assert.ok(inv.rows[0].valid_to != null, "prior fact has valid_to set (invalidated, not deleted)");
});

test("multi-valued predicate to a DIFFERENT object is not a contradiction", async () => {
  // "knows" can have many objects → adding a second must NOT invalidate the first.
  await applyExtraction(pool, {
    entities: [{ name: "A", type: "person" }, { name: "B", type: "person" }],
    facts: [{ subject: "A", predicate: "knows", object: "B", statement: "A knows B" }],
  }, { recordId: null });
  const r = await applyExtraction(pool, {
    entities: [{ name: "A", type: "person" }, { name: "C", type: "person" }],
    facts: [{ subject: "A", predicate: "knows", object: "C", statement: "A knows C",
              multi_valued: true }],
  }, { recordId: null });
  assert.equal(r.factsInvalidated, 0, "multi-valued predicate keeps both");
  assert.equal((await pool.query("SELECT count(*)::int n FROM facts WHERE valid_to IS NULL")).rows[0].n, 2);
});

// --- A guarda do statement vazio ---
//
// `statement` e o texto que vai para o indice semantico. Sem ele o fato existe na tabela e
// NUNCA pode ser recuperado: nao e um fato fraco, e um fato que ninguem jamais lera, ocupando
// espaco e inflando toda contagem de "conhecimento extraido".
//
// Medido em 17-ago-2026: 66% do que o `qwen2.5:14b` produzia vinha assim, contra 10% do
// `coder:32b` e 7,9% do corpus historico.

test("fato sem statement NAO e gravado", async () => {
  
  const r = await applyExtraction(pool, {
    entities: [{ name: "PR", type: "thing" }],
    facts: [{ subject: "PR", predicate: "contains_pr_state", object_literal: "blocked", statement: "" }],
  }, { recordId: null });

  assert.equal(r.factsInserted, 0);
  assert.equal(r.semSentenca, 1, "recusado, e CONTADO");
  const q = await pool.query("SELECT count(*)::int n FROM facts");
  assert.equal(q.rows[0].n, 0);
});

test("statement so com espaco tambem e recusado", async () => {
  
  const r = await applyExtraction(pool, {
    entities: [{ name: "X", type: "thing" }],
    facts: [{ subject: "X", predicate: "p", object_literal: "v", statement: "   \n  " }],
  }, { recordId: null });
  assert.equal(r.factsInserted, 0);
  assert.equal(r.semSentenca, 1);
});

test("statement ausente (undefined) e recusado", async () => {
  
  const r = await applyExtraction(pool, {
    entities: [{ name: "X", type: "thing" }],
    facts: [{ subject: "X", predicate: "p", object_literal: "v" }],
  }, { recordId: null });
  assert.equal(r.factsInserted, 0);
  assert.equal(r.semSentenca, 1);
});

// 🚨 O risco da guarda nao e recusar de menos: e recusar DEMAIS. Um lote com um fato ruim e
// um bom nao pode perder o bom junto.
test("o fato BOM do mesmo lote sobrevive ao descarte do ruim", async () => {
  
  const r = await applyExtraction(pool, {
    entities: [{ name: "X", type: "thing" }],
    facts: [
      { subject: "X", predicate: "ruim", object_literal: "v", statement: "" },
      { subject: "X", predicate: "bom", object_literal: "v2", statement: "ele dormiu mal ontem" },
    ],
  }, { recordId: null });

  assert.equal(r.semSentenca, 1);
  assert.equal(r.factsInserted, 1, "o bom entrou");
  const q = await pool.query("SELECT predicate, statement FROM facts");
  assert.equal(q.rows.length, 1);
  assert.equal(q.rows[0].predicate, "bom");
  assert.match(q.rows[0].statement, /dormiu mal/);
});

test("extracao inteiramente boa nao recusa nada", async () => {
  
  const r = await applyExtraction(pool, {
    entities: [{ name: "X", type: "thing" }],
    facts: [{ subject: "X", predicate: "p", object_literal: "v", statement: "uma sentenca legivel" }],
  }, { recordId: null });
  assert.equal(r.semSentenca, 0);
  assert.equal(r.factsInserted, 1);
});

// O prompt precisa PEDIR o statement, nao so desenhar o formato.
//
// Medido em 17-ago-2026, depois da guarda entrar: 66% dos fatos do `qwen2.5:14b` e ate 19 de
// um unico registro no `r1-distill-70b` chegavam sem `statement`. A conclusao facil seria
// "modelo ruim" — e estaria errada. `statement` aparecia apenas na FORMA do JSON, sem nunca
// ser declarado obrigatorio nem explicado, entao todo modelo o tratava como enfeite.
test("o prompt declara statement OBRIGATORIO e diz o que e", () => {
  const p = buildExtractionPrompt("qualquer texto");
  assert.match(p, /STATEMENT IS MANDATORY/,
    "sem esta linha, o modelo trata statement como opcional");
  assert.match(p, /self-contained/i, "diz que a sentenca se sustenta sozinha");
  assert.match(p, /DROP IT/,
    "manda descartar em vez de emitir vazio — senao o modelo 'obedece' com aspas vazias");
});

// Exemplo negativo importa tanto quanto o positivo: os vazios reais vinham exatamente
// nesse formato — o predicado repetido como sentenca, ou um literal solto.
test("o prompt mostra o que NAO serve como statement", () => {
  const p = buildExtractionPrompt("x");
  assert.match(p, /contains_pr_state/, "usa o lixo real medido como contraexemplo");
});

// graph-extract.mjs — Phase 4, Task 4.3: sovereign-LLM graph extraction + apply.
//
// extractGraph turns a record's text into {entities, facts} via a cluster-local
// (sovereign) LLM — health/biography is sensitive, so NEVER a commercial API.
// The LLM call is injected (llmFn) so this is unit-testable with a stub.
//
// applyExtraction persists the result onto the bi-temporal graph: resolveEntity
// each mention, then for each fact INVALIDATE any contradicting current fact
// (same subject+predicate, single-valued, different object → SET valid_to, never
// delete) before inserting the new one (idempotent on content_sha256).

import crypto from "node:crypto";
import { resolveEntity } from "./graph.mjs";

function sha256hex(s) {
  return crypto.createHash("sha256").update(s).digest("hex");
}

/**
 * Build the strict extraction prompt. Asks for ONLY a JSON object so parsing is
 * robust; the model is told to scope facts temporally and mark multi-valued
 * relations (so we don't over-invalidate).
 */
export function buildExtractionPrompt(content) {
  return [
    "Extract a knowledge graph from the text. Return ONLY a JSON object, no prose:",
    '{"entities":[{"name","type"}],"facts":[{"subject","predicate","object"|"object_literal",',
    '"statement","occurred_at"?,"valid_from"?,"confidence"?,"multi_valued"?}]}',
    "Rules: entities are people/projects/places/systems/concepts. predicate is a short snake_case",
    "relation. Set multi_valued=true for relations that can hold many objects at once (knows,",
    "uses, mentions). Use object_literal for non-entity objects (dates, numbers, free text).",
    "Scope facts in time when the text implies it. Extract only what the text supports.",
    "",
    "TEXT:",
    String(content || "").slice(0, 8000),
  ].join("\n");
}

/**
 * Build a sovereign LLM fn over the cluster LiteLLM router (OpenAI-compatible).
 * Reasoning models (r1-distill-70b) are fine — parseLlmJson strips <think> blocks.
 * @param {string} baseUrl  e.g. http://router.llm-router.svc.cluster.local:4000
 * @param {{model:string, apiKey?:string, timeoutMs?:number, temperature?:number}} opts
 * @returns {(prompt:string)=>Promise<string>}
 */
export function makeRouterLlmFn(baseUrl, opts = {}) {
  const url = baseUrl.replace(/\/+$/, "") + "/v1/chat/completions";
  const model = opts.model;
  const timeoutMs = opts.timeoutMs ?? 120000;
  const temperature = opts.temperature ?? 0;
  if (!model) throw new Error("makeRouterLlmFn: opts.model required");
  return async function llmFn(prompt) {
    const headers = { "content-type": "application/json" };
    if (opts.apiKey) headers.authorization = `Bearer ${opts.apiKey}`;
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), timeoutMs);
    try {
      const resp = await fetch(url, {
        method: "POST",
        headers,
        body: JSON.stringify({ model, temperature, messages: [{ role: "user", content: prompt }] }),
        signal: ctrl.signal,
      });
      if (!resp.ok) throw new Error(`router ${resp.status}: ${(await resp.text()).slice(0, 200)}`);
      const j = await resp.json();
      return j.choices?.[0]?.message?.content ?? "";
    } finally {
      clearTimeout(timer);
    }
  };
}

/** Pull the first balanced JSON object out of an LLM reply (tolerates prose/fences/reasoning). */
function parseLlmJson(reply) {
  // Strip reasoning blocks first — r1-distill emits <think>...</think> that may
  // itself contain braces, which would otherwise confuse the brace matcher.
  const s = String(reply || "").replace(/<think>[\s\S]*?<\/think>/gi, "");
  const start = s.indexOf("{");
  if (start === -1) return null;
  let depth = 0;
  for (let i = start; i < s.length; i++) {
    if (s[i] === "{") depth++;
    else if (s[i] === "}") {
      depth--;
      if (depth === 0) {
        try {
          return JSON.parse(s.slice(start, i + 1));
        } catch {
          return null;
        }
      }
    }
  }
  return null;
}

/**
 * Extract {entities, facts} from a record via the injected sovereign LLM.
 * Never throws — unparseable output yields an empty extraction.
 * @param {{content:string}} record
 * @param {{llmFn:(prompt:string)=>Promise<string>}} opts
 */
export async function extractGraph(record, { llmFn } = {}) {
  if (typeof llmFn !== "function") throw new Error("extractGraph: opts.llmFn required");
  let reply;
  try {
    reply = await llmFn(buildExtractionPrompt(record.content));
  } catch {
    return { entities: [], facts: [] };
  }
  const obj = parseLlmJson(reply);
  if (!obj || typeof obj !== "object") return { entities: [], facts: [] };
  const entities = Array.isArray(obj.entities) ? obj.entities.filter((e) => e && e.name) : [];
  const facts = Array.isArray(obj.facts) ? obj.facts.filter((f) => f && f.subject && f.predicate) : [];
  return { entities, facts };
}

/**
 * Persist an extraction onto the bi-temporal graph.
 * @param {import("pg").Pool} pool
 * @param {{entities:Array, facts:Array}} extraction
 * @param {{recordId?:(string|null), embedFn?:(texts:string[])=>Promise<number[][]>, occurredAt?:string}} opts
 * @returns {Promise<{entitiesResolved:number, factsInserted:number, factsInvalidated:number}>}
 */
export async function applyExtraction(pool, extraction, opts = {}) {
  const { recordId = null, embedFn = null, occurredAt = null } = opts;
  const entities = extraction.entities || [];
  const facts = extraction.facts || [];

  // Optionally embed entity names (for near-dup resolution) AND fact statements
  // (for the graph retrieval channel) in one batch.
  let entEmb = {};
  let factEmb = {};
  if (embedFn && (entities.length || facts.length)) {
    try {
      const names = entities.map((e) => e.name);
      const statements = facts.map((f) => f.statement || "");
      const vecs = await embedFn([...names, ...statements]);
      entities.forEach((e, i) => (entEmb[e.name] = vecs[i]));
      facts.forEach((f, i) => (factEmb[i] = vecs[names.length + i]));
    } catch {
      entEmb = {};
      factEmb = {};
    }
  }

  // Resolve every entity to a node id, keyed by name.
  const idByName = {};
  let entitiesResolved = 0;
  for (const e of entities) {
    const r = await resolveEntity(pool, {
      name: e.name,
      type: e.type || "unknown",
      embedding: entEmb[e.name] ?? null,
      summary: e.summary || "",
    });
    idByName[e.name] = r.id;
    entitiesResolved++;
  }

  let factsInserted = 0;
  let factsInvalidated = 0;
  for (let fi = 0; fi < facts.length; fi++) {
    const f = facts[fi];
    let subjectId = idByName[f.subject];
    if (!subjectId) {
      subjectId = (await resolveEntity(pool, { name: f.subject, type: "unknown" })).id;
      idByName[f.subject] = subjectId;
    }
    let objectId = null;
    if (f.object) {
      objectId = idByName[f.object];
      if (!objectId) {
        objectId = (await resolveEntity(pool, { name: f.object, type: "unknown" })).id;
        idByName[f.object] = objectId;
      }
    }
    const objectLiteral = f.object ? null : (f.object_literal ?? null);
    const validFrom = f.valid_from || occurredAt || null;
    const occ = f.occurred_at || occurredAt || null;
    const content_sha256 = sha256hex(
      [subjectId, f.predicate, objectId ?? "", objectLiteral ?? "", f.statement || ""].join("|"),
    );
    const factVec = f.embedding ?? factEmb[fi] ?? null;
    const embLit = factVec ? "[" + (Array.isArray(factVec) ? factVec.join(",") : factVec) + "]" : null;

    const client = await pool.connect();
    try {
      await client.query("BEGIN");
      // Contradiction: a SINGLE-VALUED relation whose object changed. Invalidate
      // the prior current fact(s) for (subject, predicate) with a different object.
      if (!f.multi_valued) {
        const inv = await client.query(
          `UPDATE facts SET valid_to = COALESCE($3::timestamptz, now())
             WHERE subject_id = $1 AND predicate = $2 AND valid_to IS NULL
               AND content_sha256 <> $4
               AND (object_id IS DISTINCT FROM $5 OR object_literal IS DISTINCT FROM $6)`,
          [subjectId, f.predicate, validFrom, content_sha256, objectId, objectLiteral],
        );
        factsInvalidated += inv.rowCount;
      }
      const ins = await client.query(
        `INSERT INTO facts
           (subject_id, predicate, object_id, object_literal, statement, embedding,
            valid_from, occurred_at, source_record_id, provenance, confidence, content_sha256)
         VALUES ($1,$2,$3,$4,$5,$6::halfvec,
                 COALESCE($7::timestamptz, now()),$8,$9,$10::jsonb,$11,$12)
         ON CONFLICT (content_sha256) DO NOTHING
         RETURNING id`,
        [
          subjectId, f.predicate, objectId, objectLiteral, f.statement || "", embLit,
          validFrom, occ, recordId, JSON.stringify(f.provenance || {}),
          f.confidence ?? 1.0, content_sha256,
        ],
      );
      await client.query("COMMIT");
      if (ins.rowCount > 0) factsInserted++;
    } catch (err) {
      await client.query("ROLLBACK");
      throw err;
    } finally {
      client.release();
    }
  }
  return { entitiesResolved, factsInserted, factsInvalidated };
}

export default applyExtraction;

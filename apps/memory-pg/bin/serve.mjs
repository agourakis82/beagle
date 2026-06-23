#!/usr/bin/env node
// bin/serve.mjs — Phase 2, Task 2.3: the retrieval HTTP API.
//
// The query path: embed the query (bge-m3) -> hybrid dense+BM25+RRF first stage
// (src/retrieve.mjs) -> cross-encoder rerank (src/rerank.mjs) -> top-N. This is
// the read side of the reliable memory pipeline; it reuses the exact same
// embeddings the embed-worker wrote (same model_version) so retrieval and
// ingestion never drift.
//
// createApp({ pool, embedFn, rerankFn, retrieveFn?, rerankN?, queryToken })
// is dependency-injected so it is unit-testable with stubs (no cluster). The
// bin wrapper at the bottom wires the real TEI embed/rerank fns + the live pool.
//
// Env (bin wrapper):
//   MEMORY_PG_DSN           postgres connection string (required)
//   BEAGLE_TEI_EMBED_URL    bge-m3 embed endpoint (required)
//   MEMORY_PG_RERANK_URL    bge-reranker-v2-m3 TEI base url (required)
//   MEMORY_PG_QUERY_TOKEN   bearer token; if set, /query requires it (unset = open/dev)
//   PORT                    listen port (default 8091)
//   QUERY_FIRST_STAGE_K     first-stage retrieve recall (default 50)
//   QUERY_DEFAULT_TOPN      default rerank top-N when the request omits k (default 10)

import express from "express";
import { makePool } from "../src/db.mjs";
import { makeTeiEmbedFn } from "../src/embed-worker.mjs";
import { retrieve as defaultRetrieve } from "../src/retrieve.mjs";
import { rerank, makeTeiRerankFn } from "../src/rerank.mjs";

const FIRST_STAGE_K = Number(process.env.QUERY_FIRST_STAGE_K || 50);
const DEFAULT_TOPN = Number(process.env.QUERY_DEFAULT_TOPN || 10);

/**
 * Build the express app with injected dependencies.
 *
 * @param {{
 *   pool: import("pg").Pool,
 *   embedFn: (texts: string[]) => Promise<number[][]>,
 *   rerankFn: (query: string, texts: string[]) => Promise<any>,
 *   retrieveFn?: (pool, opts) => Promise<Array<object>>,
 *   firstStageK?: number,
 *   defaultTopN?: number,
 *   queryToken?: string,
 * }} deps
 * @returns {import("express").Express}
 */
export function createApp(deps) {
  const {
    pool,
    embedFn,
    rerankFn,
    retrieveFn = defaultRetrieve,
    firstStageK = FIRST_STAGE_K,
    defaultTopN = DEFAULT_TOPN,
    queryToken = "",
  } = deps || {};

  if (typeof embedFn !== "function") throw new Error("createApp: embedFn required");
  if (typeof rerankFn !== "function") throw new Error("createApp: rerankFn required");

  const app = express();
  app.use(express.json({ limit: "1mb" }));

  app.get("/healthz", (_req, res) => res.json({ ok: true }));

  // Auth gate (mirrors physiome's authed()): unset token = open (dev); set =
  // require the matching Bearer.
  function authed(req) {
    if (!queryToken) return true;
    return (req.get("authorization") || "") === `Bearer ${queryToken}`;
  }

  app.post("/query", async (req, res) => {
    if (!authed(req)) return res.status(401).json({ error: "unauthorized" });
    const body = req.body || {};
    const query = typeof body.query === "string" ? body.query.trim() : "";
    if (!query) return res.status(400).json({ error: "query (non-empty string) required" });
    const topN = Number.isFinite(Number(body.k)) && Number(body.k) > 0 ? Number(body.k) : defaultTopN;

    try {
      // 1. Embed the query (single text -> 1024-dim).
      const vectors = await embedFn([query]);
      if (!Array.isArray(vectors) || !Array.isArray(vectors[0])) {
        throw new Error("embed returned no vector for query");
      }
      const queryEmbedding = vectors[0];

      // 2. Hybrid first-stage retrieve (dense + BM25 + RRF + recency).
      const candidates = await retrieveFn(pool, {
        queryEmbedding,
        queryText: query,
        k: firstStageK,
      });

      // 3. Cross-encoder rerank -> top-N.
      const reranked = await rerank(query, candidates, { rerankFn, topN });

      const results = reranked.map((c) => ({
        text: c.text,
        record_id: c.record_id,
        chunk_id: c.chunk_id,
        rerank_score: c.rerank_score,
        occurred_at: c.occurred_at ?? null,
      }));
      res.json({ ok: true, results });
    } catch (e) {
      // Best-effort: never crash the server; surface the error to the caller.
      res.status(500).json({ error: String(e?.message || e) });
    }
  });

  return app;
}

// ---- bin wrapper: wire the real cluster deps and listen. ----------------------

function isMain() {
  // Run the server only when invoked directly (node bin/serve.mjs), not on import.
  return process.argv[1] && import.meta.url === `file://${process.argv[1]}`;
}

async function main() {
  const dsn = process.env.MEMORY_PG_DSN;
  if (!dsn) throw new Error("MEMORY_PG_DSN is required");
  const embedUrl = process.env.BEAGLE_TEI_EMBED_URL;
  if (!embedUrl) throw new Error("BEAGLE_TEI_EMBED_URL is required");
  const rerankUrl = process.env.MEMORY_PG_RERANK_URL;
  if (!rerankUrl) throw new Error("MEMORY_PG_RERANK_URL is required");

  const pool = makePool(dsn);
  const app = createApp({
    pool,
    embedFn: makeTeiEmbedFn(embedUrl),
    rerankFn: makeTeiRerankFn(rerankUrl),
    queryToken: process.env.MEMORY_PG_QUERY_TOKEN || "",
  });

  const port = Number(process.env.PORT || 8091);
  app.listen(port, () => console.log(`[memory-pg-serve] query API listening on :${port}`));
}

if (isMain()) {
  main().catch((err) => {
    console.error(`[memory-pg-serve] fatal: ${err.stack || err.message}`);
    process.exit(1);
  });
}

export default createApp;

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
import { rerank, makeTeiRerankFn, cleanResults } from "../src/rerank.mjs";
import { captureRecord } from "../src/capture.mjs";
import { extractFromRecord, candidateToRecord } from "../src/backfill.mjs";
import { graphRetrieve as defaultGraphRetrieve, fuseChannels } from "../src/graph.mjs";

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
    ingestToken = "",
    // Default capture: persist each capture-ready record through the live ACID
    // captureRecord against the pool. Injectable so /capture is unit-testable
    // without a DB (stub captureFn).
    captureFn = async (recs) => {
      const out = [];
      for (const r of recs) out.push(await captureRecord(pool, r));
      return out;
    },
    // Phase 4: when the graph is populated, fuse a graph-fact channel into the
    // candidate pool before rerank. graphEnabled gates it (no-op + zero extra
    // query until the graph is live); graphRetrieveFn is injectable for tests.
    graphEnabled = false,
    graphRetrieveFn = defaultGraphRetrieve,
    graphHops = 1,
    graphK = 20,
    // Hard ceiling on the graph-fusion channel. The multi-hop traversal fans out
    // through hub entities (e.g. "Sounio" touches ~2900 facts) and can build a
    // 50k-row candidate set whose per-query latency swings from ~1s to >45s under
    // load — with no timeout, that hang propagated straight to /query. Cap it so a
    // slow graph query degrades to chunk-only retrieval (pre-Phase-4 behavior)
    // instead of stalling the whole request.
    graphTimeoutMs = Number(process.env.MEMORY_PG_GRAPH_TIMEOUT_MS) || 3500,
    // Max candidates handed to the (sequential, ~1.8s/batch-of-8, CPU) cross-encoder
    // reranker. The first-stage pool is RRF-ranked, so a generous top slice keeps
    // recall while bounding rerank latency. Tune via MEMORY_PG_RERANK_INPUT_CAP.
    rerankInputCap = Number(process.env.MEMORY_PG_RERANK_INPUT_CAP) || 24,
    // Relevance floor: drop final hits scoring below this rather than padding topN
    // with junk (a sparse query like "meu pai" was returning an unrelated log at
    // 0.126 while real hits score >=0.7). Cross-encoder scores are in (0,1); 0.2 is
    // safely below real matches and above noise. Tune via MEMORY_PG_RERANK_FLOOR.
    rerankFloor = Number(process.env.MEMORY_PG_RERANK_FLOOR ?? 0.2),
  } = deps || {};

  if (typeof embedFn !== "function") throw new Error("createApp: embedFn required");
  if (typeof rerankFn !== "function") throw new Error("createApp: rerankFn required");

  const app = express();
  app.use(express.json({ limit: "4mb" }));

  app.get("/healthz", (_req, res) => res.json({ ok: true }));

  // Auth gate (mirrors physiome's authed()): unset token = open (dev); set =
  // require the matching Bearer.
  function authed(req) {
    if (!queryToken) return true;
    return (req.get("authorization") || "") === `Bearer ${queryToken}`;
  }
  function ingestAuthed(req) {
    if (!ingestToken) return true;
    return (req.get("authorization") || "") === `Bearer ${ingestToken}`;
  }

  // Recent records by provenance surface, ordered by RECENCY (deterministic — not semantic).
  // The companion's technical register needs "the newest Sounio commits", which semantic /query
  // can't reliably surface; the sounio-now-poller writes SounioCommit/SounioState records here.
  app.get("/recent", async (req, res) => {
    if (!authed(req)) return res.status(401).json({ error: "unauthorized" });
    const surface = typeof req.query.surface === "string" ? req.query.surface.slice(0, 200) : "";
    if (!surface) return res.status(400).json({ error: "surface required" });
    const sourceType = typeof req.query.source_type === "string" ? req.query.source_type.slice(0, 80) : null;
    const limit = Math.min(Math.max(Number(req.query.limit) || 6, 1), 50);
    try {
      const params = [surface];
      let sql = "SELECT content, source_type, metadata, created_at FROM records WHERE prov_surface = $1";
      if (sourceType) { params.push(sourceType); sql += ` AND source_type = $${params.length}`; }
      params.push(limit);
      sql += ` ORDER BY created_at DESC LIMIT $${params.length}`;
      const { rows } = await pool.query(sql, params);
      res.json({ ok: true, records: rows });
    } catch (e) {
      res.status(500).json({ error: String(e.message || e) });
    }
  });

  app.post("/query", async (req, res) => {
    if (!authed(req)) return res.status(401).json({ error: "unauthorized" });
    const body = req.body || {};
    const query = typeof body.query === "string" ? body.query.trim() : "";
    if (!query) return res.status(400).json({ error: "query (non-empty string) required" });
    const topN = Number.isFinite(Number(body.k)) && Number(body.k) > 0 ? Number(body.k) : defaultTopN;
    // Trusted-only pass: restrict retrieval to his non-unverified records so the
    // companion's authoritative "what he told me" grounding is filled directly from
    // his own trusted words, not scraped from a noisy pool after top-k.
    const trustedOnly = body.trusted_only === true;

    try {
      // 1. Embed the query (single text -> 1024-dim).
      const vectors = await embedFn([query]);
      if (!Array.isArray(vectors) || !Array.isArray(vectors[0])) {
        throw new Error("embed returned no vector for query");
      }
      const queryEmbedding = vectors[0];

      // 2. Hybrid first-stage retrieve (dense + BM25 + RRF + recency).
      let candidates = await retrieveFn(pool, {
        queryEmbedding,
        queryText: query,
        k: firstStageK,
        trustedOnly,
      });

      // 2b. Graph channel (Phase 4): fuse relevant facts (vector + multi-hop) into
      // the candidate pool by RRF. Fail-soft — a graph error never breaks /query.
      if (graphEnabled) {
        try {
          // Bounded await: a slow multi-hop traversal must never hang /query. On
          // timeout the reject is caught below and we keep the chunk candidates.
          const facts = await Promise.race([
            graphRetrieveFn(pool, {
              queryEmbedding,
              k: graphK,
              hops: graphHops,
              // DB cancels ~0.5s before the JS race gives up, so a runaway is killed
              // server-side (connection reusable) rather than orphaned behind the race.
              timeoutMs: Math.max(1000, graphTimeoutMs - 500),
            }),
            new Promise((_, reject) =>
              setTimeout(() => reject(new Error("graph fusion timeout")), graphTimeoutMs).unref?.(),
            ),
          ]);
          if (Array.isArray(facts) && facts.length) {
            const fused = fuseChannels([
              { items: candidates, keyOf: (c) => "chunk:" + c.chunk_id },
              { items: facts, keyOf: (f) => "fact:" + f.fact_id },
            ]);
            candidates = fused.map((x) =>
              x.statement != null
                ? {
                    text: x.statement,
                    record_id: x.source_record_id ?? null,
                    chunk_id: "fact:" + x.fact_id,
                    occurred_at: null,
                    source: "graph",
                    // gate graph facts by the same trust filter as chunks; an
                    // untiered fact is treated as unverified, never laundered.
                    trust_tier: x.trust_tier ?? "unverified",
                  }
                : x,
            );
          }
        } catch (e) {
          // graph fusion is best-effort; keep the chunk candidates. Log so the
          // timeout/fallback rate is observable (a spike means the graph query
          // needs tuning, not that /query is broken).
          console.warn(`[memory-pg-serve] graph fusion skipped: ${e?.message || e}`);
        }
      }

      // 3. Cross-encoder rerank -> top-N. Cap the rerank input: the CPU reranker
      // costs ~1.8s per batch of 8 and is driven sequentially, so reranking the full
      // ~100-candidate first-stage pool took ~23s. The candidates are already RRF-
      // ranked, so reranking the top slice reorders the ones that matter without the
      // long tail — the dominant remaining /query latency after the graph-fusion fix.
      // Drop empty-text candidates BEFORE rerank so blank graph facts never
      // consume a rerank slot (or the cross-encoder's attention) at the expense
      // of a real hit.
      const nonEmpty = candidates.filter((c) => String(c?.text ?? "").trim());
      const toRerank =
        nonEmpty.length > rerankInputCap ? nonEmpty.slice(0, rerankInputCap) : nonEmpty;
      const reranked = await rerank(query, toRerank, { rerankFn, topN });

      // Post-rerank sharpening: relevance floor + dedup + belt-and-suspenders
      // empty drop, so the companion is grounded only on clean, on-topic hits.
      let results = cleanResults(
        reranked.map((c) => ({
          text: c.text,
          record_id: c.record_id,
          chunk_id: c.chunk_id,
          rerank_score: c.rerank_score,
          occurred_at: c.occurred_at ?? null,
          source: c.source ?? "chunk",
          trust_tier: c.trust_tier ?? null,
        })),
        { floor: rerankFloor },
      );
      // On a trusted-only pass, also drop any fused graph fact that is unverified
      // (the chunk channel was already trust-filtered at retrieve time; graph facts
      // are fused in separately, so gate them here too).
      if (trustedOnly) {
        results = results.filter((r) => r.trust_tier && r.trust_tier !== "unverified");
      }
      res.json({ ok: true, results });
    } catch (e) {
      // Best-effort: never crash the server; surface the error to the caller.
      res.status(500).json({ error: String(e?.message || e) });
    }
  });

  // Ingest endpoint for Phase 3 dual-write: beagle-core POSTs each newly written
  // record { kind, record } here in addition to its canonical JSONL append. We
  // run the SAME extraction the backfill uses (extractFromRecord), so dual-write
  // and migration produce identical memory-pg rows. Idempotent (captureRecord
  // dedups on content_sha256); restricted records yield zero captures.
  app.post("/capture", async (req, res) => {
    if (!ingestAuthed(req)) return res.status(401).json({ error: "unauthorized" });
    const body = req.body || {};
    const kind = typeof body.kind === "string" ? body.kind : "";
    const record = body.record;
    if (!kind || record == null || typeof record !== "object") {
      return res.status(400).json({ error: "kind (string) and record (object) required" });
    }
    try {
      const recs = extractFromRecord(kind, record).map(candidateToRecord);
      const results = recs.length ? await captureFn(recs) : [];
      res.json({
        ok: true,
        total: recs.length,
        created: results.filter((r) => r.created).length,
        ids: results.map((r) => ({ id: r.id, created: r.created })),
      });
    } catch (e) {
      res.status(500).json({ error: String(e?.message || e) });
    }
  });

  // Provenance-aware single-record capture. Unlike /capture (export-shaped), this takes
  // one clean record with explicit provenance and routes it straight through captureRecord
  // (which validates the actor + computes the orphan flag). Used by the companion to tag
  // its turns at the source: user_stated / model_generated / model_distilled(+derived_from).
  app.post("/capture_turn", async (req, res) => {
    if (!ingestAuthed(req)) return res.status(401).json({ error: "unauthorized" });
    const b = req.body || {};
    if (typeof b.source_type !== "string" || !b.source_type ||
        typeof b.content !== "string" || !b.content) {
      return res.status(400).json({ error: "source_type (string) and content (string) required" });
    }
    try {
      const rec = {
        source_type: b.source_type,
        content: b.content,
        occurred_at: b.occurred_at ?? null,
        metadata: (b.metadata && typeof b.metadata === "object") ? b.metadata : {},
        prov_actor: b.prov_actor ?? "model_generated",
        prov_surface: b.prov_surface ?? null,
        prov_derived_from: Array.isArray(b.prov_derived_from) ? b.prov_derived_from : [],
        prov_confidence: typeof b.prov_confidence === "number" ? b.prov_confidence : null,
      };
      const [out] = await captureFn([rec]);
      res.json({ id: out.id, created: out.created });
    } catch (e) {
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
    ingestToken: process.env.MEMORY_PG_INGEST_TOKEN || "",
    graphEnabled: /^(1|true|on)$/i.test((process.env.MEMORY_PG_GRAPH_ENABLED || "").trim()),
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

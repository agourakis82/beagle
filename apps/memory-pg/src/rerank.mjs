// rerank.mjs — Phase 2, Task 2.2: cross-encoder reranking (second stage).
//
// The first stage (retrieve.mjs) fuses dense + BM25 by rank (RRF). It is fast
// and high-recall but its scores are not a true relevance judgement. This stage
// re-scores the top-k candidates with a cross-encoder (BAAI/bge-reranker-v2-m3,
// served sovereignly via TEI), which attends to query+passage jointly and gives
// a sharper, comparable relevance score. We then keep the top-N.
//
// rerank() is decoupled from transport via an injected `rerankFn` so it is unit
// testable with a stub (no cluster). The real fn is makeTeiRerankFn(url).

/**
 * Normalize whatever a rerankFn returns into a per-candidate score array aligned
 * to the INPUT order. Accepts either:
 *   - number[]                aligned positionally to the input texts, or
 *   - {index, score}[]        TEI-style pairs, possibly unsorted.
 *
 * @param {number[]|Array<{index:number,score:number}>} raw
 * @param {number} n  expected candidate count
 * @returns {number[]} scores[i] = score for candidate i
 */
function alignScores(raw, n) {
  if (!Array.isArray(raw)) {
    throw new Error("rerank: rerankFn must return an array");
  }
  const scores = new Array(n).fill(Number.NEGATIVE_INFINITY);
  let sawPair = false;
  for (const item of raw) {
    if (item != null && typeof item === "object" && "index" in item) {
      sawPair = true;
      const idx = item.index;
      if (idx < 0 || idx >= n) {
        throw new Error(`rerank: rerankFn returned out-of-range index ${idx}`);
      }
      scores[idx] = Number(item.score);
    }
  }
  if (sawPair) return scores;
  // Plain number[] aligned positionally.
  if (raw.length !== n) {
    throw new Error(
      `rerank: rerankFn returned ${raw.length} scores for ${n} candidates`,
    );
  }
  return raw.map((s) => Number(s));
}

/**
 * Cross-encoder rerank of first-stage candidates.
 *
 * @param {string} query
 * @param {Array<{chunk_id:string, record_id:string, text:string, [k:string]:any}>} candidates
 * @param {{
 *   rerankFn: (query:string, texts:string[]) => (number[]|Array<{index:number,score:number}>|Promise<...>),
 *   topN?: number
 * }} opts
 * @returns {Promise<Array<{...candidate, rerank_score:number}>>} top-N, sorted by
 *   rerank_score desc; ties preserve original input order (stable).
 */
export async function rerank(query, candidates, { rerankFn, topN = 10 } = {}) {
  if (typeof rerankFn !== "function") {
    throw new Error("rerank: opts.rerankFn (function) is required");
  }
  if (!Array.isArray(candidates) || candidates.length === 0) {
    return [];
  }

  const texts = candidates.map((c) => c.text);
  const raw = await rerankFn(query, texts);
  const scores = alignScores(raw, candidates.length);

  // Attach scores, keep original index for a STABLE sort on ties.
  const decorated = candidates.map((c, i) => ({
    cand: { ...c, rerank_score: scores[i] },
    score: scores[i],
    idx: i,
  }));

  decorated.sort((a, b) => {
    if (b.score !== a.score) return b.score - a.score; // desc by score
    return a.idx - b.idx; // stable: original order on ties
  });

  return decorated.slice(0, topN).map((d) => d.cand);
}

/**
 * Build the real rerankFn that POSTs to a TEI reranker's /rerank endpoint.
 *
 * Verified TEI (text-embeddings-inference) request/response shape:
 *   POST {url}/rerank
 *   body: {"query": "...", "texts": ["...", "..."]}
 *   resp: [{"index": <input index>, "score": <float>}, ...]   (sorted desc)
 *
 * We do NOT rely on TEI's ordering — we realign by `index` to the input order.
 *
 * @param {string} url base url of the TEI reranker service (no trailing /rerank)
 * @returns {(query:string, texts:string[]) => Promise<number[]>} scores aligned
 *   to input order.
 */
export function makeTeiRerankFn(url) {
  const base = url.replace(/\/+$/, "");
  return async function teiRerank(query, texts) {
    const resp = await fetch(`${base}/rerank`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ query, texts }),
    });
    if (!resp.ok) {
      const detail = typeof resp.text === "function" ? await resp.text().catch(() => "") : "";
      throw new Error(`TEI rerank failed: HTTP ${resp.status} ${detail}`);
    }
    const body = await resp.json();
    if (!Array.isArray(body)) {
      throw new Error("TEI rerank: expected a JSON array response");
    }
    // body is [{index, score}] — realign to input order.
    const scores = new Array(texts.length).fill(Number.NEGATIVE_INFINITY);
    for (const item of body) {
      if (item == null || typeof item.index !== "number") {
        throw new Error("TEI rerank: malformed item (missing numeric index)");
      }
      scores[item.index] = Number(item.score);
    }
    return scores;
  };
}

export default rerank;

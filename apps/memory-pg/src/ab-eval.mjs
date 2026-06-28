// ab-eval.mjs — Phase 3, Task 3.3: A/B evaluation of the read cutover.
//
// Compares the legacy memory-engine (ColBERT) retrieval against the new memory-pg
// (dense+BM25+RRF → cross-encoder rerank) retrieval on a held-out set of REAL
// queries. The two systems share no record IDs, so the primary metric is
// recall@k against a GOLD set of known-relevant fragments per query; we also
// report snippet agreement (Jaccard) and latency. Pure metrics + an injectable
// evaluateAb (stub retrievers in tests; real HTTP in bin/ab-eval.mjs).

/** Lowercase, collapse all whitespace to single spaces, trim. */
export function normalizeText(s) {
  return String(s || "").toLowerCase().replace(/\s+/g, " ").trim();
}

/**
 * Fraction of gold fragments that appear (normalized substring) within the
 * top-k snippets. Returns null when there is no gold (not measurable).
 * @param {string[]} gold  known-relevant fragments
 * @param {string[]} snippets  retrieved snippets (ranked)
 * @param {number} k
 * @returns {number|null}
 */
export function recallAtK(gold, snippets, k) {
  if (!Array.isArray(gold) || gold.length === 0) return null;
  const hay = (snippets || []).slice(0, k).map(normalizeText);
  let hits = 0;
  for (const g of gold) {
    const needle = normalizeText(g);
    if (needle && hay.some((h) => h.includes(needle))) hits += 1;
  }
  return hits / gold.length;
}

/**
 * Jaccard overlap of the normalized top-k snippet SETS of two systems — an
 * agreement signal (high when both surface the same passages). 1 if both empty.
 */
export function overlapAtK(a, b, k) {
  const sa = new Set((a || []).slice(0, k).map(normalizeText).filter(Boolean));
  const sb = new Set((b || []).slice(0, k).map(normalizeText).filter(Boolean));
  if (sa.size === 0 && sb.size === 0) return 1;
  let inter = 0;
  for (const x of sa) if (sb.has(x)) inter += 1;
  const union = sa.size + sb.size - inter;
  return union === 0 ? 0 : inter / union;
}

function mean(xs) {
  return xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : 0;
}

/**
 * Aggregate per-query rows into an A/B summary + verdict.
 * @param {Array<{gold:boolean, legacyRecall:number|null, newRecall:number|null,
 *   overlap:number, legacyMs:number, newMs:number}>} rows
 */
export function summarize(rows) {
  const measured = rows.filter((r) => r.gold && r.legacyRecall != null && r.newRecall != null);
  const legacyRecall = mean(measured.map((r) => r.legacyRecall));
  const newRecall = mean(measured.map((r) => r.newRecall));
  const wins = { new: 0, legacy: 0, tie: 0 };
  for (const r of measured) {
    if (r.newRecall > r.legacyRecall) wins.new += 1;
    else if (r.newRecall < r.legacyRecall) wins.legacy += 1;
    else wins.tie += 1;
  }
  return {
    queries: rows.length,
    measured: measured.length,
    legacy: { meanRecall: legacyRecall, meanMs: mean(rows.map((r) => r.legacyMs)) },
    new: { meanRecall: newRecall, meanMs: mean(rows.map((r) => r.newMs)) },
    meanOverlap: mean(rows.map((r) => r.overlap)),
    wins,
    verdict: {
      // The cutover is safe to default-on when the new path's recall is at least
      // as good as legacy on the held-out real queries.
      newAtLeastAsGood: newRecall >= legacyRecall,
      recallDelta: newRecall - legacyRecall,
    },
  };
}

async function safeCall(fn) {
  const t0 = Date.now();
  try {
    const out = await fn();
    return { snippets: Array.isArray(out) ? out : [], ms: Date.now() - t0 };
  } catch {
    return { snippets: [], ms: Date.now() - t0 };
  }
}

/**
 * Run both retrievers over every query and score them.
 * @param {Array<{query:string, scope?:string, gold?:string[]}>} queries
 * @param {{
 *   legacyFn: (query:string, scope:string, k:number) => Promise<string[]>,
 *   newFn: (query:string, k:number) => Promise<string[]>,
 *   k?: number,
 * }} opts
 * @returns {Promise<{rows:object[], summary:object}>}
 */
export async function evaluateAb(queries, { legacyFn, newFn, k = 100 } = {}) {
  const rows = [];
  for (const q of queries) {
    const scope = q.scope || "";
    const gold = Array.isArray(q.gold) ? q.gold : [];
    const [legacy, fresh] = await Promise.all([
      safeCall(() => legacyFn(q.query, scope, k)),
      safeCall(() => newFn(q.query, k)),
    ]);
    rows.push({
      query: q.query,
      gold: gold.length > 0,
      legacyRecall: recallAtK(gold, legacy.snippets, k),
      newRecall: recallAtK(gold, fresh.snippets, k),
      overlap: overlapAtK(legacy.snippets, fresh.snippets, k),
      legacyMs: legacy.ms,
      newMs: fresh.ms,
      legacyCount: legacy.snippets.length,
      newCount: fresh.snippets.length,
    });
  }
  return { rows, summary: summarize(rows) };
}

export default evaluateAb;

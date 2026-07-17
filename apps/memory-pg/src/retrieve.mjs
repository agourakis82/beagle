// retrieve.mjs — Phase 2, Task 2.1: hybrid dense + BM25 retrieval with
// Reciprocal Rank Fusion (RRF) + a recency prior.
//
// Two independent ranking channels are fused by RANK, never by raw score
// (BM25 scores and cosine distances are not comparable, so a linear combination
// of them is meaningless — RRF sidesteps that entirely):
//
//   * Dense  (CTE `dense`): pgvector HNSW cosine over `embeddings.embedding`,
//     joined to current chunks. `SET LOCAL hnsw.ef_search=80` widens recall.
//   * Lexical (CTE `bm25`): ParadeDB pg_search BM25 over `chunks.text`
//     (`text @@@ $query`, scored by `paradedb.score(id)`).
//
// RRF (k=60), rank-based:  rrf = 1/(60+dense_rank) + 1/(60+bm25_rank)
//   A doc missing from a channel contributes 0 from that side. A doc present in
//   BOTH channels is reinforced and outranks single-channel hits at similar
//   ranks. rrf is in (0, 2/61]; we normalize by 2/61 → rrf_norm in (0, 1].
//
// Recency prior:  recency = 0.5 ^ (age_days / half_life(decay_class))
//   age_days from occurred_at (fallback created_at). half_life is per decay
//   class (identity=180d slow, tasks=10d fast). recency in (0, 1].
//
// Final blend (alpha tunable, both terms in (0,1] so they are comparable):
//   score = alpha * rrf_norm + (1 - alpha) * recency
//
// Everything runs in ONE transaction (a single pool client) so `SET LOCAL`
// applies to the fusion query, and a single SQL statement does the fuse.

const RRF_K = 60;
const RRF_NORM = 2 / (RRF_K + 1); // max possible rrf (both ranks == 1)
const CHANNEL_LIMIT = 50;
const HNSW_EF_SEARCH = 80;

const DEFAULT_HALF_LIFE = { identity: 180, tasks: 10 };

/**
 * Hybrid retrieval: dense ⊕ BM25 → RRF → recency-blended score.
 *
 * @param {import("pg").Pool} pool
 * @param {{
 *   queryEmbedding: string|number[], // 1024-dim halfvec literal or array
 *   queryText: string,
 *   k?: number,                       // top-k to return (default 50)
 *   alpha?: number,                   // RRF vs recency weight (default 0.7)
 *   halfLifeDays?: {identity?:number, tasks?:number} // per decay class
 * }} opts
 * @returns {Promise<Array<{
 *   chunk_id: string, record_id: string, text: string, score: number,
 *   dense_rank: number|null, bm25_rank: number|null, occurred_at: string|null
 * }>>}
 */
export async function retrieve(pool, opts) {
  const {
    queryEmbedding,
    queryText,
    k = 50,
    alpha = 0.7,
    halfLifeDays = {},
    // When true, restrict BOTH channels to records whose trust_tier is not
    // 'unverified' (a NULL tier counts as untrusted). Used to populate the
    // companion's authoritative "what he told me" grounding directly from his own
    // trusted words, instead of recalling the full noisy pool and filtering it
    // down to scraps after top-k.
    trustedOnly = false,
  } = opts;

  if (queryEmbedding == null) throw new Error("retrieve: queryEmbedding required");
  if (queryText == null) throw new Error("retrieve: queryText required");

  const embLit = Array.isArray(queryEmbedding)
    ? "[" + queryEmbedding.join(",") + "]"
    : queryEmbedding;

  const halfLife = { ...DEFAULT_HALF_LIFE, ...halfLifeDays };

  // Build a per-decay-class half-life lookup as a CASE so callers can tune it
  // without a DB table. Unknown classes fall back to the identity half-life.
  const hlIdentity = Number(halfLife.identity) || DEFAULT_HALF_LIFE.identity;
  const hlTasks = Number(halfLife.tasks) || DEFAULT_HALF_LIFE.tasks;

  // $1 embedding, $2 queryText, $3 channel LIMIT, $4 RRF_K, $5 RRF_NORM,
  // $6 alpha, $7 hlIdentity, $8 hlTasks, $9 k, $10 trustedOnly
  const sql = `
WITH dense AS (
  SELECT e.chunk_id,
         row_number() OVER (ORDER BY e.embedding <=> $1::halfvec ASC) AS dense_rank
  FROM embeddings e
  JOIN chunks c ON c.id = e.chunk_id
  JOIN records r ON r.id = c.record_id
  WHERE e.is_current
    AND (NOT $10::bool OR COALESCE(r.trust_tier, 'unverified') <> 'unverified')
  ORDER BY e.embedding <=> $1::halfvec ASC
  LIMIT $3
),
bm25 AS (
  SELECT c.id AS chunk_id,
         row_number() OVER (ORDER BY paradedb.score(c.id) DESC) AS bm25_rank
  FROM chunks c
  JOIN records r2 ON r2.id = c.record_id
  -- paradedb.match (NOT raw \`text @@@ $2\`): the query-string parser errors on
  -- Tantivy special chars in natural queries (apostrophe in "cluster's", a
  -- trailing "?", etc.). match() treats the input as analyzed terms, so any user
  -- text is safe and still scored/ranked by BM25.
  WHERE c.id @@@ paradedb.match('text', $2)
    AND (NOT $10::bool OR COALESCE(r2.trust_tier, 'unverified') <> 'unverified')
  ORDER BY paradedb.score(c.id) DESC
  LIMIT $3
),
fused AS (
  SELECT
    COALESCE(d.chunk_id, b.chunk_id) AS chunk_id,
    d.dense_rank,
    b.bm25_rank,
    ( COALESCE(1.0 / ($4 + d.dense_rank), 0)
    + COALESCE(1.0 / ($4 + b.bm25_rank), 0) ) AS rrf
  FROM dense d
  FULL OUTER JOIN bm25 b ON b.chunk_id = d.chunk_id
),
scored AS (
  SELECT
    f.chunk_id,
    c.record_id,
    c.text,
    f.dense_rank,
    f.bm25_rank,
    r.occurred_at,
    r.trust_tier,
    (f.rrf / $5) AS rrf_norm,
    power(
      0.5,
      EXTRACT(EPOCH FROM (now() - COALESCE(r.occurred_at, r.created_at)))
        / 86400.0
        / CASE r.decay_class WHEN 'tasks' THEN $8::float ELSE $7::float END
    ) AS recency
  FROM fused f
  JOIN chunks c ON c.id = f.chunk_id
  JOIN records r ON r.id = c.record_id
)
SELECT
  chunk_id, record_id, text, dense_rank, bm25_rank, occurred_at, trust_tier,
  ($6::float * rrf_norm + (1 - $6::float) * recency) AS score
FROM scored
ORDER BY score DESC, chunk_id
LIMIT $9;
`;

  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    await client.query(`SET LOCAL hnsw.ef_search = ${HNSW_EF_SEARCH}`);
    const res = await client.query(sql, [
      embLit, // $1
      queryText, // $2
      CHANNEL_LIMIT, // $3
      RRF_K, // $4
      RRF_NORM, // $5
      alpha, // $6
      hlIdentity, // $7
      hlTasks, // $8
      k, // $9
      trustedOnly, // $10
    ]);
    await client.query("COMMIT");
    return res.rows.map((row) => ({
      chunk_id: row.chunk_id,
      record_id: row.record_id,
      text: row.text,
      score: Number(row.score),
      dense_rank: row.dense_rank == null ? null : Number(row.dense_rank),
      bm25_rank: row.bm25_rank == null ? null : Number(row.bm25_rank),
      occurred_at: row.occurred_at,
      trust_tier: row.trust_tier,
    }));
  } catch (err) {
    await client.query("ROLLBACK");
    throw err;
  } finally {
    client.release();
  }
}

export default retrieve;

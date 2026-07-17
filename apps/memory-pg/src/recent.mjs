// recent.mjs — recency-ordered pull of his TRUSTED records, for the no-topic
// synthesis path. Recall (/query) is semantic and needs a query; this is the
// deterministic "what has he committed to record lately" source.
export async function recentTrusted(pool, { windowDays = 7, limit = 12 } = {}) {
  const days = Math.min(Math.max(Number(windowDays) || 7, 1), 90);
  const lim = Math.min(Math.max(Number(limit) || 12, 1), 50);
  const { rows } = await pool.query(
    `SELECT content, source_type, occurred_at, trust_tier
       FROM records
      WHERE trust_tier <> 'unverified'
        AND COALESCE(occurred_at, created_at) >= now() - ($1 || ' days')::interval
      ORDER BY COALESCE(occurred_at, created_at) DESC
      LIMIT $2`,
    [String(days), lim]);
  return rows.map((r) => ({
    text: r.content, source_type: r.source_type,
    occurred_at: r.occurred_at, trust_tier: r.trust_tier,
  }));
}
export default recentTrusted;

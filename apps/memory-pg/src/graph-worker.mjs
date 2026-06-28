// graph-worker.mjs — Phase 4, Task 4.3: SKIP-LOCKED drain of the pending_graph
// outbox. Mirrors the embed worker: claim a batch atomically (FOR UPDATE SKIP
// LOCKED, with an inherent reaper via locked_until), extract a knowledge graph
// from each record via the sovereign LLM, apply it bi-temporally, mark done.
// Failures retry up to maxRetries, then move to the failed_graph DLQ.

import { extractGraph, applyExtraction } from "./graph-extract.mjs";

/**
 * Process one batch of pending_graph rows.
 * @param {import("pg").Pool} pool
 * @param {{
 *   llmFn: (prompt:string)=>Promise<string>,
 *   embedFn?: (texts:string[])=>Promise<number[][]>,
 *   batch?: number,
 *   maxRetries?: number,
 * }} opts
 * @returns {Promise<{claimed:number, processed:number, facts:number, entities:number, failed:number}>}
 */
export async function runGraphOnce(pool, opts) {
  const { llmFn, embedFn = null, batch = 8, maxRetries = 3 } = opts || {};
  if (typeof llmFn !== "function") throw new Error("runGraphOnce: llmFn required");

  const claimed = await pool.query(
    `UPDATE pending_graph
        SET status='processing', locked_until = now() + interval '10 minutes'
      WHERE id IN (
        SELECT id FROM pending_graph
         WHERE status='pending' OR (status='processing' AND locked_until < now())
         ORDER BY id FOR UPDATE SKIP LOCKED LIMIT $1)
      RETURNING id, record_id, retry_count`,
    [batch],
  );

  const stats = { claimed: claimed.rowCount, processed: 0, facts: 0, entities: 0, failed: 0 };

  for (const row of claimed.rows) {
    try {
      const rec = await pool.query(
        "SELECT content, occurred_at FROM records WHERE id = $1",
        [row.record_id],
      );
      if (rec.rowCount === 0) {
        // record gone — drop the queue row as done (nothing to extract)
        await pool.query("UPDATE pending_graph SET status='done' WHERE id=$1", [row.id]);
        stats.processed++;
        continue;
      }
      const extraction = await extractGraph({ content: rec.rows[0].content }, { llmFn });
      const applied = await applyExtraction(pool, extraction, {
        recordId: row.record_id,
        embedFn,
        occurredAt: rec.rows[0].occurred_at,
      });
      stats.facts += applied.factsInserted;
      stats.entities += applied.entitiesResolved;
      await pool.query("UPDATE pending_graph SET status='done' WHERE id=$1", [row.id]);
      stats.processed++;
    } catch (err) {
      const next = row.retry_count + 1;
      if (next > maxRetries) {
        await pool.query(
          "INSERT INTO failed_graph (id, record_id, status, retry_count, created_at) " +
            "SELECT id, record_id, 'failed', $2, created_at FROM pending_graph WHERE id=$1",
          [row.id, next],
        );
        await pool.query("DELETE FROM pending_graph WHERE id=$1", [row.id]);
        stats.failed++;
      } else {
        await pool.query(
          "UPDATE pending_graph SET status='pending', retry_count=$2, locked_until=NULL WHERE id=$1",
          [row.id, next],
        );
      }
    }
  }
  return stats;
}

export default runGraphOnce;

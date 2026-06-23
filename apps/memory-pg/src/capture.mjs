// capture.mjs — Phase 1, Task 1.2: transactional outbox capture.
//
// `captureRecord` writes a record + its chunks + a pending_embeddings queue row
// in ONE transaction. This is the ACID core that replaces the corruption-prone
// JSONL append: concurrent captures can never produce partial/interleaved rows,
// and re-capturing identical content is a no-op (idempotent on content_sha256).

import crypto from "node:crypto";
import { chunkText } from "./chunk.mjs";

function sha256hex(s) {
  return crypto.createHash("sha256").update(s).digest("hex");
}

/**
 * Capture a record transactionally.
 *
 * @param {import("pg").Pool} pool
 * @param {{
 *   source_type: string,
 *   content: string,
 *   metadata?: object,
 *   occurred_at?: string|Date|null,
 *   privacy_class?: string,
 *   decay_class?: string,
 * }} rec
 * @returns {Promise<{id: string, created: boolean, chunk_count: number}>}
 */
export async function captureRecord(pool, rec) {
  const {
    source_type,
    content,
    metadata = {},
    occurred_at = null,
    privacy_class = "sensitive",
    decay_class = "identity",
  } = rec;

  if (!source_type) throw new Error("captureRecord: source_type is required");
  if (typeof content !== "string" || content.length === 0) {
    throw new Error("captureRecord: content must be a non-empty string");
  }

  const content_sha256 = sha256hex(content);

  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    // Insert the record; on duplicate content_sha256 do nothing.
    const ins = await client.query(
      `INSERT INTO records
         (source_type, content, metadata, occurred_at, content_sha256, privacy_class, decay_class)
       VALUES ($1, $2, $3::jsonb, $4, $5, $6, $7)
       ON CONFLICT (content_sha256) DO NOTHING
       RETURNING id`,
      [
        source_type,
        content,
        JSON.stringify(metadata),
        occurred_at,
        content_sha256,
        privacy_class,
        decay_class,
      ],
    );

    // Duplicate: nothing inserted. Roll back and return the existing id.
    if (ins.rowCount === 0) {
      await client.query("ROLLBACK");
      const existing = await client.query(
        "SELECT id FROM records WHERE content_sha256 = $1",
        [content_sha256],
      );
      return { id: existing.rows[0].id, created: false, chunk_count: 0 };
    }

    const id = ins.rows[0].id;
    const chunks = chunkText(content);

    if (chunks.length > 0) {
      // Bulk insert chunks in a single multi-row statement.
      const values = [];
      const params = [];
      let p = 1;
      for (const ch of chunks) {
        values.push(`($${p++}, $${p++}, $${p++}, $${p++})`);
        params.push(id, ch.chunk_index, ch.text, ch.sha256);
      }
      await client.query(
        `INSERT INTO chunks (record_id, chunk_index, text, content_sha256)
         VALUES ${values.join(", ")}`,
        params,
      );
    }

    // Enqueue exactly one outbox row for the embed worker.
    await client.query(
      "INSERT INTO pending_embeddings (record_id) VALUES ($1)",
      [id],
    );

    await client.query("COMMIT");
    return { id, created: true, chunk_count: chunks.length };
  } catch (err) {
    await client.query("ROLLBACK");
    throw err;
  } finally {
    client.release();
  }
}

export default captureRecord;

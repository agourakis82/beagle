// embed-worker.mjs — Phase 1, Task 1.3: the SKIP-LOCKED embed worker.
//
// This is the reliability heart of the pipeline. `runOnce` claims a batch of
// pending_embeddings rows using `FOR UPDATE SKIP LOCKED` (so N workers can run
// concurrently and partition the queue with zero contention and no double-work),
// embeds each record's chunks via an injected `embedFn`, upserts the vectors,
// and removes the queue row on success. Each row is processed in its OWN
// transaction so a single failure can never abort another row's work.
//
// Reliability invariants:
//   * incremental  — only un-embedded queue rows are touched.
//   * idempotent   — ON CONFLICT (chunk_id, model_version) DO UPDATE; replaying
//                    the same record never duplicates embeddings.
//   * retry        — on error the row returns to 'pending', retry_count++.
//   * DLQ          — once retry_count exceeds maxRetries the row is moved to
//                    failed_embeddings (never silently dropped).
//   * reaper       — the claim query re-picks rows whose locked_until < now(),
//                    so a crashed worker's in-flight rows are reclaimed after the
//                    lease expires (no separate reaper process needed).

/**
 * Format an array of numbers as a pgvector / halfvec literal string.
 * e.g. [1, 0, 0] -> "[1,0,0]"  (cast to ::halfvec at the call site).
 * @param {number[]} nums
 * @returns {string}
 */
export function toVectorLiteral(nums) {
  return "[" + nums.join(",") + "]";
}

/**
 * Build a real TEI embedFn that POSTs to the sovereign bge-m3 endpoint.
 *
 * The TEI/sovereign embedder accepts a batched `{ "inputs": [..] }` and returns
 * `[[..], [..], ..]` (one 1024-dim vector per input). A single-vector reply is
 * normalized to a 1-element batch. Texts are split into sub-batches of size
 * `teiBatch` and each request is bounded by `timeoutMs`.
 *
 * Shared by bin/embed-worker.mjs (background drainer) and bin/serve.mjs (query
 * embedding) so the transport + response normalization live in exactly one place.
 *
 * @param {string} url  full POST URL of the embed endpoint (e.g. .../embed)
 * @param {{ timeoutMs?: number, teiBatch?: number,
 *           acquire?: () => Promise<void> }} [opts]
 * @returns {(texts: string[]) => Promise<number[][]>}
 */
export function makeTeiEmbedFn(url, opts = {}) {
  if (!url) throw new Error("makeTeiEmbedFn: url is required");
  const timeoutMs = opts.timeoutMs ?? 30000;
  const teiBatch = opts.teiBatch ?? 32;
  // Optional token-bucket gate (the worker passes one to throttle TEI; serve
  // does single-text queries so it can omit it).
  const acquire = typeof opts.acquire === "function" ? opts.acquire : async () => {};

  async function embedBatch(texts) {
    await acquire();
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), timeoutMs);
    try {
      const resp = await fetch(url, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ inputs: texts }),
        signal: ctrl.signal,
      });
      if (!resp.ok) {
        throw new Error(`TEI ${resp.status}: ${(await resp.text()).slice(0, 200)}`);
      }
      const out = await resp.json();
      // TEI returns [[..], ..]; normalize a single-vector reply to a 1-elem batch.
      const vectors =
        Array.isArray(out) && out.length && Array.isArray(out[0]) ? out : [out];
      if (vectors.length !== texts.length) {
        throw new Error(
          `TEI returned ${vectors.length} vectors for ${texts.length} inputs`,
        );
      }
      return vectors.map((v) => v.map(Number));
    } finally {
      clearTimeout(timer);
    }
  }

  return async function embedFn(texts) {
    const out = [];
    for (let i = 0; i < texts.length; i += teiBatch) {
      const part = await embedBatch(texts.slice(i, i + teiBatch));
      out.push(...part);
    }
    return out;
  };
}

/**
 * Process at most `batch` pending embedding jobs once.
 *
 * @param {import("pg").Pool} pool
 * @param {{
 *   embedFn: (texts: string[]) => (number[][] | Promise<number[][]>),
 *   batch?: number,
 *   modelVersion?: string,
 *   maxRetries?: number,
 * }} opts
 * @returns {Promise<{claimed:number, embedded:number, failed:number}>}
 */
export async function runOnce(pool, opts) {
  const {
    embedFn,
    batch = 50,
    modelVersion = "bge-m3",
    maxRetries = 3,
  } = opts || {};

  if (typeof embedFn !== "function") {
    throw new Error("runOnce: embedFn is required");
  }

  // 1. Claim a batch atomically. FOR UPDATE SKIP LOCKED lets concurrent workers
  //    grab disjoint rows. We also re-pick stale 'processing' rows (reaper).
  const claimed = await pool.query(
    `UPDATE pending_embeddings
        SET status='processing', locked_until = now() + interval '5 minutes'
      WHERE id IN (
        SELECT id FROM pending_embeddings
         WHERE status='pending'
            OR (status='processing' AND locked_until < now())
         ORDER BY id
         FOR UPDATE SKIP LOCKED
         LIMIT $1
      )
      RETURNING id, record_id, retry_count`,
    [batch],
  );

  let embedded = 0;
  let failed = 0;

  for (const row of claimed.rows) {
    try {
      embedded += await processRow(pool, row, embedFn, modelVersion);
    } catch (err) {
      failed += 1;
      await failRow(pool, row, maxRetries, err);
    }
  }

  return { claimed: claimed.rowCount, embedded, failed };
}

/**
 * Embed one record's chunks and remove the queue row, in a single transaction.
 * Throws on any error so the caller can route the row to retry/DLQ.
 * @returns {Promise<number>} number of embeddings written.
 */
async function processRow(pool, row, embedFn, modelVersion) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    const chunks = await client.query(
      "SELECT id, text FROM chunks WHERE record_id = $1 ORDER BY chunk_index",
      [row.record_id],
    );

    let written = 0;
    if (chunks.rows.length > 0) {
      const texts = chunks.rows.map((c) => c.text);
      const vectors = await embedFn(texts);

      if (!Array.isArray(vectors) || vectors.length !== texts.length) {
        throw new Error(
          `embedFn returned ${vectors && vectors.length} vectors for ${texts.length} texts`,
        );
      }

      for (let i = 0; i < chunks.rows.length; i++) {
        const vec = vectors[i];
        if (!Array.isArray(vec) || vec.length === 0) {
          throw new Error(`embedFn returned an invalid vector at index ${i}`);
        }
        await client.query(
          `INSERT INTO embeddings (chunk_id, embedding, model_version, is_current)
             VALUES ($1, $2::halfvec, $3, true)
           ON CONFLICT (chunk_id, model_version)
             DO UPDATE SET embedding = EXCLUDED.embedding, is_current = true`,
          [chunks.rows[i].id, toVectorLiteral(vec), modelVersion],
        );
        written += 1;
      }
    }

    // Success: drop the queue row.
    await client.query("DELETE FROM pending_embeddings WHERE id = $1", [row.id]);
    await client.query("COMMIT");
    return written;
  } catch (err) {
    await client.query("ROLLBACK").catch(() => {});
    throw err;
  } finally {
    client.release();
  }
}

/**
 * Route a failed row to retry (back to 'pending', retry_count++) or, once
 * retry_count exceeds maxRetries, to failed_embeddings (DLQ). Done in its own
 * transaction so it is independent of the failed processRow transaction.
 */
async function failRow(pool, row, maxRetries, _err) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    const upd = await client.query(
      `UPDATE pending_embeddings
          SET status='pending', retry_count = retry_count + 1, locked_until = NULL
        WHERE id = $1
        RETURNING retry_count`,
      [row.id],
    );

    // Row may have been deleted/claimed elsewhere; nothing to do.
    if (upd.rowCount === 0) {
      await client.query("COMMIT");
      return;
    }

    const retryCount = upd.rows[0].retry_count;
    if (retryCount > maxRetries) {
      // Move to the dead-letter queue, then remove from pending.
      await client.query(
        `INSERT INTO failed_embeddings
           SELECT * FROM pending_embeddings WHERE id = $1`,
        [row.id],
      );
      await client.query("DELETE FROM pending_embeddings WHERE id = $1", [
        row.id,
      ]);
    }

    await client.query("COMMIT");
  } catch (err) {
    await client.query("ROLLBACK").catch(() => {});
    throw err;
  } finally {
    client.release();
  }
}

export default runOnce;

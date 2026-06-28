// backfill-jsonl.mjs — Phase 3 full backfill by STREAMING the canonical JSONL.
//
// The legacy beagle-core export has no pagination and a full export is ~330MB+;
// fetching it whole would spike the live brain and the import heap. Instead we
// stream the canonical per-kind JSONL files line-by-line (each line = one
// record), route each through the shared extractFromRecord (privacy filter +
// passage-per-turn + kind→text), and captureRecord it. Constant memory,
// restartable, idempotent (captureRecord dedups on content_sha256). Zero load on
// beagle-core — it reads the files directly.

import { createInterface } from "node:readline";
import { extractFromRecord, candidateToRecord } from "./backfill.mjs";

/**
 * Stream one kind's JSONL from a Readable and capture every extracted candidate.
 * Bounded concurrency keeps a steady number of captures in flight (the import is
 * insert-only — embedding happens later via the embed-worker draining the outbox).
 *
 * @param {import("node:stream").Readable} readable  source of newline-delimited JSON
 * @param {string} kind  MemoryEpisode|MemoryAtom|MemoryWorld|ConversationPassage
 * @param {{
 *   capture: (rec: object) => Promise<{id:string, created:boolean}>,
 *   concurrency?: number,
 *   onProgress?: (stats: object) => void,
 *   progressEvery?: number,
 * }} opts
 * @returns {Promise<{lines:number, badLines:number, candidates:number, created:number, duplicate:number, errors:number}>}
 */
export async function backfillJsonlStream(readable, kind, opts = {}) {
  const { capture, concurrency = 8, onProgress, progressEvery = 2000 } = opts;
  if (typeof capture !== "function") throw new Error("backfillJsonlStream: opts.capture required");

  const stats = { lines: 0, badLines: 0, candidates: 0, created: 0, duplicate: 0, errors: 0 };
  const rl = createInterface({ input: readable, crlfDelay: Infinity });

  let inflight = new Set();
  const pump = async (rec) => {
    try {
      const res = await capture(rec);
      if (res && res.created) stats.created++;
      else stats.duplicate++;
    } catch {
      stats.errors++;
    }
    if (onProgress && (stats.created + stats.duplicate + stats.errors) % progressEvery === 0) {
      onProgress(stats);
    }
  };

  for await (const line of rl) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    stats.lines++;
    let item;
    try {
      item = JSON.parse(trimmed);
    } catch {
      stats.badLines++;
      continue;
    }
    const recs = extractFromRecord(kind, item).map(candidateToRecord);
    for (const rec of recs) {
      stats.candidates++;
      const p = pump(rec).finally(() => inflight.delete(p));
      inflight.add(p);
      if (inflight.size >= concurrency) await Promise.race(inflight);
    }
  }
  await Promise.all(inflight);
  return stats;
}

export default backfillJsonlStream;

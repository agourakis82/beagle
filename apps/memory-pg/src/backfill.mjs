// backfill.mjs — Phase 3, Task 3.1: migration backfill importer.
//
// The legacy beagle-core export (POST /api/exocortex/v1/memory/export) is a
// single JSON document: { episodes, atoms, worlds, passages }. The dead LanceDB
// worker flattened it via `iter_candidates` (privacy filter, kind→text
// selection, conversation-passage expansion). We reproduce the *invariants* of
// that flattening and feed every row through the live ACID `captureRecord`:
//
//   • exclude `restricted` records (never indexed — health/biography sensitivity)
//   • text-bearing rows only
//   • idempotent: captureRecord dedups on content_sha256, so re-running backfill
//     against the same (or an overlapping) export creates nothing new
//   • HNSW is rebuilt only AFTER the bulk load (drop → load → drain → rebuild),
//     so we don't pay per-row index maintenance during a 100k+ import.
//
// Granularity note: conversation passages are captured one record PER TURN, not
// per sliding-window like the old path. LanceDB stored per-window vectors, so it
// pre-chunked; memory-pg has a real `chunks` table + segment-aware chunker, so
// the turn is the right record and `chunkText` does the windowing downstream.

import crypto from "node:crypto";
import { readFile } from "node:fs/promises";
import { captureRecord } from "./capture.mjs";

function textHash(s) {
  return "sha256:" + crypto.createHash("sha256").update(s).digest("hex");
}

function recordText(item, kind) {
  if (kind === "MemoryAtom") return String(item.text || item.normalized_text || "");
  if (kind === "MemoryEpisode") {
    return String(item.summary || item.content_preview || item.source_ref || "");
  }
  if (kind === "MemoryWorld") {
    return ["label", "summary", "project_slug", "merkle_root"]
      .map((k) => String(item[k] || ""))
      .join(" ");
  }
  return "";
}

function makeCandidate(item, kind, content, canonicalId, opts = {}) {
  return {
    canonical_id: canonicalId,
    kind,
    content,
    content_hash: String(item.content_hash || textHash(content)),
    privacy_class: String(item.privacy_class || "sensitive").toLowerCase(),
    occurred_at: String(opts.occurred_at ?? item.occurred_at ?? item.created_at ?? ""),
    provenance: opts.provenance ?? item.provenance ?? {},
    source_refs: item.source_refs ?? [],
    chronoself_commit: String(item.chronoself_commit || ""),
  };
}

// Export field name -> record kind. Single source of truth shared by the
// whole-export backfill and the per-record dual-write capture endpoint, so both
// produce byte-identical memory-pg rows (no ingest/migration drift).
export const KIND_BY_FIELD = {
  episodes: "MemoryEpisode",
  atoms: "MemoryAtom",
  worlds: "MemoryWorld",
  passages: "ConversationPassage",
};

function isRestricted(item) {
  return String(item.privacy_class || "sensitive").toLowerCase() === "restricted";
}

/**
 * Flatten ONE beagle-core record (of the given kind) into capture-ready
 * candidate rows. Pure. A conversation passage expands to one candidate per
 * non-empty turn; everything else yields 0 or 1. Restricted records yield none.
 * This is the shared unit used by both the backfill and the /capture endpoint.
 * @param {string} kind  one of MemoryEpisode|MemoryAtom|MemoryWorld|ConversationPassage
 * @param {object} item  the raw record
 * @returns {Array<object>}
 */
export function extractFromRecord(kind, item) {
  const out = [];
  if (!item || typeof item !== "object" || isRestricted(item)) return out;

  if (kind === "ConversationPassage") {
    const passageId = String(item.id || textHash(JSON.stringify(item)));
    const occurred_at = String(item.occurred_at || "");
    const provenance =
      item.provenance || { session_id: item.session_id, source_platform: item.source_platform };
    const turns = item.turns || [];
    for (let i = 0; i < turns.length; i++) {
      const content = String((turns[i] || {}).content || "");
      if (!content.trim()) continue;
      out.push(
        makeCandidate(item, "ConversationPassage", content, `passage:${passageId}:${i}`, {
          occurred_at,
          provenance,
        }),
      );
    }
    return out;
  }

  const text = recordText(item, kind);
  if (!text.trim()) return out;
  const canonicalId = String(item.id || item.source_ref || textHash(text));
  out.push(makeCandidate(item, kind, text, canonicalId));
  return out;
}

/**
 * Flatten a parsed beagle-core export into capture-ready candidate rows.
 * Pure (no DB). Mirrors the legacy iter_candidates invariants.
 * @param {{episodes?:any[],atoms?:any[],worlds?:any[],passages?:any[]}} exp
 * @returns {Array<object>}
 */
export function extractCandidates(exp) {
  const out = [];
  for (const [field, kind] of Object.entries(KIND_BY_FIELD)) {
    for (const item of exp[field] || []) out.push(...extractFromRecord(kind, item));
  }
  return out;
}

/**
 * Map a candidate to the captureRecord argument shape.
 * @returns {{source_type:string,content:string,metadata:object,occurred_at:(string|null),privacy_class:string}}
 */
export function candidateToRecord(c) {
  const occurred_at = c.occurred_at && String(c.occurred_at).trim() ? c.occurred_at : null;
  return {
    source_type: c.kind,
    content: c.content,
    occurred_at,
    privacy_class: c.privacy_class,
    metadata: {
      canonical_id: c.canonical_id,
      kind: c.kind,
      content_hash: c.content_hash,
      source_refs: c.source_refs,
      provenance: c.provenance,
      chronoself_commit: c.chronoself_commit,
      migrated_from: "beagle-core-export",
    },
  };
}

/**
 * Import a beagle-core export file into memory-pg via captureRecord.
 * Idempotent; restricted records are excluded and counted.
 * @param {import("pg").Pool} pool
 * @param {string} exportFile
 * @param {{onProgress?:(stats:object)=>void, progressEvery?:number}} [opts]
 */
export async function backfill(pool, exportFile, opts = {}) {
  const raw = await readFile(exportFile, "utf8");
  const exp = JSON.parse(raw);

  const restrictedExcluded =
    countRestricted(exp.episodes) +
    countRestricted(exp.atoms) +
    countRestricted(exp.worlds) +
    countRestricted(exp.passages);

  const candidates = extractCandidates(exp);
  const stats = { seen: candidates.length, created: 0, duplicate: 0, restricted_excluded: restrictedExcluded };

  const every = opts.progressEvery || 500;
  for (const cand of candidates) {
    const res = await captureRecord(pool, candidateToRecord(cand));
    if (res.created) stats.created++;
    else stats.duplicate++;
    if (opts.onProgress && (stats.created + stats.duplicate) % every === 0) opts.onProgress(stats);
  }
  return stats;
}

function countRestricted(arr) {
  let n = 0;
  for (const item of arr || []) {
    if (String(item.privacy_class || "sensitive").toLowerCase() === "restricted") n++;
  }
  return n;
}

// ---- HNSW index management (build-after-bulk-load) ----
// Definition mirrors sql/001_core.sql exactly.

export async function dropEmbeddingIndex(pool) {
  await pool.query("DROP INDEX IF EXISTS embeddings_hnsw");
}

export async function rebuildEmbeddingIndex(pool) {
  await pool.query(
    `CREATE INDEX IF NOT EXISTS embeddings_hnsw ON embeddings
       USING hnsw (embedding halfvec_cosine_ops)
       WITH (m=16, ef_construction=128) WHERE is_current`,
  );
}

export default backfill;

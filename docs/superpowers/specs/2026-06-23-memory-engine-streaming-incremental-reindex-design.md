# Memory-Engine Streaming + Incremental Reindex — Design

**Date:** 2026-06-23
**Author:** Demetrios Agourakis (with Claude)
**Status:** design — pending review
**Related:** [[project_exocortex_ingest_constraints]] (findings 5–7), `apps/beagle-memory-engine/`

## Problem

The semantic reindex OOMs as the corpus grows, and the corpus only grows. On 2026-06-23 a
full-corpus rebuild (`limit=100000`) OOMKilled the memory-engine (`exit 137`) even at a **96Gi**
limit, leaving the index partial (~42k rows; canonical store intact at 146,253 records / 466MB).

**Root cause — measured, not assumed.** It is *not* the Rust server (a thin HTTP/orchestration
shell) and *not* the embedding step (already batched at `BUILD_BATCH_SIZE=1000`, peak ~one batch).
The blowup is the **upfront full-corpus materialization in the Python worker**
(`apps/beagle-memory-engine/workers/semantic_backbone.py`), which happens on **both** the full and
the incremental paths:

1. `export = load_json(args.export)` — parses the entire ~300–466MB export JSON into a Python dict.
   Python object overhead multiplies on-disk size several-fold.
2. `candidates, _ = collect_candidates(export)` — builds a Python **list of every candidate row**,
   each carrying `text[:12000]`. Conversation passages **explode** (each turn → up to
   `MAX_WINDOWS_PER_TURN=64` ~800-char windows), so 146k source records become potentially millions
   of candidate dicts, all resident at once.
3. The incremental path still calls `collect_candidates(export)` to compute `cur` and `to_upsert`,
   so **even incremental loads the whole corpus into memory** before doing its cheap delta write.

Both (1) and (2) scale O(corpus). Language is irrelevant; the architecture materializes everything.

## Goals

- **Flat reindex memory**: peak memory bounded by *one batch + a lightweight id→hash manifest*, not
  by corpus size. The corpus can grow to millions of records without OOM.
- **Keep the existing, correct incremental delta logic** (manifest diff → upsert changed, delete
  stale, skip unchanged) — only change *how data is fed into it*.
- **Ship the OOM fix with minimal blast radius first** (worker-only, no beagle-core change), then a
  network-efficiency follow-up.
- No behavior change to query/serving; identical index contents vs. the current code on the same input.

## Non-Goals

- Rewriting the worker in Rust (does not address the architectural cause; loses the Python ML
  ecosystem — lancedb, TEI client).
- Changing the embedding model, schema, or LanceDB layout.
- Distributed/sharded indexing (out of scope; flat-memory single-node is sufficient for the corpus
  trajectory).

## Approach (two phases)

### Phase 1 — Worker streaming (ships first; fixes the OOM; no beagle-core change)

Replace `load_json` + `collect_candidates` (which return whole structures) with **streaming
generators** that parse the export file incrementally and yield candidate rows one at a time.

- **Streaming parse**: iterate the export file with `ijson` (added to `requirements.txt`) over each
  top-level array (`episodes`, `atoms`, `worlds`, `passages`) instead of `json.load` of the whole
  object. Never hold the full parsed dict.
- **Generator candidates**: `iter_candidates(export_path) -> Iterator[dict]` yields the same
  candidate dicts `collect_candidates` produced (passage expansion included), one at a time, so the
  full list is never resident.
- **Two streaming passes in `rebuild()`** (disk re-read is cheap vs. RAM):
  1. *Manifest pass*: stream candidates, build `cur = {canonical_id: content_hash}` keeping **only
     the two strings per row** (drop `text`/content). This is the only corpus-proportional structure
     and is ~1–2 orders of magnitude smaller than the full candidate list.
  2. *Write pass*: stream candidates again; for each whose id is in the upsert set (changed/new, or
     all ids in full mode), accumulate into a batch; at `BUILD_BATCH_SIZE`, `encode_rows` +
     `merge_insert` (incremental) or create/append (full), then free the batch.
- Peak memory ≈ `len(cur) * ~120 bytes` + one batch of embeddings. Independent of total content size.
- The existing `restricted` exclusion, passage windowing, deletion of stale ids, `optimize()`
  compaction, and the incremental/full/fallback control flow are **preserved unchanged**.

**Why this is safe**: the candidate dicts produced are byte-identical to today's; only their
*lifetime* changes (streamed, not all-resident). A golden test pins this.

### Phase 2 — Server-side manifest diff (network + memory both flat; follow-up)

Even in Phase 1 the worker still reads the full export file (the Rust server still fetches the whole
corpus from beagle-core and writes it to disk). Phase 2 removes that:

- beagle-core gains two endpoints:
  - `GET /api/exocortex/v1/memory/export/manifest` → **streaming NDJSON of `{canonical_id,
    content_hash}` only** (no content). Cheap to produce and transfer.
  - `POST /api/exocortex/v1/memory/export/by-ids` → full content for a given set of canonical ids
    (the deltas), streamed.
- Worker flow: fetch manifest → diff against local sidecar manifest → request content for **only the
  changed ids** → embed + merge_insert. Unchanged rows are never serialized, transferred, or parsed.
- The full-rebuild path keeps the existing whole-export endpoint (rare maintenance op).

Phase 2 is a beagle-core (Rust) + worker change; it is the durable network-efficiency win but is
**not required to fix the OOM** — Phase 1 does that.

## Data flow (Phase 1)

```
beagle-core /export (whole corpus JSON) ──> Rust writes export file on disk (engine-state PVC)
   └─ worker: ijson stream over export file
        ├─ pass 1: build cur {id: hash}     (lean, corpus-proportional but tiny)
        ├─ load prev manifest (sidecar)      → diff: to_upsert = changed/new, stale = removed
        └─ pass 2: stream candidates → batch(changed) → encode_rows → merge_insert → free
   └─ optimize() compaction → write new manifest → report row_count
```

## Recovery of the current partial index

After Phase 1 ships (and the hardened `exocortex-6d83ad5a` baseline is deployed): run one controlled
**full** rebuild with live `kubectl top pod` watching. With streaming, peak memory should be a few
hundred MB + one batch. If confirmed, subsequent ingests use the cheap incremental path. The
beagle-core `BEAGLE_REINDEX_LIMIT` env (default 1_000_000) is only safe to rely on once a full
streaming rebuild is proven to fit; until then deploy beagle-core with a conservative limit.

## Testing strategy

- **Golden equivalence**: a fixture export (episodes + atoms + worlds + multi-turn passages) →
  assert `list(iter_candidates(file)) == collect_candidates(load_json(file))[0]` (same rows, order).
- **Streaming correctness**: passage windowing, restricted exclusion, content-hash, canonical_id all
  identical to the current code on the fixture.
- **Memory bound**: build a large synthetic export (e.g. 20k passage records → hundreds of k
  windows); run the manifest pass under `tracemalloc`; assert peak does **not** scale with the full
  content size (compare against `json.load` of the same file as the baseline it must beat).
- **Incremental diff**: with a prev manifest, only changed/new ids are upserted and removed ids
  deleted — same counters as today.
- Phase 2: contract tests for the manifest + by-ids endpoints; worker delta-fetch path.

## Risks

- `ijson` parsing differences vs `json.load` for unusual encodings → mitigated by the golden test.
- Two-pass disk read doubles file I/O on the export file (acceptable; bounded, sequential, on the
  engine-state PVC).
- Phase 2 endpoints add surface to beagle-core → gated behind the existing operator auth; full-export
  endpoint retained for fallback.

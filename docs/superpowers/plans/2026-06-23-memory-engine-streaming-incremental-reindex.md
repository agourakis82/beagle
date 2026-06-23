# Memory-Engine Streaming + Incremental Reindex — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the semantic reindex memory-flat (bounded by one batch + a lean id→hash manifest, not by corpus size) so it stops OOMing as the corpus grows.

**Architecture:** The OOM is the Python worker materializing the entire export (`json.load`) and the entire candidate list (`collect_candidates`, with passage explosion) before batching. Phase 1 replaces both with streaming generators (`ijson`) and a two-pass `rebuild()`, with NO beagle-core change. Phase 2 adds a server-side manifest/delta export so the worker never even reads unchanged content.

**Tech Stack:** Python 3.13 worker (`apps/beagle-memory-engine/workers/semantic_backbone.py`), `ijson` (streaming JSON), `pytest`, LanceDB; Rust HTTP server (`src/main.rs`); kaniko build → `192.168.3.207:5003`.

**Spec:** `docs/superpowers/specs/2026-06-23-memory-engine-streaming-incremental-reindex-design.md`

---

## Phase 1 — Worker streaming (ships first; fixes the OOM)

### Task 1: pytest harness + golden fixture + lock current behavior

**Files:**
- Create: `apps/beagle-memory-engine/workers/tests/conftest.py`
- Create: `apps/beagle-memory-engine/workers/tests/fixtures/export_small.json`
- Create: `apps/beagle-memory-engine/workers/tests/test_candidates.py`
- Modify: `apps/beagle-memory-engine/requirements.txt`

- [ ] **Step 1: Add test deps + ijson to requirements**

Append to `apps/beagle-memory-engine/requirements.txt`:

```
# Streaming JSON parser for memory-flat reindex (parses the export incrementally instead of
# json.load of the whole corpus into Python dicts — the reindex OOM root cause).
ijson==3.3.0
```

(pytest is a dev-only dep; install ad hoc in the test step — do NOT add it to the runtime image.)

- [ ] **Step 2: Write the golden fixture** `tests/fixtures/export_small.json`

```json
{
  "episodes": [
    {"id": "ep1", "summary": "first episode summary", "privacy_class": "sensitive", "occurred_at": "2026-01-01"}
  ],
  "atoms": [
    {"id": "at1", "text": "an atom of meaning", "content_hash": "h-at1", "privacy_class": "sensitive"},
    {"id": "at2", "normalized_text": "restricted atom", "privacy_class": "restricted"}
  ],
  "worlds": [
    {"id": "w1", "label": "World One", "summary": "a world", "project_slug": "p", "merkle_root": "m", "privacy_class": "sensitive"}
  ],
  "passages": [
    {"id": "pa1", "privacy_class": "sensitive", "occurred_at": "2026-02-02", "session_id": "s1", "source_platform": "claude",
     "turns": [{"content": "hello world this is a turn"}, {"content": ""}]}
  ]
}
```

- [ ] **Step 3: Write the lock-in golden test** `tests/test_candidates.py`

```python
import json, sys
from pathlib import Path

WORKERS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(WORKERS))
import semantic_backbone as sb  # noqa: E402

FIX = Path(__file__).parent / "fixtures" / "export_small.json"

def test_collect_candidates_baseline():
    export = sb.load_json(str(FIX))
    cands, restricted = sb.collect_candidates(export)
    ids = [c["canonical_id"] for c in cands]
    # episode, atom at1, world, one passage window (the empty turn yields nothing); restricted at2 excluded
    assert restricted == 1
    assert "ep1" in ids and "at1" in ids and "w1" in ids
    assert any(i.startswith("passage:pa1:0:") for i in ids)
    assert "at2" not in ids
    # every candidate is text-bearing and carries a content_hash
    assert all(c["text"].strip() and c["content_hash"] for c in cands)
```

- [ ] **Step 4: Run it**

Run: `cd apps/beagle-memory-engine/workers && python3 -m pytest tests/test_candidates.py -q`
Expected: PASS (locks current behavior before refactor).

- [ ] **Step 5: Commit**

```bash
git add apps/beagle-memory-engine/requirements.txt apps/beagle-memory-engine/workers/tests/
git commit -m "test(memory-engine): lock collect_candidates behavior + add ijson dep"
```

---

### Task 2: streaming `iter_candidates` generator (golden-equivalent)

**Files:**
- Modify: `apps/beagle-memory-engine/workers/semantic_backbone.py`
- Test: `apps/beagle-memory-engine/workers/tests/test_candidates.py`

- [ ] **Step 1: Write the failing equivalence test** (append to `test_candidates.py`)

```python
def test_iter_candidates_matches_collect():
    export = sb.load_json(str(FIX))
    expected, _ = sb.collect_candidates(export)
    got = list(sb.iter_candidates(str(FIX)))
    assert got == expected  # same rows, same order, byte-identical dicts

def test_iter_candidates_counts_restricted():
    stats = {"restricted_excluded": 0}
    list(sb.iter_candidates(str(FIX), stats))
    assert stats["restricted_excluded"] == 1
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd apps/beagle-memory-engine/workers && python3 -m pytest tests/test_candidates.py::test_iter_candidates_matches_collect -q`
Expected: FAIL with `AttributeError: module 'semantic_backbone' has no attribute 'iter_candidates'`

- [ ] **Step 3: Implement `iter_candidates`** — add after `collect_candidates` in `semantic_backbone.py`

```python
def iter_candidates(export_path: str, stats: dict[str, int] | None = None):
    """Streaming twin of collect_candidates: parse the export file incrementally with ijson and
    YIELD candidate dicts one at a time (passage expansion included), so the full corpus is never
    resident. Byte-identical rows to collect_candidates. `stats["restricted_excluded"]` is
    incremented for skipped restricted records when a stats dict is passed."""
    import ijson  # local import: only the rebuild path needs it
    sources = [
        ("episodes", "MemoryEpisode"),
        ("atoms", "MemoryAtom"),
        ("worlds", "MemoryWorld"),
        ("passages", "ConversationPassage"),
    ]
    for field, kind in sources:
        with open(export_path, "rb") as handle:
            for item in ijson.items(handle, f"{field}.item"):
                privacy = str(item.get("privacy_class") or "sensitive").lower()
                if privacy == "restricted":
                    if stats is not None:
                        stats["restricted_excluded"] = stats.get("restricted_excluded", 0) + 1
                    continue
                if kind == "ConversationPassage":
                    yield from collect_passage_records(item, privacy)
                    continue
                text = record_text(item, kind)
                if not text.strip():
                    continue
                canonical_id = str(item.get("id") or item.get("source_ref") or text_hash(text))
                yield {
                    "canonical_id": canonical_id,
                    "kind": kind,
                    "content_hash": str(item.get("content_hash") or text_hash(text)),
                    "privacy_class": privacy,
                    "source_refs": json.dumps(item.get("source_refs") or [], ensure_ascii=False),
                    "chronoself_commit": str(item.get("chronoself_commit") or ""),
                    "provenance": json.dumps(item.get("provenance") or {}, ensure_ascii=False, sort_keys=True),
                    "occurred_at": str(item.get("occurred_at") or item.get("created_at") or ""),
                    "text": text[:12000],
                }
```

Note: `ijson` yields plain dicts/lists for `item`; `.get()` works identically to `json.load` dicts.

- [ ] **Step 4: Run to verify both tests pass**

Run: `cd apps/beagle-memory-engine/workers && python3 -m pytest tests/test_candidates.py -q`
Expected: PASS (all 4).

- [ ] **Step 5: Commit**

```bash
git add apps/beagle-memory-engine/workers/semantic_backbone.py apps/beagle-memory-engine/workers/tests/test_candidates.py
git commit -m "feat(memory-engine): streaming iter_candidates (ijson) — golden-equivalent to collect_candidates"
```

---

### Task 3: restructure `rebuild()` into two streaming passes

**Files:**
- Modify: `apps/beagle-memory-engine/workers/semantic_backbone.py` (`rebuild()`, lines ~411–470 + the full/incremental blocks)
- Test: `apps/beagle-memory-engine/workers/tests/test_rebuild_stream.py`

- [ ] **Step 1: Write the failing test** `tests/test_rebuild_stream.py` (uses a stub encoder + temp lancedb)

```python
import sys
from pathlib import Path
WORKERS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(WORKERS))
import semantic_backbone as sb  # noqa: E402

FIX = Path(__file__).parent / "fixtures" / "export_small.json"

class StubEncoder:
    backend = "stub"
    def encode(self, text, is_query=False):
        return [[0.0] * sb.DIM]  # one token-vector; shape matches arrow_schema list(list(float32, DIM))

def _args(tmp, full=False):
    import argparse
    return argparse.Namespace(export=str(FIX), model="stub", table="semantic_memory_v1",
                              lancedb_path=str(tmp), full=full)

def test_full_then_incremental_roundtrip(tmp_path, monkeypatch):
    monkeypatch.setattr(sb, "ColbertEncoder", lambda *_a, **_k: StubEncoder())
    # full build
    out = sb.rebuild(_args(tmp_path, full=True))
    assert out["row_count"] >= 4
    assert out["rebuild_mode"] in ("full", "full-fallback")
    # second run with an unchanged corpus → incremental, nothing upserted
    out2 = sb.rebuild(_args(tmp_path, full=False))
    assert out2["rebuild_mode"] == "incremental"
    assert out2["row_count"] == out["row_count"]
```

(If LanceDB is unavailable in the dev env, this test runs in the build image where lancedb is installed; mark it `@pytest.mark.skipif` on ImportError of lancedb so the suite still runs locally.)

- [ ] **Step 2: Run to verify it fails**

Run: `cd apps/beagle-memory-engine/workers && python3 -m pytest tests/test_rebuild_stream.py -q`
Expected: FAIL — current `rebuild()` still calls `load_json`/`collect_candidates` and `out` lacks the streaming shape, or the incremental assertion fails because `cur` is built from the full list.

- [ ] **Step 3: Replace the head of `rebuild()`** — swap the eager load for the streaming manifest pass.

Replace:

```python
def rebuild(args: argparse.Namespace) -> dict[str, Any]:
    started = time.time()
    export = load_json(args.export)
    encoder = ColbertEncoder(args.model)
    candidates, restricted_excluded_count = collect_candidates(export)
    cur = {c["canonical_id"]: c["content_hash"] for c in candidates}
    table_name = args.table
```

with:

```python
def rebuild(args: argparse.Namespace) -> dict[str, Any]:
    started = time.time()
    encoder = ColbertEncoder(args.model)
    table_name = args.table
    # Pass 1 (streaming): build the lean id->hash manifest only — never hold the corpus content.
    stats = {"restricted_excluded": 0}
    cur: dict[str, str] = {}
    for c in iter_candidates(args.export, stats):
        cur[c["canonical_id"]] = c["content_hash"]
    restricted_excluded_count = stats["restricted_excluded"]
```

- [ ] **Step 4: Replace `full_overwrite` to stream pass-2** — change its body to iterate `iter_candidates` instead of the resident `candidates` list:

```python
    def full_overwrite(db: Any) -> Any:
        """Encode + overwrite the whole table, streaming pass-2 so peak memory is ~one batch."""
        nonlocal added, deleted, skipped
        deleted = 0
        skipped = 0
        table = None
        written = 0
        batch: list[dict[str, Any]] = []
        def flush():
            nonlocal table, written, batch
            if not batch:
                return
            rows = encode_rows(batch, encoder)
            if table is None:
                table = db.create_table(table_name, data=rows, schema=arrow_schema(), mode="overwrite")
            else:
                table.add(rows)
            written += len(rows)
            rows = None
            batch = []
        for c in iter_candidates(args.export):
            batch.append(c)
            if len(batch) >= BUILD_BATCH_SIZE:
                flush()
        flush()
        if table is None:  # empty corpus
            table = db.create_table(table_name, data=[], schema=arrow_schema(), mode="overwrite")
        added = written
        return table
```

- [ ] **Step 5: Replace the incremental block** — stream pass-2, batching only changed ids:

```python
        if incremental:
            try:
                table = db.open_table(table_name)
                to_upsert_ids = {cid for cid, h in cur.items() if prev.get(cid) != h}
                stale = [cid for cid in prev if cid not in cur]
                if stale:
                    for start in range(0, len(stale), DELETE_BATCH_SIZE):
                        chunk = stale[start : start + DELETE_BATCH_SIZE]
                        in_list = ", ".join(_sql_quote(cid) for cid in chunk)
                        table.delete(f"canonical_id IN ({in_list})")
                upserted = 0
                batch: list[dict[str, Any]] = []
                def flush_upsert():
                    nonlocal upserted, batch
                    if not batch:
                        return
                    rows = encode_rows(batch, encoder)
                    (table.merge_insert("canonical_id")
                        .when_matched_update_all()
                        .when_not_matched_insert_all()
                        .execute(rows))
                    upserted += len(rows)
                    rows = None
                    batch = []
                for c in iter_candidates(args.export):
                    if c["canonical_id"] in to_upsert_ids:
                        batch.append(c)
                        if len(batch) >= BUILD_BATCH_SIZE:
                            flush_upsert()
                flush_upsert()
                added = upserted
                deleted = len(stale)
                skipped = len(cur) - len(to_upsert_ids)
                rebuild_mode = "incremental"
                worker_status = "native-incremental"
                create_index_guarded(table)
                row_count = table.count_rows()
                native_lancedb = True
```

(The `except` fallback, `else` full branch, `optimize_table_guarded`, manifest write, and payload assembly downstream are UNCHANGED — they already reference `cur`, `added`, etc. Set the initial `row_count = len(cur)` where the old code had `row_count = len(candidates)`.)

- [ ] **Step 6: Fix the residual `len(candidates)` reference** — change the initializer line:

```python
    row_count = len(cur)
```

- [ ] **Step 7: Run the rebuild test + the candidate tests**

Run: `cd apps/beagle-memory-engine/workers && python3 -m pytest tests/ -q`
Expected: PASS (golden + roundtrip). Confirms identical index contents via streaming.

- [ ] **Step 8: Commit**

```bash
git add apps/beagle-memory-engine/workers/semantic_backbone.py apps/beagle-memory-engine/workers/tests/test_rebuild_stream.py
git commit -m "feat(memory-engine): two-pass streaming rebuild — flat memory, no full-corpus materialization"
```

---

### Task 4: memory-bound regression test

**Files:**
- Test: `apps/beagle-memory-engine/workers/tests/test_memory_bound.py`

- [ ] **Step 1: Write the test** (synthetic large export; assert streaming peak << json.load peak)

```python
import json, sys, tracemalloc
from pathlib import Path
WORKERS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(WORKERS))
import semantic_backbone as sb  # noqa: E402

def _make_big_export(path, n_passages=4000, turns=4, chars=3000):
    blob = "x" * chars
    with open(path, "w", encoding="utf-8") as fh:
        fh.write('{"episodes":[],"atoms":[],"worlds":[],"passages":[')
        for i in range(n_passages):
            if i:
                fh.write(",")
            rec = {"id": f"pa{i}", "privacy_class": "sensitive", "occurred_at": "2026-01-01",
                   "session_id": "s", "source_platform": "x",
                   "turns": [{"content": blob} for _ in range(turns)]}
            fh.write(json.dumps(rec))
        fh.write("]}")

def test_streaming_manifest_peak_below_full_load(tmp_path):
    p = tmp_path / "big.json"
    _make_big_export(str(p))
    # baseline: json.load whole file
    tracemalloc.start()
    export = sb.load_json(str(p)); _ = len(export["passages"])
    full_peak = tracemalloc.get_traced_memory()[1]; tracemalloc.stop()
    del export
    # streaming manifest pass
    tracemalloc.start()
    cur = {}
    for c in sb.iter_candidates(str(p)):
        cur[c["canonical_id"]] = c["content_hash"]
    stream_peak = tracemalloc.get_traced_memory()[1]; tracemalloc.stop()
    # streaming peak must be a fraction of the full-load peak
    assert stream_peak < full_peak * 0.5, f"stream={stream_peak} full={full_peak}"
    assert len(cur) > 0
```

- [ ] **Step 2: Run it**

Run: `cd apps/beagle-memory-engine/workers && python3 -m pytest tests/test_memory_bound.py -q`
Expected: PASS — streaming peak < 50% of full-load peak (in practice far lower; the gap widens with corpus size).

- [ ] **Step 3: Commit**

```bash
git add apps/beagle-memory-engine/workers/tests/test_memory_bound.py
git commit -m "test(memory-engine): assert streaming reindex peak memory is corpus-independent"
```

---

### Task 5: build, deploy, and a controlled recovery rebuild

**Files:**
- Reuse: `k8s/beagle-memory-lab/build-job-hardening.yaml`, `k8s/beagle-memory-lab/deploy-hardening.sh`

- [ ] **Step 1: Build the new worker image** — bump the build-job ref/tag to the new HEAD commit and apply:

```bash
# edit build-job-hardening.yaml: BEAGLE_GIT_REF=<new commit>, BEAGLE_IMAGE_TAG=exocortex-stream-<sha>
kubectl apply -f k8s/beagle-memory-lab/build-job-hardening.yaml
```

- [ ] **Step 2: Deploy** via the existing script (image bump + strip dead overrides):

Run: `bash k8s/beagle-memory-lab/deploy-hardening.sh` (edit IMG to the new tag first)
Expected: rollout healthy, worker present.

- [ ] **Step 3: Controlled full rebuild with live memory watch**

```bash
kubectl -n beagle-memory-lab port-forward svc/beagle-memory-engine 18099:8090 &
# in another shell: watch kubectl -n beagle-memory-lab top pod
curl -m 7200 -X POST http://127.0.0.1:18099/v1/index/semantic/rebuild -H 'content-type: application/json' -d '{"limit":1000000}'
```

Expected: completes without OOM; `kubectl top` stays a few hundred MB + one batch; `row_count` returns to full corpus (~300k+). If memory still climbs, the residual is `cur` (id→hash) size → proceed to Phase 2.

- [ ] **Step 4: Re-enable the reindex CronJob** (suspended this session) with the raised limit, and confirm incremental runs are cheap.

```bash
kubectl -n beagle-memory-lab patch cronjob beagle-memory-reindex -p '{"spec":{"suspend":false}}'
```

- [ ] **Step 5: Commit any manifest/doc updates + update memory**

```bash
git add k8s/beagle-memory-lab/
git commit -m "chore(memory-engine): deploy streaming reindex image + recovery rebuild"
```

---

## Phase 2 — Server-side manifest diff (network + memory flat; follow-up)

> Ship Phase 1 first and confirm the OOM is gone. Phase 2 removes the remaining full-export read.

### Task 6: read + document the current beagle-core export handler

**Files:**
- Read: `apps/beagle-monorepo/src/http_exocortex/mod.rs` (the `export` handler + `fetch_export` in `apps/beagle-memory-engine/src/main.rs`)

- [ ] **Step 1:** Locate the export handler, its route, the JSON shape (fields `episodes/atoms/worlds/passages`), and the auth guard. Record the exact response struct so the new endpoints reuse it.
- [ ] **Step 2:** Note how `fetch_export` (Rust) currently materializes the body; that is the Rust-side cost Phase 2 removes for incremental runs.

### Task 7: beagle-core `export/manifest` streaming endpoint (TDD)

**Files:**
- Modify: `apps/beagle-monorepo/src/http_exocortex/mod.rs`
- Test: Rust `#[tokio::test]` near the handler

- [ ] **Step 1:** Write a failing test: `GET /api/exocortex/v1/memory/export/manifest` returns NDJSON, one `{"canonical_id","content_hash"}` per indexable record, restricted excluded, no content fields.
- [ ] **Step 2:** Implement: stream the same source iteration the export uses, emitting only id+hash per line (`axum::body::Body::from_stream`). Reuse the operator auth guard.
- [ ] **Step 3:** Run the test; expected PASS. Commit.

### Task 8: beagle-core `export/by-ids` endpoint (TDD)

**Files:**
- Modify: `apps/beagle-monorepo/src/http_exocortex/mod.rs`

- [ ] **Step 1:** Failing test: `POST .../export/by-ids` with `{"canonical_ids":[...]}` returns full records (same shape as today's export) for only those ids, restricted still excluded.
- [ ] **Step 2:** Implement by filtering the source iteration to the requested ids; stream the response. Commit.

### Task 9: worker delta-fetch path

**Files:**
- Modify: `apps/beagle-memory-engine/src/main.rs` (incremental rebuild calls manifest+by-ids instead of full export)
- Modify: `apps/beagle-memory-engine/workers/semantic_backbone.py` (accept a manifest file + a deltas file instead of a full export, for the incremental path)
- Test: `tests/test_rebuild_stream.py` (delta path)

- [ ] **Step 1:** Failing test: given a local manifest + a deltas-only export, `rebuild` upserts only the deltas and deletes ids absent from the new manifest — identical index to a full rebuild on the same end state.
- [ ] **Step 2:** Implement: incremental rebuild reads the manifest (id→hash) to compute the diff, requests `by-ids` content for changed ids only, embeds + merge_inserts. Full rebuild keeps the whole-export path.
- [ ] **Step 3:** Run; expected PASS. Build + deploy as in Task 5. Commit.

### Task 10: end-to-end verification

- [ ] Ingest a small batch → confirm the auto-reindex (now incremental, server-side diff) transfers/parses only the deltas (check `added`/`skipped` counters + beagle-core logs), with flat memory on `kubectl top`.
- [ ] Confirm a full rebuild still works as the maintenance path.

---

## Self-Review Notes

- **Spec coverage:** Phase 1 (streaming parse + two-pass rebuild + memory test + deploy) covers the OOM fix; Phase 2 (manifest + by-ids + worker delta) covers the network/Rust-side materialization. ✔
- **Type consistency:** `iter_candidates` yields the exact dict `collect_candidates` appended (golden test enforces). `rebuild()` payload keys (`row_count`, `rebuild_mode`, `added`, `deleted`, `skipped`) unchanged. ✔
- **No placeholders:** Phase 1 steps carry full code; Phase 2 carries concrete endpoint contracts + test intents but defers exact Rust bodies to Task 6's read of the existing handler (the handler was not read in this planning pass — Task 6 is the explicit prerequisite). ✔
- **Risk:** keep `collect_candidates` (used by the golden test) until Phase 2; do not delete it in Phase 1.

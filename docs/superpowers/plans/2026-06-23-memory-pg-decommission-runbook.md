# memory-pg migration — Phase 3.4 decommission runbook

Retire the legacy memory stack (JSONL canonical writes + LanceDB/ColBERT semantic
index + the Python `semantic_backbone` reindex worker) **after** memory-pg has
been proven canonical. Doctrine: **archive, never delete**; every step is
**reversible**; never run a step before its precondition holds.

This is an operational procedure. The only code it relies on is already merged on
`feat/memory-pg`:
- dual-write (3.2): `BEAGLE_DUAL_WRITE_MEMORY_PG`
- read cutover (3.3): `BEAGLE_RETRIEVAL_VIA_MEMORY_PG`
- stop-append (3.4): `BEAGLE_JSONL_APPEND_DISABLED` (fail-safe — see Step 4)

## Preconditions (ALL must hold before starting)

1. **Deployed:** memory-pg image with `/capture` + the NUL/rerank fixes is live
   (serve, embed-worker); beagle-core is built with the 3.2/3.3/3.4 hooks.
2. **Dual-write soaked:** `BEAGLE_DUAL_WRITE_MEMORY_PG=1` has been on long enough
   to cover normal write traffic, and `bin/reconcile.mjs` reports **missing=0**
   across at least two runs spaced over the soak window.
3. **Backfill complete:** the full corpus has been backfilled and the embed queue
   is drained (`pending_embeddings` where status<>'done' == 0); HNSW rebuilt.
4. **A/B passed:** `bin/ab-eval.mjs` on a real held-out query set reports
   `verdict.newAtLeastAsGood = true` (recall@k of memory-pg ≥ legacy).

If any precondition fails, STOP — the old stack stays canonical.

## Steps (each reversible)

### Step 1 — Flip the read cutover
Set `BEAGLE_RETRIEVAL_VIA_MEMORY_PG=1` on beagle-core and roll. Retrieval now
serves from memory-pg `/query`; writes still go to BOTH stores.
- **Verify:** real recall queries return sensible results; error rate flat.
- **Rollback:** unset the flag, roll. Instant — the legacy index is untouched.

### Step 2 — Take the safety archive + backup (BEFORE stopping any writes)
```bash
# Legacy stack — copies, never deletes:
ops/archive-legacy-memory.sh            # dry-run first
ops/archive-legacy-memory.sh --commit   # writes tar.gz + SHA256SUMS, verifies

# New canonical store:
MEMORY_PG_DSN=postgres://... ops/memory-pg-backup.sh
```
Copy both archives **off-box**. Do not proceed until verified.

### Step 3 — Stop the legacy reindex (semantic_backbone / LanceDB writer)
Scale the reindex worker / CronJob to zero so LanceDB stops being updated. Leave
the deployment object in place for now (delete only in Step 6).
```bash
kubectl -n <ns> scale deploy/<memory-engine-reindex> --replicas=0
# or: kubectl -n <ns> patch cronjob/<reindex> -p '{"spec":{"suspend":true}}'
```
- **Verify:** retrieval (now memory-pg) unaffected; no new LanceDB segments.
- **Rollback:** scale back to 1 / unsuspend.

### Step 4 — Stop the legacy JSONL appends
Set `BEAGLE_JSONL_APPEND_DISABLED=1` on beagle-core (keep
`BEAGLE_DUAL_WRITE_MEMORY_PG=1`). memory-pg `/capture` is now the sole write for
mirrored kinds (episodes/atoms/passages).

**Fail-safe:** the code (`jsonl_write_skipped`) suppresses the JSONL append ONLY
when dual-write is also enabled and the kind is mirrored. If dual-write is off,
or the log is non-mirrored (chronoself, hyperedges, …), JSONL keeps being
written — a misconfigured flag can never silently drop writes.
- **Verify:** new records appear in memory-pg; `memory_*.jsonl` mtimes stop
  advancing; `reconcile.mjs` still clean.
- **Rollback:** unset the flag — appends resume immediately (no data lost; the
  dual-write kept memory-pg current throughout).

### Step 5 — Soak
Run on memory-pg-only writes for a soak window. Watch error rates, capture
latency, and `reconcile.mjs`. This is the last point with a one-flag rollback.

### Step 6 — Remove the legacy deployments (after the soak is clean)
Delete the LanceDB deployment and the Python `semantic_backbone` worker /
memory-engine semantic serving. The JSONL files and LanceDB dir are already
archived (Step 2) and the source dirs are still on disk — they are NOT deleted
here. Physical source-dir cleanup, if ever, is a separate deliberate step taken
only after the off-box archive is confirmed.

## Restore

**Logical (matches the backup script; extensions FIRST):**
```bash
createdb memory_restored
psql -d memory_restored -c 'CREATE EXTENSION IF NOT EXISTS vector;'
psql -d memory_restored -c 'CREATE EXTENSION IF NOT EXISTS pg_search;'
# CREATE EXTENSION age;   # only once Phase 4 graph tables exist
pg_restore --no-owner --dbname=postgres://user@host/memory_restored memory-pg-<stamp>.dump
```
The `CREATE EXTENSION` calls MUST precede `pg_restore` — the `halfvec` and bm25
columns need their types to exist before the data loads.

**Physical alternatives:** `pg_basebackup -Ft -z -Xs` of the running primary, or a
Ceph RBD snapshot of the memory-pg PVC. A physical restore is a drop-in data dir
and does NOT need the extensions-first step (the whole cluster is copied).

**Legacy restore:** untar the Step-2 archive back into place and unset the
3.4/3.3/3.2 flags — the old stack resumes exactly as before.

## Final state
- Canonical store: **memory-pg** (Postgres + pgvector + pg_search).
- Retrieval: **memory-pg /query** (dense+BM25+RRF → bge-reranker-v2-m3).
- Legacy JSONL + LanceDB: **archived** (retained, off-box), writers stopped,
  deployments removed.
- After completion, update `[[project_exocortex_ingest_constraints]]`: the
  fragile JSONL/LanceDB/subprocess stack is replaced.

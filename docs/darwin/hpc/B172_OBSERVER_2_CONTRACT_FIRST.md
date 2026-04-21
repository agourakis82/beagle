# B17.2 — Observer 2.0 Contract-First

Status: GO

## Objective

Create the first canonical Observer 2.0 path for bounded physiological ingestion and retrieval:

- canonical `PhysioSnapshot` contract
- bounded ingest via `POST /api/observer/physio`
- bounded latest retrieval via `GET /api/observer/physio/latest`
- clean reuse by the memory ingest spine

## Canonical Path

- observer contract + latest state: `crates/beagle-observer/src/lib.rs`
- HTTP observer surface: `apps/beagle-monorepo/src/http.rs`
- memory integration point: `apps/beagle-monorepo/src/http_memory.rs`

## Contract Shape

The canonical snapshot is bounded and repo-native:

- `source`
- `session_id`
- `timestamp`
- `hr`
- `hrv_ms`
- `hrv_level`
- `spo2`
- `stress_index`
- `severity`

## Expected Proof

- observer ingest works through the canonical contract
- latest snapshot is recoverable from the Observer surface
- memory ingest uses the canonical latest snapshot path
- cluster stays green
- Slurm stays green

## Canonical Live Proof

- canonical session id: `b172-observer-0322112536`
- `POST /api/observer/physio` returned `status=ok` with canonical snapshot persisted
- `GET /api/observer/physio/latest` returned the same `session_id` and snapshot values
- `POST /api/memory/ingest_chat` attached the canonical latest physio snapshot
- `POST /api/memory/query` returned the ingested turn with both `physio_snapshot` and `recent_physio`
- cluster remained green and `Slurmctld(primary)` remained `UP`

## Canonical Artifacts

- `.artifacts/darwin-hpc/observer-contract/physio-ingest-response.json`
- `.artifacts/darwin-hpc/observer-contract/physio-latest.json`
- `.artifacts/darwin-hpc/observer-contract/memory-ingest-response.json`
- `.artifacts/darwin-hpc/observer-contract/memory-query-response.json`
- `.artifacts/darwin-hpc/observer-contract/smoke.json`
- `.artifacts/darwin-hpc/observer-contract/final-cluster-health.txt`

# B17.1 — Memory Ingest Spine

Status: GO

## Objective

Create the first repo-native Beagle memory spine for external conversation turns:

- `POST /api/memory/ingest_chat`
- `POST /api/memory/query`
- MCP tools:
  - `beagle_memory_ingest_chat`
  - `beagle_memory_query`

The phase keeps Beagle as the system of truth. External tools do not own canonical memory; they only use bounded ingest/query surfaces.

## What This Phase Adds

- Bounded ingest of one chat turn at a time.
- Qdrant-preferred searchable memory records, with repo-native local persistence when lower-layer memory services are absent.
- Hypergraph append path preserved when the bridge substrate is available.
- Best-effort physiological attachment from Beagle observer state.
- Best-effort experiment flag attachment from Beagle runtime state.
- Compact bounded query results with structured metadata.

## Canonical Request Shape

### Ingest

```json
{
  "source": "chatgpt",
  "conversation_id": "conv-123",
  "turn_index": 4,
  "role": "assistant",
  "text": "Beagle now has a bounded memory ingest path.",
  "tags": ["memory", "darwin-hpc"],
  "domain": "beagle-engine"
}
```

### Query

```json
{
  "query": "bounded memory ingest path",
  "limit": 5,
  "domain": "beagle-engine",
  "tags": ["memory"],
  "include_recent_physio": true
}
```

## Runtime Path

- HTTP surface: `apps/beagle-monorepo/src/http_memory.rs`
- Memory engine: `crates/beagle-memory/src/engine.rs`
- Hypergraph append path: `crates/beagle-memory/src/bridge.rs`
- Observer physio source: `AppState.observer.current_user_context()`
- MCP surface: `beagle-mcp-server/src/tools/memory.ts`

## Storage Model

- Primary searchable substrate: Qdrant collection `beagle_memory_chat` when configured
- Current live cluster path: repo-native persisted local memory index under `BEAGLE_DATA_DIR`
- Append/trace substrate: Beagle hypergraph conversation turn storage when bridge services are available
- Neo4j linkage: out of scope for this phase

## Canonical Live Proof

- canonical conversation id: `b171-memory-0322110205`
- HTTP ingest result: `e962d0e6-fc40-5748-9348-41792b9a19b8`
- MCP ingest result: `9dd644e3-5510-55f0-a8ae-a5c46ed151a6`
- artifacts:
  - `.artifacts/darwin-hpc/memory-ingest-spine/ingest-response.json`
  - `.artifacts/darwin-hpc/memory-ingest-spine/query-response.json`
  - `.artifacts/darwin-hpc/memory-ingest-spine/physio-attachment.json`
  - `.artifacts/darwin-hpc/memory-ingest-spine/mcp-tool-results.json`
  - `.artifacts/darwin-hpc/memory-ingest-spine/smoke.json`
  - `.artifacts/darwin-hpc/memory-ingest-spine/final-cluster-health.txt`

## Expected Proof

- ingest endpoint works
- query endpoint works
- latest physio snapshot is attached when available
- query returns the ingested turn
- MCP tools resolve through the same Beagle-owned HTTP surface
- cluster stays green
- Slurm stays green

# B17.1 — GO / NO-GO

Status: GO

## GO Criteria

- `beagle_memory_ingest_chat` works
- `beagle_memory_query` works
- `POST /api/memory/ingest_chat` works
- `POST /api/memory/query` works
- latest physio snapshot is attached when available
- bounded useful results are returned
- query resolves the ingested turn
- cluster stays green
- Slurm stays green

## Current Read

- runtime implementation: complete
- MCP surface: aligned to the new bounded contracts
- local/container validation: passed
- live cluster proof: passed and frozen
- live cluster mode: local persisted memory path active; Qdrant/bridge remain optional and dormant until configured

## Promotion Rule

Live smoke and validator both passed. The phase is promoted to `GO`.

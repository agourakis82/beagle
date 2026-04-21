# B22.1 - Hybrid Retrieval Spine / Embeddings & RAG Elevation

## Objective

Elevate the existing Beagle memory layer into a canonical hybrid retrieval spine so memory becomes retrieval-grade, payload-aware, and directly consumable by workstream/program/campaign context.

## What This Phase Adds

- A canonical retrieval collection contract for Beagle memory.
- A canonical memory point contract with explicit payload fields.
- A hybrid query/result contract with dense + sparse retrieval and payload filters.
- Runtime retrieval surfaces under `/api/memory/retrieval/...`.
- Workstream context-packet integration driven by hybrid retrieval instead of the older bounded legacy query path.

## Canonical Retrieval Shape

- `collection`: Beagle memory retrieval collection with dense backend, sparse backend, payload fields, and filter fields.
- `point`: canonical memory point materialized as `vector + payload`.
- `query`: hybrid retrieval request with dense/sparse switches, weights, top-k, and payload filters.
- `result`: bounded retrieval result with explicit hits, scores, and applied filters.

## Canonical Payload Fields

- `memory_id`
- `workstream_id`
- `campaign_id`
- `program_id`
- `workspace_id`
- `session_id`
- `source`
- `conversation_id`
- `turn_index`
- `role`
- `domain`
- `tags`
- `physio_snapshot_ref`
- `physio_snapshot`
- `experiment_flags`
- `result_refs`
- `claim_refs`
- `timestamp`

## Runtime Surfaces

- `GET /api/memory/retrieval/collection`
- `POST /api/memory/retrieval/query`

The workstream context packet now consumes the hybrid retrieval spine through:

- `GET /api/darwin/workstreams/{id}/context-packet`

## Bounded Design

- Beagle remains the system of truth.
- No new graph runtime is introduced.
- No ingress, HA, or backplane redesign is introduced.
- Hybrid retrieval is canonical now; reranking stays optional and deferred.

## GO Shape

`B22.1 = GO` when:

1. memory points are indexed with explicit payload;
2. hybrid retrieval returns bounded relevant hits;
3. payload filters work;
4. retrieval hits feed at least one context-packet surface;
5. restart remains coherent;
6. cluster stays green;
7. Slurm stays green.

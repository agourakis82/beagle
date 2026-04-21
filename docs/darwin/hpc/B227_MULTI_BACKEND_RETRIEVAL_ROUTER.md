# B22.7 — Multi-Backend Retrieval Router / Query-Type Arbitration

## Objective

Add the first bounded retrieval router on top of the canonical hybrid retrieval spine without
changing:

- `Qdrant` as the canonical store direction
- `voyage-4-large` as the canonical general dense backend
- `voyage-code-3` as the bounded code retrieval lane
- `bge-m3` as the bounded sovereign retrieval lane
- `local-lexical` as the complementary sparse path

## What changes in this phase

1. Adds an explicit query-type classifier with three bounded classes:
   - `general`
   - `code`
   - `sovereign`
2. Adds an explicit retrieval routing decision contract.
3. Exposes a router-aware query path that delegates to the already-proven general, code, and
   sovereign retrieval lanes.
4. Preserves payload-aware filters over:
   - `workstream_id`
   - `campaign_id`
   - `session_id`
   - `source`
   - `role`
   - `domain`
   - `repo_path`
   - `file_type`
   - `tags`
5. Pushes the routed retrieval decision into the workstream and program context packets.

## Routing policy

- `general` queries route to `voyage-4-large`
- `code` queries route to `voyage-code-3`
- `sovereign` queries route to `bge-m3`
- `local-lexical` remains active for all lanes as the complementary sparse signal

The classifier stays intentionally bounded:

- explicit `query_type_hint` wins when present and valid
- `repo_path` / `file_type` filters promote `code`
- code-like query text promotes `code`
- multilingual, sovereign, privacy-sensitive, or offline-capable query text promotes `sovereign`
- everything else falls back to `general`

## Important boundary

This phase does not introduce:

- heavy reranking
- a learned router
- a second retrieval control plane
- a store migration away from `Qdrant`

The router only arbitrates between already-proven bounded retrieval lanes.

## Canonical proof

The live smoke for this phase produces artifacts in:

`beagle/.artifacts/darwin-hpc/multi-backend-retrieval-router/`

Key proof points:

- query typing returns a bounded class
- routing decisions select the correct backend for `general`, `code`, and `sovereign`
- payload-aware filters remain active on the routed path
- the workstream and program context packets preserve routed retrieval context
- restart preserves identity and routed retrieval coherence

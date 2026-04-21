# B22.8 — Late-Interaction / Reranking Pilot

## Objective

Add the first bounded reranking layer on top of the already-live multi-backend retrieval router
without changing:

- `Qdrant` as the canonical store direction
- `voyage-4-large` as the canonical general dense backend
- `voyage-code-3` as the bounded code retrieval lane
- `bge-m3` as the bounded sovereign dense lane
- `local-lexical` as the complementary sparse path

## What changes in this phase

1. Promotes an explicit reranking profile contract for the live runtime.
2. Adds a bounded reranking hook on top of routed retrieval.
3. Activates:
   - `Voyage rerank-2.5` for the general lane
   - `bge-reranker-v2-m3` for the sovereign lane
4. Keeps code retrieval on prerank routing only in this phase.
5. Pushes reranking state into the canonical workstream/program context packets.

## Boundary

This phase does not introduce:

- a new retrieval store
- a global reranking stage for every lane
- heavy late interaction across the full corpus
- a learned ranking subsystem

The pilot stays bounded to reranking the routed top-k candidate set.

## Pilot policy

- `general` queries:
  - prerank with `voyage-4-large + local-lexical`
  - rerank top-k with `Voyage rerank-2.5`
- `sovereign` queries:
  - prerank with `bge-m3 + local-lexical`
  - rerank top-k with `bge-reranker-v2-m3`
- `code` queries:
  - remain prerank-only in `B22.8`
  - continue using `voyage-code-3 + local-lexical`

## Canonical proof

The live smoke for this phase produces artifacts in:

`beagle/.artifacts/darwin-hpc/reranking-pilot/`

Key proof points:

- prerank vs postrank outputs are explicit
- reranking latency and relevance-proxy deltas are recorded
- payload-aware filters remain active
- the workstream/program context packets expose reranking state
- restart preserves the same `workstream_id`, `workspace_id`, and `session_id`

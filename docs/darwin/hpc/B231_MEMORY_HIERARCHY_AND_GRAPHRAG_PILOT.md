# B23.1 — Memory Hierarchy & GraphRAG Pilot

## Objective

Promote the live retrieval spine into a bounded memory-organization layer that
distinguishes how Beagle stores and recalls its own objects. This phase adds:

- explicit `episodic`, `semantic`, and `procedural` memory buckets
- a bounded GraphRAG view over canonical Beagle entities
- context-packet enrichment with graph-aware retrieval output

## Canonical stance

- `Qdrant` remains the vector-store direction
- the `B22.x` retrieval spine remains the canonical retrieval substrate
- the graph layer is assembled on demand from canonical ids and retrieval hits
- this pilot does not introduce a separate graph database or autonomous graph runtime

## What is live

- `POST /api/memory/graphrag/query`
- `GET /api/darwin/workstreams/{id}/context-packet` with GraphRAG-enriched retrieval context
- `GET /api/darwin/programs/{id}/context-packet` with propagated GraphRAG context

## Memory hierarchy policy

- `episodic`
  - session-local recall, handoffs, resumptions, operator events
- `semantic`
  - results, evidence, claims, manuscript-supporting facts
- `procedural`
  - repo-native code, config, scripts, and operational runbooks

## Pilot graph scope

The bounded graph projection covers canonical Beagle entities only:

- `Program`
- `Campaign`
- `Workstream`
- `Session`
- `Experiment`
- `Result`
- `Claim`
- `Manuscript`

And the pilot relationships remain narrow:

- `program -> contains -> campaign`
- `campaign -> uses -> workstream`
- `session -> belongs_to -> workstream`
- `workstream -> runs -> experiment`
- `experiment -> yields -> result`
- `result -> supports -> claim`
- `claim -> appears_in -> manuscript`

## Why this stays bounded

The pilot does not replace retrieval. It starts from routed, filtered, reranked
retrieval results and projects a small graph-aware view from those supporting
records. That keeps the phase repo-native, auditable, and coherent with the
existing Beagle-owned identity model.

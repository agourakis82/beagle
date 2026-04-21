# B23.2 — Memory Promotion, Forgetting & GraphRAG Query Modes

## Objective

Add the first canonical lifecycle policy layer on top of the existing memory
hierarchy and bounded GraphRAG pilot.

This phase introduces:

- explicit promotion from episodic memory into semantic or procedural memory
- explicit retention and forgetting policy by memory type
- bounded GraphRAG query-mode routing across `local`, `global`, and `drift`
- propagation of policy and promotion metadata into context packets

## Canonical stance

- `Qdrant` remains the vector-store direction
- the existing retrieval spine remains in place
- the current dense backends remain in place
- GraphRAG remains bounded and Beagle-owned
- no giant graph subsystem is introduced in this phase

## What is live

- `GET /api/memory/promotion-policy`
- `GET /api/memory/retention-policy`
- `POST /api/memory/graphrag/query-mode`
- `POST /api/memory/promotion/evaluate`

## Bounded policy shape

Promotion is explicit and non-destructive:

- episodic -> semantic when bounded claim/evidence/manuscript language shows
  the memory has hardened into reusable knowledge
- episodic -> procedural when bounded attach/launch/resume/config/script
  language shows the memory has hardened into reusable execution know-how

Retention stays bounded by memory type:

- episodic memory expires or compacts first
- semantic memory stays longer across the active campaign window
- procedural memory stays until superseded

GraphRAG query modes stay narrow:

- `local` for session/workstream-neighborhood questions
- `global` for broader program/campaign/manuscript scope
- `drift` for change-over-time and cross-session comparisons

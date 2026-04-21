# B23.3 — Query-Adaptive Memory Compiler / Context Budgeted Tool Context

## Objective

Add the first canonical memory compiler so Beagle can compile bounded,
task-aware context packets from the memory hierarchy, routed retrieval, and
bounded GraphRAG layers that are already live.

This phase introduces:

- explicit compiler contract for task-aware memory compilation
- explicit context budget profiles for implementation, analysis,
  interactive-editing, and manuscript work
- compiled context packets that preserve identity, retrieval lane, GraphRAG
  mode, and source-slice budget decisions
- bounded propagation of compiled context into workstream/program context,
  tool dock launch metadata, and subagent handoff propagation

## Canonical stance

- `Qdrant` remains the vector-store direction
- the current retrieval spine remains in place:
  - `voyage-4-large` for general retrieval
  - `voyage-code-3` for code retrieval
  - `bge-m3` for the sovereign track
  - sparse lexical retrieval remains active
  - reranking remains bounded
- the memory compiler reuses Beagle-owned memory and graph layers rather than
  creating a parallel memory runtime

## What is live

- `GET /api/memory/compiler`
- `GET /api/memory/compiler/budget-profile/:task_profile`
- `POST /api/memory/compiler/compile`
- `POST /api/darwin/workstreams/:workstream_id/compiled-context`

## Bounded compiler shape

The compiler answers five canonical questions:

- which memory tiers are selected for this task profile
- which retrieval lane should be used for this task profile
- which GraphRAG query mode should be used for this task profile
- how much bounded context budget is allocated to each source kind
- how the final compiled context differs across daily Beagle work surfaces

The initial profiles stay narrow and explicit:

- `implementation`
  - code retrieval
  - local GraphRAG hint
  - procedural-first memory budget
- `analysis`
  - general retrieval
  - global GraphRAG hint
  - semantic-first memory budget
- `interactive-editing`
  - code retrieval
  - local GraphRAG hint
  - procedural plus recent episodic budget
- `manuscript`
  - general retrieval
  - global GraphRAG hint
  - semantic-heavy editorial budget

## Integration surfaces

Compiled context is propagated into:

- workstream context packets
- program/campaign context packets
- premium tool dock launch metadata
- workspace subagent handoff propagation

The compiler remains bounded:

- no new embedding backend is introduced
- no heavy global reranking is introduced
- no giant autonomous memory runtime is introduced
- editorial/scientific readiness limits remain explicit where they already
  apply

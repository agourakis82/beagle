# B23.6 — Context Quality Evals & Compiler Policy Learning

`B23.6` adds the first bounded evaluation harness over the canonical Beagle memory compiler.

## Purpose

The goal of this phase is to stop treating compiler policy as hand-authored only. Beagle now compares bounded compiler variants for the current task classes and derives an evidence-backed compiler policy from those comparisons.

## Scope

- keep the existing retrieval stack and dense backends
- keep reranking bounded
- keep the Beagle backplane unchanged
- compare bounded compiler variants instead of building a new autonomous runtime

## What Is Evaluated

- implementation context quality
- analysis context quality
- manuscript context quality
- current-truth vs both-truth suitability
- local vs global vs drift GraphRAG suitability
- episodic / semantic / procedural / temporal / graphrag budget efficiency

## Runtime Surfaces

- `GET /api/memory/compiler`
- `GET /api/memory/compiler/budget-profile/:task_profile`
- `POST /api/memory/compiler/compile`
- `POST /api/memory/compiler/eval`
- `POST /api/memory/compiler/policy`

## Bounded Policy Learning

Each eval case compares a small set of compiler policy variants for a task profile. The runtime measures:

- relevance proxy
- task fit
- context usefulness
- budget efficiency
- truth-view appropriateness
- graphrag-mode appropriateness
- route appropriateness
- top-k stability

The selected winner becomes the evidence basis for the derived compiler policy.

## Canonical Outcome

The canonical B23.6 artifact set preserves:

- explicit eval cases
- per-task policy comparison
- compiler eval report
- evidence-backed compiler policy
- restart coherence
- cluster and Slurm health

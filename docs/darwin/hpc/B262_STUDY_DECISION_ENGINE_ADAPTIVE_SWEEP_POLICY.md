# B26.2 Study Decision Engine / Adaptive Sweep Policy

## Purpose

B26.2 adds the first bounded decision layer on top of the canonical study registry, study DAG, sweep representation, and comparative result summary.

The decision engine does not launch new runs. It reads the existing study state, explains why one variant is preferred, and emits a bounded next-run proposal for operator review.

## What it does

- Reads the canonical study registry, study DAG, study sweep, and comparative result summary for the current workstream/workspace/session identity
- Selects a best candidate variant using bounded, auditable structural heuristics
- Emits a study decision with one explicit recommended action
- Emits a next-run proposal that remains operator-visible and is not auto-launched
- Preserves the same Beagle-owned identity across the full decision path

## Decision policy

- `rerun-variant` when the latest diff is result-only and the study needs confirmation under the same bounded lineage
- `continue-sweep` when the study still needs broader coverage across code, config, or environment changes
- `promote-variant` only when the current evidence basis is strong enough to justify promotion
- `archive-variant` when a candidate is structurally weaker and no longer useful for the current sweep
- `stop-study` when the study has already converged and additional runs are not expected to add value

## Known limits

- The engine is intentionally bounded and heuristic-driven
- The engine does not auto-launch the next run
- The engine does not replace operator review
- The engine does not create a new workflow engine or a parallel canonical state


# B26.3 Study Proposal-to-Run Dispatch / Adaptive Study Continuation

## Purpose

B26.3 turns the canonical B26.2 `next-run-proposal` into a real bounded run inside the same study loop.

The phase remains operator-aware: a proposal is approved, dispatched through the existing workbench lane, and then bound back into the same study registry, sweep, comparative summary, and continuation state.

## What it does

- Reads the canonical study decision and next-run proposal for the current workstream/workspace/session identity
- Approves the proposal in a bounded, operator-visible step
- Dispatches the proposal as a real run through the existing collaborative workbench
- Persists a study run update and a study continuation state for restart recovery
- Preserves the same Beagle-owned identity across proposal, run, and study update

## Boundaries

- The phase does not create a fully autonomous study loop
- The phase does not skip operator visibility
- The phase does not replace the existing study registry, DAG, sweep, or result binding layers
- The phase does not introduce ingress, edge, or HA behavior

## Acceptance

- A canonical next-run proposal can be approved and dispatched
- The resulting run remains tied to the same study
- The study update is explicit and auditable
- Restart recovers the same proposal, dispatch, run update, and continuation state

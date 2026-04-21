# B26.4 Study Convergence & Variant Promotion Gate

## Purpose

B26.4 closes the study loop by deciding whether the canonical study should continue or stop, selecting the strongest variant, and freezing a bounded promotion/archive decision in the same Beagle-owned identity.

## What it does

- Reads the canonical study registry, DAG, sweep, decision, proposal dispatch, continuation state, and run update artifacts
- Computes whether the bounded evidence window is sufficient to close the study
- Selects the best-scoring variant as the promotion candidate
- Marks the remaining variants for archive-only treatment
- Produces a closeout summary that freezes the final comparative decision

## Boundaries

- The phase does not start a new sweep automatically
- The phase does not invent a new workflow engine
- The phase does not introduce ingress, edge, or HA behavior
- The phase does not replace the existing study registry, DAG, sweep, or continuation layers
- The phase does not hide readiness limits from the operator

## Acceptance

- The study produces an explicit convergence decision
- A bounded variant promotion/archive decision is produced
- The closeout summary records the final comparative decision
- The same study/workstream/workspace/session identity is preserved
- Restart remains coherent

## Next phase

- once the convergence gate reports `enough_evidence_to_stop = true`, the B26.5 phase takes over to materialize the promoted variant, archive the losers, and bind the promoted run back into the workbench, memory, and lineage artifacts while keeping the same Beagle-owned identity.

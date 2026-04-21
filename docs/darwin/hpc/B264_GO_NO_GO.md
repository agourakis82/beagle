# B26.4 GO / NO-GO

## GO when

- `study-convergence.json` reports `convergence_state = "converged"`
- `variant-promotion-decision.json` reports `decision_action = "promote-variant"`
- `study-closeout-summary.json` freezes the final comparative decision
- All artifacts preserve the same Beagle-owned study/workstream/workspace/session identity
- Live restart reproduces the same convergence result
- Cluster health and Slurm health remain green

## NO-GO when

- The convergence evidence window is still incomplete
- The selected variant cannot be resolved from the study sweep
- Identity continuity breaks across registry, sweep, decision, dispatch, or continuation state
- Restart changes the closeout result


# B26.5 GO / NO-GO

## GO when

- the `study-promotion-execution.json` artifact exists and records the promoted variant, archived variants, workbench binding, deterministic binding, and result identity receipt for the same best-scoring run
- the promotion execution summary preserves the same Beagle-owned study/workstream/workspace/session identity as the convergence gate
- the restart proof (`container-proof/study-promotion-execution-after-restart.json`) continues to show the same study and identity bindings
- cluster health remains green and the Slurm controller is responsive before/after the promotion execution

## NO-GO when

- the promoted run cannot be tied back to the workbench run, the deterministic binding, or the run-result identity receipt
- the archived variants list is incomplete or inconsistent with the convergence gate decision
- the restart proof changes the promoted variant, annotated actions, or identity marker
- cluster health or Slurm health degrades during the promotion execution snapshot

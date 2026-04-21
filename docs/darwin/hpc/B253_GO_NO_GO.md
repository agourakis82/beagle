# B25.3 — GO / NO-GO

## GO

Implementação canónica: runtime (`workbench_reservation`, `workbench_run`,
`workbench_result_binding`, `workbench_orchestration`), rotas HTTP em
`http_darwin_hpc`, contratos YAML em `docs/darwin/hpc/contracts/`, smoke em
`run_workbench_orchestration_smoke.sh` (ou alias
`run_workbench_run_orchestration_smoke.sh`) e validador correspondente.

`B25.3` is `GO` when all of the following are true:

- one canonical workbench reservation is created
- the reservation binds an allowed compute profile to an allowed collaboration
  role
- one bounded run is dispatched from that reservation
- the run reaches a terminal state in the same workbench envelope
- result refs and manifest receipts are bound back to the same
  `workstream/workspace/session`
- partner-dev remains bounded and does not receive cluster-admin or direct
  Kubernetes access
- restart still recovers the same workspace/session identity
- cluster health remains green
- Slurm remains green

## GO-WITH-BLOCKER

Use `GO-WITH-BLOCKER` if:

- the contracts are present and compile
- the workbench orchestration path exists
- but the live run cannot be completed or rebound because of an external live
  platform issue such as scheduler unavailability or rollout instability

## STAGED / READY FOR LIVE SMOKE

Use `STAGED / READY FOR LIVE SMOKE` if:

- contracts, runtime surfaces, and scripts are in place
- compile/test passes
- but the live cluster rollout or smoke has not been run yet

## NO-GO

This phase is `NO-GO` if any of the following happen:

- the run path bypasses the bounded Beagle control plane
- result refs are left detached from the workbench/session identity
- partner-dev receives unrestricted cluster access
- restart loses the same Beagle-owned workspace/session continuity

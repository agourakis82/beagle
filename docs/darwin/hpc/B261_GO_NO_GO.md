# B26.1 — GO / NO-GO

## GO criteria

- One canonical study is registered for the active workbench workspace/session lane.
- Multiple runs are tied to that study through explicit run registration.
- One bounded sweep/variant set is represented and traceable to concrete run ids.
- One comparative result summary is generated against a baseline run.
- Beagle-owned identity remains preserved where applicable across study artifacts.
- Restart remains coherent for study registry/sweep/dag/summary reads.
- Cluster stays green.
- Slurm stays green.

## No-go triggers

- Study orchestration creates a second control plane outside Beagle.
- Study artifacts cannot be tied back to canonical run capsules/replay receipts.
- Identity fields drift across study records for the same workstream workspace lane.
- Comparative summary cannot explain baseline-versus-variant differences explicitly.

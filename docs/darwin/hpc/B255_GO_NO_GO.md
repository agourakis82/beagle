# B25.5 — GO / NO-GO

## GO criteria

- One canonical run capsule is written for a live workbench run.
- One prior run capsule is available through lineage.
- One bounded run diff is generated between the latest run and its prior lineage parent.
- Code/config/environment/result comparison sections are explicit.
- One replay request is generated from the latest run capsule.
- The same Beagle-owned `workstream/workspace/session` identity is preserved.
- Restart recovery keeps the latest run capsule and replay request coherent.
- Cluster stays green.
- Slurm stays green.

## No-go triggers

- Capsule generation drifts to profile-latest instead of the run-scoped identity.
- The latest and prior capsules do not preserve the same Beagle-owned identity.
- The diff cannot explain run differences explicitly by category.
- Restart loses the latest run/result linkage.

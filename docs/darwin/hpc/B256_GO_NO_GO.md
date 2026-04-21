# B25.6 — GO / NO-GO

## GO criteria

- One canonical live run captures explicit code provenance.
- The latest run capsule carries real Git-aware fields for branch, commit, tree-ish, dirty state,
  and patch reference when available.
- One source fingerprint is captured and bound to the same run.
- The latest run diff explicitly reports code-state differences.
- The same Beagle-owned `workstream/workspace/session` identity is preserved.
- Restart recovery keeps the latest run/code/result linkage coherent.
- Cluster stays green.
- Slurm stays green.

## No-go triggers

- Code provenance remains effectively empty (`branch=none commit=none patch_ref=none dirty=unknown`)
  after a canonical B25.6 run.
- The run capsule and deterministic result binding point at different run identities.
- The run diff cannot explain code-state differences explicitly.
- Restart loses the latest run/code/result linkage.

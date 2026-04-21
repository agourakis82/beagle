# B16.1 - GO / NO-GO

## Current gate

B16.1 is `GO`.

Canonical promotion evidence:

1. `workspace_id=b161-wave1-0322082253`
2. `session_id=ws-20260322112605`
3. `cpu-batch-v1` completed as job `59`
4. published result `31` remained resolvable
5. restart preserved the same workstream/workspace/session identity
6. live validator passed on `.artifacts/darwin-hpc/second-real-workstream-cutover/`

## GO conditions

B16.1 may promote to `GO` only if the live smoke proves all of the following:

1. the second workstream `beagle-darwin-hpc-wave1` is visible in the
   repo-native registry
2. one real workflow loop completes under `workspace_id` and `session_id`
   bound to that workstream
3. control room resolves the second workstream with coherent repo, branch,
   governance, handoff and last-result state
4. timeline resolves ordered events for that same workstream/session line
5. restart/recovery preserves the same workstream/workspace/session identity
6. `default_dev_plane=beagle-cluster` remains intact
7. `vm_fallback_role=fallback-only` remains intact
8. cluster remains green
9. `Slurmctld(primary)` remains `UP`

## NO-GO conditions

B16.1 remains below `GO` if any of the following occur:

1. the second workstream exists only in docs and not in live control-room
   resolution
2. the live pilot falls back to the first canonical workstream by inertia
3. workstream identity changes across restart/recovery
4. timeline cannot replay the second workstream events coherently
5. cluster or Slurm degrade during the drill

## Promotion note

The second workstream was promoted only after the live smoke completed and
`validate_second_real_workstream_cutover_smoke.sh` passed against the captured
artifacts.

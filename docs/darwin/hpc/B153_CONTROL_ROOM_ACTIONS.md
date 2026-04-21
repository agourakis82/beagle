# B15.3 - Control Room Actions

## Current status

B15.3 is `GO`.

Canonical deliverables for this phase:

- `crates/beagle-darwin/src/workstream_control_room.rs`
- `crates/beagle-darwin/src/workspace_plane.rs`
- `apps/beagle-monorepo/src/http_darwin_hpc.rs`
- `scripts/infrastructure/darwin-hpc/run_control_room_actions_smoke.sh`
- `scripts/infrastructure/darwin-hpc/validate_control_room_actions_smoke.sh`

Canonical smoke evidence lives under:

- `.artifacts/darwin-hpc/control-room-actions/bootstrap-before.json`
- `.artifacts/darwin-hpc/control-room-actions/seed-pilot.json`
- `.artifacts/darwin-hpc/control-room-actions/cockpit-before.json`
- `.artifacts/darwin-hpc/control-room-actions/status-before.json`
- `.artifacts/darwin-hpc/control-room-actions/action-hold.json`
- `.artifacts/darwin-hpc/control-room-actions/status-held.json`
- `.artifacts/darwin-hpc/control-room-actions/action-resume.json`
- `.artifacts/darwin-hpc/control-room-actions/status-resumed.json`
- `.artifacts/darwin-hpc/control-room-actions/bootstrap-after-restart.json`
- `.artifacts/darwin-hpc/control-room-actions/session-after-restart.json`
- `.artifacts/darwin-hpc/control-room-actions/cockpit-after-restart.json`
- `.artifacts/darwin-hpc/control-room-actions/governance-ledger-tail.jsonl`
- `.artifacts/darwin-hpc/control-room-actions/smoke.json`
- `.artifacts/darwin-hpc/control-room-actions/final-cluster-health.txt`

## Objective

Add the first bounded mutation actions to the internal control room so the
operator can govern the canonical workstream from the same Beagle-owned
workstream/session envelope.

This phase enables:

1. `POST /api/darwin/workstreams/{id}/hold`
2. `POST /api/darwin/workstreams/{id}/resume`

## Architectural decision

- the control room remains bounded: only `hold` and `resume` are added
- the canonical workstream/session identity remains Beagle-owned
- governance mutations update runtime state, handoff, and a bounded governance
  ledger
- restart/recovery must preserve the same workspace/session identity and final
  resumed state
- lower layers, ingress, edge, HA, providers, and multi-workstream expansion
  remain out of scope

## Success condition

B15.3 closes when:

1. `hold` moves the canonical workstream from `canonical` to `held`
2. `resume` moves the canonical workstream from `held` back to `canonical`
3. the same workspace/session identity remains intact throughout the drill
4. handoff and last-result continuity remain coherent through both actions
5. the bounded governance ledger records the actions explicitly
6. cluster remains green
7. Slurm remains green

## Live result

The live drill passed on workspace `b153-0322071243` with session
`ws-20260322101553`.

The canonical proof captured:

1. one seeded canonical workstream session completed `cpu-batch-v1` as job `57`
   and kept published result `31` resolved
2. `hold` mutated the workstream from `canonical` to `held` on that same
   workspace/session line
3. `resume` mutated the workstream from `held` back to `canonical` on that same
   workspace/session line
4. restart/recovery preserved the same session identity after the resumed state
5. the bounded governance ledger explicitly recorded both `hold` and `resume`
6. cluster remained green and `Slurmctld(primary)` stayed `UP`

Live seeded workflow facts:

1. seeded workflow profile: `cpu-batch-v1`
2. submitted job id: `57`
3. published result job id: `31`
4. same session line preserved through seed, hold, resume, and restart
5. `fallback_active=false` before, during, and after the drill

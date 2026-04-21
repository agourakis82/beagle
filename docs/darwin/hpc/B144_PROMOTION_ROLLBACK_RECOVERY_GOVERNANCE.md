# B14.4 - Promotion / Rollback / Recovery Governance

## Current status

B14.4 is `GO`.

Canonical live governance workspace:

- `b144-0321204218`

Canonical governance artifacts live under:

- `docs/darwin/hpc/workstreams/registry.yaml`
- `docs/darwin/hpc/workstreams/beagle-darwin-hpc-governance.yaml`

Canonical smoke evidence lives under:

- `.artifacts/darwin-hpc/workstream-governance-smoke/bootstrap-before.json`
- `.artifacts/darwin-hpc/workstream-governance-smoke/session-before.json`
- `.artifacts/darwin-hpc/workstream-governance-smoke/seed-pilot.json`
- `.artifacts/darwin-hpc/workstream-governance-smoke/bootstrap-held.json`
- `.artifacts/darwin-hpc/workstream-governance-smoke/session-held.json`
- `.artifacts/darwin-hpc/workstream-governance-smoke/bootstrap-after-resume.json`
- `.artifacts/darwin-hpc/workstream-governance-smoke/session-after-resume.json`
- `.artifacts/darwin-hpc/workstream-governance-smoke/smoke.json`
- `.artifacts/darwin-hpc/workstream-governance-smoke/final-cluster-health.txt`

## Objective

Turn workstream lifecycle into explicit governed state transitions:

1. make the workstream state machine first-class and repo-native
2. expose the current state and last transition through the live runtime policy
3. prove one controlled governance drill without reopening lower layers
4. preserve session, handoff, task and result continuity across the drill

## Minimum governance model

The minimum governance model is:

1. states: `staged`, `pilot`, `canonical`, `held`, `rollback`, `recovery`
2. transitions: `promote`, `hold`, `resume`, `rollback`, `recover`

The first controlled drill for this phase is intentionally low-entropy:

1. `canonical -> held`
2. `held -> canonical`

## Architectural decision

- governance remains embedded in the canonical workstream object; it does not
  create a new control plane
- live proof uses the existing Beagle workspace/session/runtime surfaces only
- the drill remains bounded to one canonical workstream
- the phase does not reopen infra, ingress, edge, HA, providers or topology

## Placement

- workstream registry: `docs/darwin/hpc/workstreams/registry.yaml`
- canonical workstream spec:
  `docs/darwin/hpc/workstreams/beagle-darwin-hpc-governance.yaml`
- live governance smoke:
  `scripts/infrastructure/darwin-hpc/run_workstream_governance_smoke.sh`
- live governance validator:
  `scripts/infrastructure/darwin-hpc/validate_workstream_governance_smoke.sh`

## Success condition

The phase is now closed because:

1. the workstream state machine is explicit and repo-native
2. at least one controlled governance drill passes live
3. hold/resume does not break session, handoff or last task/result continuity
4. cluster remains green
5. Slurm remains green
6. no lower layer is reopened

## Live result

The canonical governance drill closed as `GO`.

Live proof from workspace `b144-0321204218`:

1. the canonical workstream exposed an explicit lifecycle state machine with
   states `staged`, `pilot`, `canonical`, `held`, `rollback`, `recovery`
2. the drill started in `state=canonical` with `last_transition=resume`
3. one real seed workflow completed as `cpu-batch-v1` job `54` and preserved
   published result `31`
4. the live runtime was deliberately moved to `state=held` with
   `last_transition=hold`
5. the same session `ws-20260321234559` remained intact while held
6. the last handoff and published result remained intact while held
7. the runtime was resumed back to `state=canonical` with
   `last_transition=resume`
8. the same session, handoff and published result remained intact after resume
9. `default_dev_plane=beagle-cluster` remained active and
   `vm_fallback_role=fallback-only` remained true in practice
10. cluster remained green and `Slurmctld(primary)` remained `UP`

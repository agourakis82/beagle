# B15.4 - Operator Timeline / Audit Replay

## Current status

B15.4 is `GO`.

Canonical deliverables for this phase:

- `crates/beagle-darwin/src/workstream_timeline.rs`
- `apps/beagle-monorepo/src/http_darwin_hpc.rs`
- `scripts/infrastructure/darwin-hpc/run_operator_timeline_smoke.sh`
- `scripts/infrastructure/darwin-hpc/validate_operator_timeline_smoke.sh`

Canonical smoke evidence will live under:

- `.artifacts/darwin-hpc/operator-timeline/bootstrap-before.json`
- `.artifacts/darwin-hpc/operator-timeline/seed-pilot.json`
- `.artifacts/darwin-hpc/operator-timeline/action-hold.json`
- `.artifacts/darwin-hpc/operator-timeline/action-resume.json`
- `.artifacts/darwin-hpc/operator-timeline/bootstrap-after-restart.json`
- `.artifacts/darwin-hpc/operator-timeline/session-after-restart.json`
- `.artifacts/darwin-hpc/operator-timeline/timeline.json`
- `.artifacts/darwin-hpc/operator-timeline/timeline-limit.json`
- `.artifacts/darwin-hpc/operator-timeline/timeline-event-hold.json`
- `.artifacts/darwin-hpc/operator-timeline/timeline-event-recovery.json`
- `.artifacts/darwin-hpc/operator-timeline/governance-ledger-tail.jsonl`
- `.artifacts/darwin-hpc/operator-timeline/smoke.json`
- `.artifacts/darwin-hpc/operator-timeline/final-cluster-health.txt`

## Objective

Create the first internal timeline / audit replay surface for the canonical
workstream so an operator can read what happened, in order, under the same
Beagle-owned workstream/session identity.

This phase must expose:

1. governance transitions
2. real workflow loop completion
3. published result references
4. handoff evolution
5. recovery / restart evidence

## Target surface

The internal timeline surface for this phase is:

1. `GET /api/darwin/workstreams/{id}/timeline`
2. `GET /api/darwin/workstreams/{id}/timeline?limit=N`
3. `GET /api/darwin/workstreams/{id}/timeline/{event_id}`

## Architectural decision

- the timeline is read-only in this phase; it does not add new mutation
  semantics
- the surface is composed from runtime truth that already exists:
  workspace/session state, bounded governance ledger, and fallback ledger
- the timeline remains internal and bounded to the canonical workstream
- no new backplane, ingress, edge, HA, provider expansion or multi-workstream
  surface is introduced here

## Success condition

B15.4 can close only if the live smoke proves:

1. the internal timeline surface responds
2. governance transitions, loop completion, result references, handoff
   evolution and recovery are visible in order
3. the same workspace/session identity remains intact after restart
4. cluster remains green
5. Slurm remains green

## Live result

The live drill passed on workspace `b154-0322075224` with session
`ws-20260322105541`.

The canonical proof captured:

1. one seeded canonical workstream session completed `cpu-batch-v1` as job `58`
   and kept published result `31` resolved
2. the timeline surface returned one ordered six-event audit line under the
   same Beagle-owned workspace/session identity
3. the ordered replay exposed:
   - `session_bootstrap`
   - `workflow_completed`
   - `result_reference`
   - `governance_transition` `hold`
   - `governance_transition` `resume`
   - `recovery_bootstrap`
4. `GET /api/darwin/workstreams/beagle-darwin-hpc-governance/timeline?limit=3`
   returned the latest bounded replay window as `hold -> resume -> recovery`
5. `GET /api/darwin/workstreams/beagle-darwin-hpc-governance/timeline/{event_id}`
   resolved both a concrete governance event and a concrete recovery event
6. restart/recovery preserved the same session identity and resumed canonical
   state on `beagle-cluster`
7. cluster remained green and `Slurmctld(primary)` remained `UP`

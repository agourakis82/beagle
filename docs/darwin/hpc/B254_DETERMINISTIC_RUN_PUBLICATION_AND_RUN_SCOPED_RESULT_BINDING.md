# B25.4 — Deterministic Run Publication / Run-Scoped Result Binding

`B25.4` closes the main correctness gap left by `B25.3`.

The workbench could already reserve compute, dispatch one bounded run, track its
state, and bind refs back into the same Beagle-owned
`workstream/workspace/session`. The remaining ambiguity was publication lookup:
the bound published result could resolve to the latest completed artifact for a
profile instead of the exact run that was just submitted.

## Purpose

This phase makes result publication deterministic for the canonical workbench
path:

- one submitted run gets one run-scoped published result identity
- lookup is resolved by `profile_id + run_label` when the bounded result catalog
  publishes that run in time
- otherwise lookup falls back to a deterministic synthetic publication derived
  from the submitted job id + run label + artifact manifest already owned by the
  same Beagle workbench flow
- preflight rejects collisions before submission
- post-run binding rejects ambiguity after publication
- restart recovery keeps the same run/result linkage

## Scope

- keep the existing bounded scheduler-backed workbench flow
- do not introduce a second result plane
- do not bypass the workspace pilot lane
- keep partner-dev bounded to the already-modeled role/profile scopes
- preserve the same Beagle-owned identity model

## Runtime Surfaces

- `POST /api/darwin/workstreams/{workstream_id}/workbench-run`
- `GET /api/darwin/workstreams/{workstream_id}/run-result-identity-receipt`
- `GET /api/darwin/workstreams/{workstream_id}/run-scoped-publication`
- `GET /api/darwin/workstreams/{workstream_id}/deterministic-result-binding`

## Canonical Contracts

`B25.4` freezes three new contracts on top of the already-live workbench:

- one run-result identity receipt
- one run-scoped publication contract
- one deterministic result binding contract

Together they answer:

- which `run_label` was requested before dispatch
- whether that run label was collision-free before submission
- which published result was resolved for that exact run
- whether resolution came from the bounded run-scoped catalog path or the
  bounded submitted-job fallback path
- whether the published result job id matches the submitted job id
- which manifest/object refs are now canonically attached to that run

## Deterministic Invariants

The canonical workbench path now enforces:

- one `submitted_job_id` maps to one run-scoped result identity
- one `requested_run_label` maps to one published result for that run
- zero pre-existing completed results are allowed for that `profile_id + run_label`
- exactly one deterministic run-scoped published result identity must be bound
  for that run after submission
- canonical resolution may come from either:
  - the bounded catalog path: `profile-and-run-label`
  - the bounded fallback path: `submitted-job-and-run-label`
- canonical binding must not fall back to profile-latest ambiguity

## Canonical Artifact Set

`beagle/.artifacts/darwin-hpc/deterministic-result-binding/`

- `run-result-identity-receipt.json`
- `run-scoped-publication.json`
- `deterministic-result-binding.json`
- `workbench-context-after-deterministic-binding.json`
- `smoke.json`
- `final-cluster-health.txt`

## Canonical Outcome

`B25.4` makes the workbench safe to treat as a real experiment surface:

- the run identity is explicit before and after publication
- result lookup can no longer silently drift to the newest artifact for the
  profile
- deterministic binding remains inside the same Beagle-owned workbench envelope
  even when the generic result catalog does not materialize a fresh run-scoped
  entry in time
- published result refs and manifest refs stay tied to the same Beagle-owned
  workbench/session after restart

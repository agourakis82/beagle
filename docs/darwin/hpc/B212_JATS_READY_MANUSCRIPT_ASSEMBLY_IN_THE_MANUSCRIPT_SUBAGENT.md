# B21.2 — JATS-Ready Manuscript Assembly in the Manuscript Subagent

## Objective

Create the first bounded editorial assembly layer inside the `manuscript`
subagent so the same Beagle-owned
`workstream/workspace/session` can convert campaign `claims`, `evidence`,
`manuscript-pack`, `review-bundle`, and `provenance` into one JATS-ready
artifact.

## What is canonical in this phase

- one runtime surface:
  - `GET/POST /api/darwin/workstreams/{id}/workspace-manuscript-assembly`
- one bounded assembly profile:
  - `jats-1.4-ready`
- one source subagent:
  - `manuscript`
- one identity:
  - same `workstream_id`
  - same `workspace_id`
  - same `session_id`

## Runtime shape

The assembly layer sits strictly above `B21.1`.

1. `core -> experiments`
2. `experiments -> manuscript`
3. `manuscript -> JATS-ready assembly`

The assembly response keeps explicit links to:

- `program_context`
- `evidence_pack`
- `claims`
- `manuscript_pack`
- `review_bundle`
- `jats_pack`

It also freezes:

- `section_profile`
- `section_map_contract_ref`
- `readiness_state`
- `manuscript_target_id`

## Contracts

- `docs/darwin/hpc/contracts/workspace-manuscript-assembly-schema.yaml`
- `docs/darwin/hpc/contracts/jats-manuscript-pack-schema.yaml`
- `docs/darwin/hpc/contracts/manuscript-section-map.yaml`

## Live proof

Canonical live proof is emitted under:

- `.artifacts/darwin-hpc/manuscript-jats-assembly/`

Expected key artifacts:

- `workspace-manuscript-assembly-post.json`
- `workspace-manuscript-assembly.json`
- `workspace-manuscript-assembly-after-restart.json`
- `campaign-review-bundle.json`
- `campaign-jats-manuscript-pack.json`
- `jats-article.xml`
- `smoke.json`
- `final-cluster-health.txt`

## Honest boundary

This phase does **not**:

- automate DOI minting
- automate submission
- hide the `human-eval-pending` readiness gap when it still exists
- create a second canonical manuscript path outside Beagle

# B21.3 — Scholarly Release Pipeline / JATS QA + Crosswalk Export

## Objective

Promote the bounded manuscript assembly from [B212_JATS_READY_MANUSCRIPT_ASSEMBLY_IN_THE_MANUSCRIPT_SUBAGENT.md](/home/devsounio/beagle/docs/darwin/hpc/B212_JATS_READY_MANUSCRIPT_ASSEMBLY_IN_THE_MANUSCRIPT_SUBAGENT.md)
into a release-grade package inside the same Beagle-owned workspace/session/workstream identity.

## Included

- JATS QA report over the manuscript subagent artifact
- RO-Crate export for the release bundle
- DataCite-ready metadata export
- Crossref-compatible article stub export
- Restart-safe release record under the workspace plane
- Live smoke + validator

## Not Included

- Real DOI deposit
- Real Crossref submission
- Public release ingress
- HA
- Any new canonical state owner outside Beagle

## Canonical Surface

- `GET /api/darwin/workstreams/{id}/workspace-scholarly-release`
- `POST /api/darwin/workstreams/{id}/workspace-scholarly-release`

The release layer is manuscript-subagent scoped but remains inside the same canonical:

- `workstream_id`
- `workspace_id`
- `session_id`

## Release Contents

- bounded JATS QA
- RO-Crate metadata export
- DataCite-ready metadata block
- Crossref-compatible article stub
- explicit provenance and readiness state

## Honest Boundary

`readiness_state=claim-linked-human-eval-pending` remains explicit when it still applies. The release bundle is packaging-ready, not submission-automated.

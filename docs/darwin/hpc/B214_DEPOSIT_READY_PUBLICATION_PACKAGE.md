# B21.4 — Deposit-Ready Publication Package / DOI Staging

## Objective

Freeze one canonical campaign into a deposit-ready publication package derived from the `B21.3` scholarly release, without performing real DOI minting, Crossref submission, or hiding epistemic gaps that still apply.

## Canonical Surface

- `GET /api/darwin/workstreams/{id}/workspace-publication-package`
- `POST /api/darwin/workstreams/{id}/workspace-publication-package`

## Inputs

- latest `workspace-scholarly-release`
- same Beagle-owned `workstream_id`
- same Beagle-owned `workspace_id`
- same Beagle-owned `session_id`
- same manuscript subagent continuity

## Outputs

- `publication-readiness-report.json`
- `datacite-deposit-payload.json`
- `crossref-deposit-bundle.json`
- `deposit-ready-publication-package.json`
- inherited:
  - `jats-article.xml`
  - `ro-crate-metadata.json`
  - `datacite-metadata.json`
  - `crossref-article.xml`

## Boundaries

- no real DOI minting
- no real Crossref submission
- no public ingress
- no HA
- no second canonical workspace/session
- no change to Beagle sovereignty over context/session/handoff

## Success Shape

The package is technically ready for future deposit staging while keeping `readiness_state=claim-linked-human-eval-pending` explicit whenever that remains true.

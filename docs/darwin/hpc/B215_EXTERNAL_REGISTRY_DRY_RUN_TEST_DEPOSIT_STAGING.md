# B21.5 — External Registry Dry-Run / Test Deposit Staging

## Objective

Freeze one canonical campaign into an external-registry-facing dry-run package
derived from `B21.4`, without opening the real DataCite or Crossref deposit
boundary and without hiding `claim-linked-human-eval-pending`.

## In Scope

- one `workspace-external-staging` runtime layer
- DataCite test-system staging payload
- Crossref dry-run journal/article bundle
- explicit external staging readiness report
- restart-safe shaping and live cluster proof

## Out of Scope

- real DOI minting
- real Crossref submission
- findable publication
- HA, ingress, or backplane redesign

## Canonical Outputs

- `external-staging-readiness-report.json`
- `datacite-test-staging-payload.json`
- `crossref-dry-run-bundle.json`
- `external-registry-staging-bundle.json`

## Honest Boundary

This phase externalizes the technical deposit boundary into dry-run artifacts.
It does not claim scientific closure, and it preserves the epistemic blocker
when human evaluation is still pending.

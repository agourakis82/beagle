# B21.6 — Sandbox Deposit Handshake / Receipt Tracking

## Objective

Execute one real sandbox handshake against the DataCite test API and the
Crossref test deposit endpoint from the manuscript subagent, preserve the
receipts in a canonical ledger, and keep
`claim-linked-human-eval-pending` explicit.

## In Scope

- one `workspace-sandbox-deposit` runtime layer
- live DataCite test handshake receipt capture
- live Crossref test handshake receipt capture
- canonical registry submission ledger
- restart-safe shaping and live cluster proof

## Out of Scope

- real DOI minting
- Crossref production submission
- transition to `findable`
- hiding epistemic blockers
- HA, ingress, or backplane redesign

## Canonical Outputs

- `datacite-test-receipt.json`
- `crossref-test-receipt.json`
- `registry-submission-ledger.json`
- `sandbox-deposit-bundle.json`

## Honest Boundary

This phase proves the technical handshake boundary against test registries.
It does not claim scientific closure, and it does not treat a successful
technical exchange as permission to publish or make a DOI findable.

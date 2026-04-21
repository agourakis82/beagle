# B19.5 — Standards-Grade Review Bundles / RO-Crate Export

Status: GO

## Objective

Create the first canonical review bundle export so Beagle can package a live
campaign into a bounded, externalizable, review-friendly research object.

## Canonical Shift

Before `B19.5`, Beagle could assemble internal evidence packs, claims, and
manuscript packs.

After `B19.5`, Beagle can also export:

- one canonical review bundle
- one RO-Crate-like metadata block
- one citation-ready metadata block
- one provenance-carrying package that remains campaign-aware and restart-safe

## Internal Surface

- `GET /api/darwin/campaigns/{id}/review-bundle`

## Export Profile

The runtime export remains intentionally bounded:

- `RO-Crate 1.2 bounded` as the packaging profile
- `W3C PROV bounded` as the provenance profile
- `DataCite-ready` as the citation block profile

This phase does not attempt DOI minting, full manuscript generation, or
submission automation.

## Included

- review bundle runtime assembly
- RO-Crate-like metadata export
- bounded provenance carry-forward
- citation-ready metadata carry-forward
- smoke + validator

## Excluded

- DOI creation
- repository publication automation
- full manuscript authoring
- public UI
- ingress / edge / HA
- graph runtime expansion

## Canonical Target

- program: `beagle-physio-symbolic-exocortex`
- campaign: `expedition-002-hrv-aware`
- manuscript target: `expedition-002-results`

## Expected Artifacts

- `.artifacts/darwin-hpc/review-bundle/review-bundle.json`
- `.artifacts/darwin-hpc/review-bundle/ro-crate-metadata.json`
- `.artifacts/darwin-hpc/review-bundle/review-bundle-after-restart.json`
- `.artifacts/darwin-hpc/review-bundle/smoke.json`
- `.artifacts/darwin-hpc/review-bundle/final-cluster-health.txt`

## Canonical Live Proof

- workspace: `b195-review-bundle-0323071950`
- session: `ws-20260323102314`
- status: `smoke=ok`, `validator=ok`
- export profile: `ro-crate-1.2-bounded`
- readiness state: `claim-linked-human-eval-pending`

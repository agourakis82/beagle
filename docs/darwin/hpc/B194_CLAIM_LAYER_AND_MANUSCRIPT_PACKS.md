# B19.4 — Claim Layer & Manuscript Packs

Status: GO

## Objective

Create the first canonical claim layer so Beagle can turn evidence packs into
reviewable claims and manuscript-ready bounded packs.

## Canonical Shift

Before `B19.4`, Beagle could package evidence.

After `B19.4`, Beagle can also express:

- explicit claims linked to evidence packs
- confidence mode and bounded gaps
- manuscript targets linked to campaign evidence
- manuscript-ready bounded packs with provenance and citation metadata

## Internal Surfaces

- `GET /api/darwin/campaigns/{id}/claims`
- `GET /api/darwin/campaigns/{id}/manuscript-pack`

## Included

- claim objects
- claim-to-evidence links
- manuscript pack assembly over canonical evidence packs
- bounded provenance and citation carry-forward
- smoke + validator

## Excluded

- DOI minting
- manuscript auto-writing
- public UI
- ingress / edge / HA
- graph runtime expansion

## Canonical Target

- program: `beagle-physio-symbolic-exocortex`
- campaign: `expedition-002-hrv-aware`
- manuscript target: `expedition-002-results`

## Expected Artifacts

- `.artifacts/darwin-hpc/claim-layer/claims.json`
- `.artifacts/darwin-hpc/claim-layer/manuscript-pack.json`
- `.artifacts/darwin-hpc/claim-layer/manuscript-pack-after-restart.json`
- `.artifacts/darwin-hpc/claim-layer/smoke.json`
- `.artifacts/darwin-hpc/claim-layer/final-cluster-health.txt`

# B19.3 — Evidence Packs / Manuscript Packs

Status: GO

## Objective

Create the first canonical evidence pack so Beagle can assemble one campaign
into a bounded, provenance-aware, citation-ready research object.

## Canonical Shift

Before `B19.3`, Beagle could resolve live program/campaign context.

After `B19.3`, Beagle can also assemble that context into a first-class
evidence-oriented package that links:

- campaign/workstream identity
- experiment refs
- dataset refs
- result refs
- memory refs
- physio refs
- recipe refs
- provenance
- citation-ready metadata

## Internal Surface

- `GET /api/darwin/campaigns/{id}/evidence-pack`

## Pack Profile

The runtime pack is intentionally bounded:

- `RO-Crate-inspired` for grouped research packaging
- `W3C PROV bounded` for provenance
- `DataCite-ready` for citation metadata

This phase does not attempt DOI minting or full manuscript automation.

## Included

- canonical evidence pack runtime assembly
- provenance block
- citation-ready metadata block
- campaign-aware resolution over existing workstream packets
- smoke + validator

## Excluded

- DOI creation
- submission automation
- manuscript generation
- public UI
- ingress / edge / HA
- large graph runtime expansion

## Canonical Target

- program: `beagle-physio-symbolic-exocortex`
- campaign: `expedition-002-hrv-aware`

## Expected Artifacts

- `.artifacts/darwin-hpc/evidence-pack/evidence-pack.json`
- `.artifacts/darwin-hpc/evidence-pack/evidence-pack-after-restart.json`
- `.artifacts/darwin-hpc/evidence-pack/smoke.json`
- `.artifacts/darwin-hpc/evidence-pack/final-cluster-health.txt`

## Canonical Live Proof

- workspace: `b193-evidence-pack-0323055639`
- session: `ws-20260323090000`
- program: `beagle-physio-symbolic-exocortex`
- campaign: `expedition-002-hrv-aware`
- active workstream: `beagle-darwin-hpc-governance`
- evidence refs:
  - `result_refs=1`
  - `memory_refs=3`
  - `physio_refs=4`
  - `recipe_refs=1`
- restart preserved the same workspace/session identity
- cluster remained green and `Slurmctld(primary)` stayed `UP`

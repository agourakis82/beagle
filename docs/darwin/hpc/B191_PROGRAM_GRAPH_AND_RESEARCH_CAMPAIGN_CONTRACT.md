# B19.1 — Program Graph & Research Campaign Contract

Status: GO

## Objective

Create the first repo-native program/campaign layer above workstreams so Beagle
can organize execution, experiments, evidence, and manuscript targets as one
coherent program instead of a set of isolated loops.

## Canonical Shift

Before `B19.1`, the highest explicit unit was the governed workstream.

After `B19.1`, Beagle also has:

- one canonical program
- canonical campaigns inside that program
- explicit links from campaigns to workstreams, experiments, results, and
  manuscript/evidence targets

## Scope

Included:

- program graph schema
- first canonical program
- first canonical campaign set
- explicit mapping from existing workstreams into campaigns
- explicit mapping from Expedition 002 into the campaign layer
- consistency check and validator

Excluded:

- new runtime graph subsystem
- ingress / edge / HA
- public UI
- large ontology expansion
- lower-layer redesign

## Canonical Objects

- program: `beagle-physio-symbolic-exocortex`
- campaigns:
  - `darwin-hpc-governance`
  - `expedition-002-hrv-aware`

## Required Relations

- `program -> campaign`
- `campaign -> workstream`
- `campaign -> experiment`
- `experiment -> result`
- `result -> manuscript/evidence target`
- `physio snapshot -> experiment/session contextual layer`

## Expected Artifacts

- `docs/darwin/hpc/contracts/program-graph-schema.yaml`
- `docs/darwin/hpc/programs/beagle-physio-symbolic-exocortex.yaml`
- `docs/darwin/hpc/campaigns/darwin-hpc-governance.yaml`
- `docs/darwin/hpc/campaigns/expedition-002-hrv-aware.yaml`
- `.artifacts/darwin-hpc/program-graph-contract/consistency-summary.json`

## Canonical Result

`B19.1 = GO`

The repo-native contract layer is now live and consistent:

- canonical program: `beagle-physio-symbolic-exocortex`
- canonical campaigns:
  - `darwin-hpc-governance`
  - `expedition-002-hrv-aware`
- existing workstreams map cleanly into the campaign layer
- `Expedition 002` maps cleanly into the campaign layer
- the consistency checker passed on the canonical artifact set

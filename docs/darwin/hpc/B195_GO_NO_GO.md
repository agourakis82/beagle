# B19.5 — GO / NO-GO

Status: GO

## GO Criteria

- one canonical campaign returns a bounded review bundle
- the bundle carries claims, evidence-pack linkage, manuscript-pack linkage,
  provenance, and citation-ready metadata
- the RO-Crate-like metadata block is present and coherent
- the bundle remains restart-coherent
- cluster stays green
- Slurm stays green

## No-Go Conditions

- review bundle assembly loses claim/evidence/manuscript linkage
- RO-Crate-like export metadata is missing or incoherent
- citation-ready metadata is absent
- restart loses workspace/session coherence
- the live smoke or validator fails

## Canonical Decision

- `GO`
- live smoke passed for campaign `expedition-002-hrv-aware`
- validator passed on `.artifacts/darwin-hpc/review-bundle/`
- cluster stayed green
- `Slurmctld(primary)` stayed `UP`

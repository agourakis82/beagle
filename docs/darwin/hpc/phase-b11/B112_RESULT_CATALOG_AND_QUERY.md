# B11.2 - Result Catalog and Query Semantics

## Objective

Create the first canonical result catalog on top of published object manifests
and expose lightweight query semantics for result discovery.

## Design Rule

- object plane remains the source of truth
- catalog entries are derived from published manifests
- queries stay internal and lightweight
- no new database is introduced in the first pass

## Target Query Surface

- `GET /results`
- `GET /results?profile_id=...`
- `GET /results?run_label=...`
- `GET /results/{job_id}`
- `GET /results/{job_id}/manifest`

## Live Result

- canonical run: `20260319-185720`
- catalog source of truth: `darwin-hpc-artifacts`
- catalog entries discovered: `5`
- query surface returned `200` for all canonical checks
- canonical lookup preserved `r740-proxmox` for the published GPU result path

# B10.1 Known Limits

## Current Limits

- the first canonical publication round covers `cpu-short-v1` only
- the object endpoint remains internal and HTTP-only in this phase
- publication credentials remain host-side platform credentials
- no object lifecycle policy is enforced yet
- no broader profile matrix is promoted yet
- the published manifest describes the three payload objects and points
  separately to its own manifest object key instead of becoming
  self-checksum-referential

## Interpretation

B10.1 proves durable object-backed publication semantics for one approved
bundle first. It does not yet broaden publication across all workload classes.

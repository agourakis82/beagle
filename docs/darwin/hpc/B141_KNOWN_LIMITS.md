# B14.1 Known Limits

## Current limits

- the phase cuts over one real workstream only:
  `beagle-darwin-hpc-governance`
- the proof still uses one canonical repo and one branch lineage at a time
- the phase proves one real loop plus restart/recovery, not every possible loop
  inside the workstream
- fallback is only validated if it actually occurs during the drill
- no provider expansion, ingress, edge, HA, topology or lower-layer reopening
  is introduced here

## Interpretation

B14.1 is the first explicit workstream cutover to canonical Beagle/cluster
operation. It is not a global migration of all work at once.

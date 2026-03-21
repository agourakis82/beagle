# B13.2 Known Limits

## Current limits

- the loop is proven with one minimal code change, not a large feature branch
- the updated behavior is validated on one existing surface, not across the
  whole Beagle app
- the workflow proof remains a single canonical operator path
- the phase proves repo-native iteration of the Beagle service, not multi-repo
  development
- the live code change is intentionally small: one persisted
  `workspace_plane_contract_version` field in the workspace contract
- the VM can still exist as support; this phase only proves it is no longer the
  mandatory center for this bounded software loop

## Interpretation

B13.2 proves that the canonical Beagle repo can sustain a real edit → build →
deploy → validate loop through the cluster. It is not a large feature phase,
and it does not yet imply large-scale in-cluster development across multiple
repos or branches at once.

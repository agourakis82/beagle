# B25.3 — Known Limits

`B25.3` intentionally keeps orchestration narrow.

## Current Limits

- only one canonical reservation/run/result-binding record is persisted per
  workspace in this phase
- the orchestration path reuses the existing workspace pilot lane rather than
  introducing a richer queue manager
- result binding currently follows the existing workspace pilot publication
  semantics, which can resolve to the latest completed result for the selected
  profile instead of forcing a newly unique per-run published result
- compute selection remains limited to already-modeled typed profiles
- partner-dev remains operator-mediated; this phase does not introduce
  self-service cluster access
- the workbench run surface proves one bounded happy-path dispatch, not a full
  multi-run history browser

## Not In Scope

- high availability
- broad public ingress
- unrestricted multi-user scheduling
- a second scheduler control plane
- editorial-first abstractions

## Readiness Note

`B25.3` is the first canonical proof that the collaborative workbench can close
the loop from reservation to result binding. It is not yet the final experiment
orchestration layer; it is the bounded substrate that later phases can extend
without leaving the Beagle-owned identity model.

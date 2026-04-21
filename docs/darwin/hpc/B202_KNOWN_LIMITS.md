# B20.2 — Known Limits

Status: GO

## Current Limits

- The Cursor lane remains `metadata-first`; the native attach proof lives in `B20.2a`, not in
  this phase's original smoke.
- The lane is intentionally `browser-first` plus `native-attach-ready`, pointing at the same
  internal `OpenVSCode Server` habitat and the same Beagle-owned context files.
- The attach path remains `cluster-internal`; it still relies on bounded `kubectl port-forward`
  rather than ingress or a full Coder control plane.
- No new state is owned by Cursor in this phase; all canonical state remains in Beagle.
- The lane is `internal-only`; there is no public exposure or ingress.
- This phase does not add multi-workspace management, HA, or a Coder control plane.

## Explicit Non-Goals

- replacing Beagle as source of truth
- introducing a second workspace identity model
- changing the `OpenVSCode Server` substrate chosen in `B20.1`
- adding public IDE exposure
- turning Cursor into the canonical state owner

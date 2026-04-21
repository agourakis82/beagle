# B20.7 — Known Limits

- the sub-agents share one workspace pod and one PVC; they are specialized inner surfaces, not isolated compute planes
- role separation is contract-first and workspace-internal; it does not yet imply scheduler-level isolation
- attach remains anchored to the same managed workspace access stack closed in `B20.4` and `B20.5`

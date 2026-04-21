# B20.5 — Known Limits

- The launch/resume path remains private and cluster-internal.
- The current implementation still relies on managed Kubernetes port-forward plus SSH under the hood.
- There is still no public ingress, HA, or external control plane in this phase.
- Browser fallback stays bounded and pragmatic; the premium path remains Cursor over the same Beagle-owned workspace.
- This phase does not replace `B20.4`; it composes on top of it.

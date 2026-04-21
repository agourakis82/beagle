# B20.4 — Known Limits

- The managed attach plane is still private and cluster-internal.
- This phase does not add public ingress.
- This phase does not add HA.
- This phase does not migrate the workspace into a full Coder control plane.
- The managed path is coder-compatible in access shape, but it is still Beagle-owned and operator-bounded.
- The managed path still depends on private Kubernetes reachability and an auto-managed `kubectl port-forward` under the alias, not on external host routing.
- External hostnames, Coder Connect, and Desktop-style managed host routing remain future work.

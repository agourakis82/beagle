# B20.3 — Known Limits

- The operator-friendly attach plane remains `cluster-internal`; it still uses bounded
  `kubectl port-forward` under the helper instead of public ingress.
- `Cursor` remains a premium client, not a canonical state owner.
- The helper-managed attach path still depends on an operator SSH keypair and the bounded
  `authorized_keys` secret for the workspace SSH sidecar.
- This phase does not add HA, public exposure, a Coder control plane, or multi-workspace user
  management.

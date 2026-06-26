# Registry Hardening

Full design, threat model, and staged rollout:
`docs/exocortex/REGISTRY_HARDENING_PLAN.md`

Files here:

| File | Phase | Purpose |
|---|---|---|
| `00-cluster-ca.yaml` | Phase 1 | Self-signed CA + ClusterIssuer |
| `01-registry-cert.yaml` | Phase 1 | TLS cert for 192.168.3.207:5003 |
| `02-registry-ca-configmap.yaml` | Phase 4 | CA PEM distributed to build jobs (fill PEM before applying) |

Apply only after reading the full plan. Do not skip phases.

# B21.4 Known Limits

- The DataCite deposit payload uses a placeholder DOI prefix for draft staging; no real registry prefix is consumed in this phase.
- The Crossref bundle is deposit-ready XML only; no submission handshake is attempted.
- `readiness_state=claim-linked-human-eval-pending` can coexist with technical deposit readiness. This is intentional.
- The package is cluster-internal and repo-native; it is not yet a public publication surface.

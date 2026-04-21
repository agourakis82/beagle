# B23.6 Known Limits

- The compiler eval harness is bounded and intentionally compares a small policy set per task profile.
- The derived compiler policy is evidence-backed for the canonical eval cases, not for every future task shape.
- Drift GraphRAG is evaluated as a bounded candidate and is not globally promoted by this phase.
- No new embedding backend, reranker, ingress, or HA surface is introduced.
- Editorial and scientific readiness limits remain explicit and are not hidden by context policy learning.

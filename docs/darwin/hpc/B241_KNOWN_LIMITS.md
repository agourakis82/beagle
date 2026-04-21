# B24.1 — Known Limits

- The planner stays bounded and operator-visible; it does not become a full
  autonomous executor in this phase.
- Recipe and experiment targets are selected from the canonical Beagle
  workstream/program bindings rather than from a separate planning substrate.
- Planner policy is explicit and coherent, but still mostly hand-authored in
  this first phase; deeper policy learning belongs in later work.
- The planner does not hide editorial or scientific readiness limits, including
  `claim-linked-human-eval-pending` where that still applies.
- The phase reuses the current retrieval and memory compiler stack and does not
  introduce new embedding backends, rerankers, ingress, or HA.

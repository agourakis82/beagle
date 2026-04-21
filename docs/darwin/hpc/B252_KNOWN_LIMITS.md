# B25.2 — Known Limits

- `B25.2` is a bounded read/write coordination surface; it does not add a new
  autonomous orchestration runtime.
- Compute selection is explicit and policy-aware, but this phase does not add
  new Slurm partitions, MIG automation, or time-slicing rollout logic.
- Partner-dev access remains operator-mediated and scoped; per-user cluster
  identity is still not live here.
- The workbench surfaces execution/result refs that already exist; it does not
  replace the underlying execution, review, or continuation contracts.
- The control-room “last result” catalog may be empty while the execution plane
  still exposes non-empty `execution_result_links_path` and `result_link_count`;
  smoke validation accepts either path as evidence of a visible result surface.
- The current live GPU-sharing stance remains the same as `B25.1`:
  isolated typed GPU is live, oversubscribed/shared GPU remains modeled but not
  enabled as the canonical live lane.

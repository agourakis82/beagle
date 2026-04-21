# B26.1 — Known Limits

- Study registration is workspace-lane scoped and bounded to canonical run artifacts currently
  visible in that lane; this phase does not add cross-workspace federation.
- Sweep variants are derived from existing run/replay metadata and do not yet support arbitrary
  parameter-grid expansion with independent schedulers.
- Comparative output is category-level (`code`, `config`, `environment`, `result`) and does not
  yet include statistical significance or custom evaluator plugins.
- The study DAG is intentionally bounded and descriptive; it is not a generic execution runtime.

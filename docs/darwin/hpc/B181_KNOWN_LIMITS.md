# B18.1 — Known Limits

- This phase creates one bounded context packet surface for a canonical
  workstream. It is not a general multi-workstream memory orchestration layer.
- `experiment_flags` are best-effort. The preferred source is the latest
  pipeline `run_report` via `source_run_id`; bounded fallback from recent memory
  metadata is allowed when that path is absent.
- `latest_physio` is best-effort. Packet generation does not fail solely because
  a physiological snapshot is absent.
- `memory_hits` are bounded and compact. This phase does not expose a raw memory
  dump to tools.
- The recommended recipe is heuristic and intentionally conservative.
- Strong compile proof remains containerized while the local host toolchain
  remains below the workspace MSRV.

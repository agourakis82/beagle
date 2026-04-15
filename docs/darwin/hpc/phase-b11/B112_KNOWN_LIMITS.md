# B11.2 Known Limits

## Current Limits

- the catalog is materialized as a host-side JSON file
- query semantics are limited to internal lightweight filters
- no full text search or arbitrary query DSL exists
- no external ingress or public consumer surface exists
- no separate result index service or persistent database exists

## Live Shape

- catalog entries are derived from published `artifact-manifest.json` objects only
- the current canonical filters are `profile_id`, `run_label`, and `job_id`
- the first-pass query surface is optimized for discovery and lookup, not analytics

## Interpretation

B11.2 should make result discovery canonical and queryable without making the
platform heavier than necessary in the first pass.

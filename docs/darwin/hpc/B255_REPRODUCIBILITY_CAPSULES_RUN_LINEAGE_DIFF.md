# B25.5 — Reproducibility Capsules / Run Lineage & Diff

## Objective

Promote the workbench from deterministic run/result binding to replay-grade lineage by
capturing one canonical run capsule per run and making the latest run comparable to its direct
prior lineage parent inside the same Beagle-owned workstream/workspace/session envelope.

## Canonical scope

- One submitted workbench run produces one run capsule.
- The capsule stays Beagle-owned and reuses the existing reservation, run, and deterministic
  result binding flow.
- The latest run can be compared with its prior lineage parent through a bounded run diff.
- A replay request can be derived from the latest run capsule without creating a second
  execution plane.

## What a run capsule contains

- Identity: `workstream_id`, `workspace_id`, `session_id`, `run_id`, `reservation_id`
- Run/result identity: `submitted_job_id`, `published_result_job_id`, `run_label`
- Workload configuration: `selected_subagent_id`, `task_family`, `compute_profile_id`,
  `recipe_kind`, `experiment_id`
- Repo/runtime envelope when observable: canonical repo/branch/track, git branch/commit,
  patch ref, dirty state, image reference/digest
- Retrieval/reasoning envelope: retrieval query type/profile, GraphRAG mode, temporal truth view,
  config fingerprint
- Input/result materialization: input manifest, artifact manifest, published result manifest,
  bound result refs

## Canonical diff categories

- `code`
- `config`
- `environment`
- `result`

Each category is explicit even when unchanged, so Beagle can explain whether two runs differ
because the code changed, the workload configuration changed, the compute/runtime lane changed,
or only the output changed.

## Replay boundary

The replay request is bounded. It does not bypass the workbench or scheduler. It simply freezes
the latest run capsule into a replay-grade request document that can be re-submitted through the
existing bounded workbench execution lane.

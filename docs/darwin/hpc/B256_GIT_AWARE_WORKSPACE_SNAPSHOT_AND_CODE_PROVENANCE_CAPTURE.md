# B25.6 — Git-Aware Workspace Snapshot & Code Provenance Capture

## Objective

Strengthen replay-grade reproducibility by capturing one Git-aware code provenance envelope per
run and binding it into the same Beagle-owned run capsule, deterministic result binding, and run
diff flow.

## Canonical scope

- One submitted workbench run produces one Git-aware workspace snapshot.
- One submitted workbench run produces one source fingerprint.
- One submitted workbench run produces one code provenance envelope bound to the same
  `workstream/workspace/session/run`.
- The latest run diff can explain code-state differences explicitly instead of collapsing them to
  `branch=none commit=none patch_ref=none dirty=unknown`.
- The bounded workbench scheduler and result plane remain unchanged.

## What code provenance captures

- Identity: `workstream_id`, `workspace_id`, `session_id`, `selected_subagent_id`,
  `submitted_job_id`, `run_label`
- Git-aware workspace state: `repo_root`, `branch`, `commit`, `tree_ish`, `dirty_state`,
  `patch_ref`
- Source fingerprint: `source_fingerprint`, `lockfile_fingerprints`
- Runtime envelope: `image_reference`, `image_digest`, `artifact_manifest_key`

## Capture strategy

- Prefer a local Git-aware capture when the runtime can see the workspace checkout.
- Accept a bounded workspace-provided attestation when the runtime cannot see the checkout
  directly.
- Keep the capture explicit. Missing fields stay explicit instead of being guessed.

## Diff boundary

The run diff now makes code-state changes explicit by comparing:

- repo root
- branch
- commit
- tree-ish
- patch ref
- dirty state
- source fingerprint
- lockfile fingerprints

This is still bounded. It is not a full provenance platform or a source-control replacement.

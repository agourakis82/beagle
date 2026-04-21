# B25.1 — GO / NO-GO

Status: GO

## GO Criteria

This phase is `GO` if:

- the same Beagle-owned workspace can be attached from `VS Code` and `Cursor`
- repo hydration remains explicit and reproducible
- GPU/compute access is modeled through bounded typed profiles
- partner-dev access is explicit and scoped
- the same `workstream_id` / `workspace_id` / `session_id` remain preserved
- cluster stays green
- `Slurmctld(primary)` stays `UP`

## Decision

`GO`.

What is now explicit:

- workspace tenancy is frozen as a Beagle-owned shared workspace contract
- the external-workspace-compatible registration remains attached to the same
  identity instead of creating a second state owner
- the canonical warm-start path remains `template-backed-prehydrated-pvc`
- the live GPU lane remains the typed isolated `gpu-single-v1` path
- partner-dev access is bounded to the shared workspace plus a narrowed profile
  scope

# B20.1 — GO / NO-GO

Status: GO

## GO Criteria

This phase is `GO` if:

- one canonical cluster workspace starts in `beagle`
- the browser IDE responds through the internal service
- the workspace contains the Beagle-owned context packet
- the workspace contains the Beagle-generated `context.env`
- `Cursor`, `Claude Code`, and `Codex` continue to resolve from the same Beagle-owned identity
- restart preserves the same `workstream_id`, `workspace_id`, and `session_id`
- cluster stays green
- `Slurmctld(primary)` stays `UP`

## Decision

`GO`.

What is already true:

- the Beagle habitat runtime surface exists
- the workspace Kubernetes manifests exist
- the bootstrap/context injection path exists
- the workspace launch path now uses the official `OpenVSCode Server` image with a bounded
  Beagle bootstrap wrapper
- local/container validation is clean
- the live cluster path reaches Beagle bootstrap, physio ingest, memory ingest, workspace PVC
  provisioning, workspace IDE health, repo hydration, and restart recovery

What closed the blocker:

- the old `code-server` substrate was removed from the canonical path after reproducing its
  runtime failure cluster-wide
- the official `OpenVSCode Server` substrate now stays healthy live on `t560-proxmox`
- the Beagle-owned context remains present before and after restart
- cluster health stays green and `Slurmctld(primary)` stays `UP`

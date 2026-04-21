# B18.4 — Known Limits

Status: GO

## Current Limits

- this phase proves a bounded `patch_ref` path; it does not auto-create git
  commits or mutate remote branches
- repo-native output is audit-friendly and recoverable, but still artifact-first
  rather than a full commit promotion workflow
- the strong compile proof remains the containerized Rust 1.89 path because the
  host toolchain is still below the repo MSRV

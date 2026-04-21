# B26.7 Known Limits

- The Sounio workspace is a dedicated cluster habitat, not a multi-tenant
  workspace platform.
- The first rollout is CPU-first for interactive development; GPU is available
  through Slurm workflows rather than as a permanent editor node.
- The workspace image is provisioned for compiler/language work, but future
  repo-specific tools may still require incremental package additions.
- The current OpenVSCode container can intermittently fail `git`/`curl` network
  hydration with `getaddrinfo() thread failed to start`; the bounded workaround
  in this phase is a host-side git seed into the same workspace PVC, which
  preserves the canonical Beagle-owned root while keeping rollback explicit.
- This phase does not auto-launch a new Sounio study or planner campaign.
- The Beagle workspace remains intact and separate; this phase does not convert
  the existing `beagle-workspace` PVC into the Sounio home.

# Workstream Registry

This directory is the canonical repo-native registry for Darwin/HPC workstreams
that live under Beagle governance.

Rules:

1. each workstream is represented by one versioned spec file
2. the registry expresses identity, compute, result, consumer, recovery and
   promotion policy
3. runtime `workstream_cutover_policy` should align with the canonical spec
4. adding a workstream here does not automatically make it canonical; promotion
   still requires an explicit phase
5. execution recipes live under `docs/darwin/hpc/workstreams/recipes/` and are
   versioned alongside the workstream specs they govern

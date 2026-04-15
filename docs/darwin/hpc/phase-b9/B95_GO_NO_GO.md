# B9.5 GO / NO-GO

## GO

B9.5 is GO when all of the following are true:

1. `GET /profiles` returns the clean profile catalog.
2. `cpu-short-v1` submits, completes, and returns a valid artifact manifest.
3. `cpu-batch-v1` submits, completes, and returns a valid artifact manifest.
4. `gpu-single-v1` submits, completes, and returns a valid artifact manifest.
5. All three flows use the same gateway surface.
6. Cluster health remains stable after the test matrix.
7. Slurm health remains stable after the test matrix.
8. No blocked platform policy is reopened.

## GO-WITH-BLOCKER

B9.5 is GO-WITH-BLOCKER when:

1. The CPU profile expansion works end to end.
2. The GPU profile needs one bounded correction.
3. That correction does not require topology, ingress, storage, or policy
   reopening.

## NO-GO

B9.5 is NO-GO when any of the following becomes necessary:

1. Raw scheduler payload passthrough.
2. Arbitrary scripts from clients.
3. Storage reopening to make the GPU path work.
4. MPI or multi-node behavior to prove the concept.
5. Cluster health degradation.
6. Slurm health degradation.

## Automation Note

`scripts/phase-b9/run_workload_profile_expansion.sh` produces a preliminary
automation decision:

- `GO` when all three profiles pass.
- `GO-WITH-BLOCKER` when the CPU profiles pass and the GPU profile does not.
- `NO-GO` otherwise.

Manual review is still required for the final policy and health assessment.

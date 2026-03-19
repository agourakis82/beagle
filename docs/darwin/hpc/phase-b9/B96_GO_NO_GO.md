# B9.6 GO / NO-GO

## GO

B9.6 is GO when all of the following are true:

1. `darwin-research` can reach the internal gateway in a controlled way.
2. At least one real submit/status/artifact flow completes via the
   research-facing path.
3. The approved profile catalog remains the only admitted submission surface.
4. Cluster health remains green.
5. Slurm health remains green.
6. No blocked platform constraint is reopened.

Canonical run `20260319-062504` satisfies this state:

1. `darwin-research` reached the gateway successfully.
2. `GET /profiles` succeeded.
3. Invalid submit was rejected with HTTP 400.
4. Approved submit/status/artifact/stdout/stderr succeeded.
5. Kubernetes nodes were all `Ready` during health capture.
6. Slurm remained healthy.
7. No blocked platform constraint was reopened.

## GO-WITH-BLOCKER

B9.6 is GO-WITH-BLOCKER when all of the research admission proofs succeed, the
profile boundary remains enforced, but a bounded environmental issue outside the
gateway path prevents calling the cluster fully green.

Earlier run `20260319-061231` fit this state:

1. `darwin-research` reached the gateway successfully.
2. `GET /profiles` succeeded.
3. Invalid submit was rejected with HTTP 400.
4. Approved submit/status/artifact/stdout/stderr succeeded.
5. Slurm remained healthy.
6. `5860-proxmox` was already `NotReady` during health capture.

## NO-GO

B9.6 is NO-GO when any of the following becomes necessary:

1. Raw scheduler payload exposure.
2. Arbitrary scripts from research-side callers.
3. Public exposure through ingress or edge.
4. Storage reopening to make the path work.
5. Topology changes to make the path work.
6. Cluster health degradation.
7. Slurm health degradation.

## Validation Targets

The B9.6 validation set must prove:

1. `GET /profiles` works from `darwin-research`.
2. `POST /jobs/submit` works with an approved profile only.
3. Status retrieval works.
4. Artifact manifest retrieval works.
5. Stdout retrieval works.
6. Stderr retrieval works.

## Automation Note

`scripts/phase-b9/run_research_controlled_admission.sh` produces a preliminary
automation decision based on the research-side path. Final policy and health
review remain manual.

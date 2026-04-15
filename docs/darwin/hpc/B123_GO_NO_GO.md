# B12.3 GO / NO-GO

## Current status

B12.3 is currently `GO`.

Current evidence:

1. the Beagle internal control surface is live in the cluster
2. `GET /api/darwin/hpc/control` returns a unified operator-facing summary
3. `cpu-short-v1` submit/status/artifact-manifest passed through Beagle for job
   `34`
4. published result lookup/manifest passed through Beagle for published job `32`
5. bridge health/providers/execute remained intact
6. cluster and Slurm remained green during the smoke

## GO if

1. one internal Beagle surface unifies HPC, results and bridge operations
2. profiles, submit, status, results and manifest retrieval answer through the
   Beagle service
3. bridge health/providers/execute remain intact
4. the cluster remains green
5. Slurm remains green
6. no lower-layer foundation is reopened

## GO-WITH-BLOCKER if

1. the unified control surface exists with correct placement
2. but one bounded upstream Darwin gateway dependency is temporarily unhealthy
3. and there is no architectural regression in the Beagle side

## NO-GO if

1. the phase reopens bridge foundation design
2. raw scheduler payloads are exposed
3. ingress, edge, HA or topology changes are pulled in
4. the internal surface is split back into unrelated routes without a coherent
   control layer

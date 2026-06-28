# B9.6 Research-facing Controlled Admission

## Canonical Starting State

- B9.1a = GO
- B9.1 = GO
- B9.2 = GO
- B9.3 = GO
- B9.4 = GO
- B9.5 = GO
- B9 = GO-WITH-CONSTRAINTS

The internal HPC gateway is already live and supports:

- `cpu-short-v1`
- `cpu-batch-v1`
- `gpu-single-v1`

Artifact flow is already canonical. Cluster health is green. Slurm health is
green.

## Objective

B9.6 extends the existing internal HPC service layer from platform-owned use to
research-facing controlled admission.

The proof target is:

`darwin-research` can consume the internal gateway in a controlled way without
turning the platform into broad self-service and without reopening storage,
ingress, edge, HA, or topology.

## Phase Structure

### B9.6a - Admission policy

Define who may call the gateway, from where, and for which approved profiles.

### B9.6b - Namespace consumer path

Allow `darwin-research` to reach the internal ClusterIP gateway through an
explicit controlled path.

### B9.6c - End-to-end controlled consumer validation

Run a real submit/status/artifact flow from the research namespace using an
approved profile only.

### B9.6d - Closure

Freeze the contract, known limits, and remaining gaps.

## What B9.6 Delivers

- A research admission policy bound to `darwin-research`.
- Minimal manifests for controlled namespace-to-gateway communication.
- A research canary job that exercises `GET /profiles`, `POST /jobs/submit`,
  status retrieval, artifact retrieval, stdout retrieval, and stderr retrieval.
- Scripts that collect the expected B9.6 artifact bundle under
  `phase-b9/<RUN_ID>/research-admission/`.

## Central Rule

The gateway remains policy-first:

- `profile_id + parameters` only
- no raw scheduler payloads
- no arbitrary scripts
- no arbitrary partition requests
- no arbitrary GPU count requests
- no public exposure

The only expansion in B9.6 is controlled research-side consumption of the same
internal service layer.

## Canonical Execution Record

Canonical run: `20260319-062504`

Observed result:

- `darwin-research` reached the internal gateway successfully.
- `GET /profiles` succeeded.
- An invalid submit with extra parameters was rejected with HTTP 400.
- The approved `cpu-short-v1` submit/status/artifact/stdout/stderr flow
  completed successfully.
- Slurm remained healthy during the run.
- Kubernetes health capture remained fully green, including `5860-proxmox` in
  `Ready`.

Canonical verdict:

`B9.6 = GO`

Earlier run `20260319-061231` remains part of the record as the bounded
environmental blocker run: the gateway path was already good, but
`5860-proxmox` was `NotReady` during that earlier health capture.

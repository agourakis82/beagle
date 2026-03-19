# B9.5 Profile Catalog

## Public API

- `GET /profiles`
- `POST /jobs/submit`
- `GET /jobs/{job_id}`
- `GET /jobs/{job_id}/artifact-manifest`
- `GET /jobs/{job_id}/stdout`
- `GET /jobs/{job_id}/stderr`

## Submission Shape

The gateway accepts only profile-based requests:

```json
{
  "profile_id": "cpu-short-v1",
  "parameters": {
    "run_label": "test-001"
  }
}
```

Unknown fields are rejected. Unknown profiles are rejected. Extra parameters are
rejected.

## Profiles

### `cpu-short-v1`

- kind: CPU
- node shape: single-node
- GPU: false
- max walltime: `00:02:00`
- artifact mode: deterministic-small
- allowed parameters: `run_label`
- intended use: current canary-class job under a stable named profile

### `cpu-batch-v1`

- kind: CPU
- node shape: single-node
- GPU: false
- max walltime: `00:10:00`
- artifact mode: deterministic-medium
- allowed parameters: `run_label`
- intended use: richer CPU-only batch validation without reopening platform
  boundaries

### `gpu-single-v1`

- kind: GPU
- node shape: single-node
- GPU: true
- max walltime: `00:05:00`
- artifact mode: deterministic-small
- allowed parameters: `run_label`
- intended use: first GPU-backed internal gateway validation without MPI,
  multi-node behavior, or storage coupling

## Contract Files

- `phase-b9/contract/hpc-workload-profiles.yaml`
- `phase-b9/contract/gateway-submit-schema.json`
- `phase-b9/contract/cpu-short-job.json`
- `phase-b9/contract/cpu-batch-job.json`
- `phase-b9/contract/gpu-single-job.json`

## Example Requests

- `phase-b9/templates/example_cpu_short_request.json`
- `phase-b9/templates/example_cpu_batch_request.json`
- `phase-b9/templates/example_gpu_single_request.json`

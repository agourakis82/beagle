# B11.1 - Object-backed Retrieval

## Objective

Make the published object plane the primary retrieval source behind the
lab-facing gateway so consumers resolve canonical results from object storage
instead of host-side execution paths.

## Design Rule

- keep the gateway API stable
- prefer published RGW objects for retrieval
- use host-side retrieval only as explicit fallback
- do not move object credentials into Kubernetes

## Retrieval Surface

- `GET /jobs/{job_id}`
- `GET /jobs/{job_id}/artifact-manifest`
- `GET /jobs/{job_id}/artifact`
- `GET /jobs/{job_id}/stdout`
- `GET /jobs/{job_id}/stderr`

## Live Result

- canonical run: `20260319-183834`
- `cpu-short-v1` resolved from
  `hpc/cpu-short-v1/24/b96-20260319-062504/artifact-manifest.json`
- `cpu-batch-v1` resolved from
  `hpc/cpu-batch-v1/31/b102-20260319-072237-cpu-batch/artifact-manifest.json`
- `gpu-single-v1` resolved from
  `hpc/gpu-single-v1/32/b102-20260319-072237-gpu-single/artifact-manifest.json`
- published `artifact.bin`, `stdout.txt`, and `stderr.txt` were retrieved from
  the object plane for all three profiles
- the GPU-backed retrieval preserved `r740-proxmox` as the execution truth

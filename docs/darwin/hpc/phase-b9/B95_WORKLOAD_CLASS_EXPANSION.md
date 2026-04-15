# B9.5 Workload Class Expansion over the Same Service Layer

## Canonical Starting State

- B9.1a = GO
- B9.1 = GO
- B9.2 = GO
- B9.3 = GO
- B9.4 = GO
- B9 = GO-WITH-CONSTRAINTS

The existing platform has already proven:

- the Slurm control boundary is real
- the REST path is real
- the artifact flow is real
- the lab-facing gateway is real

## Objective

B9.5 expands the same internal gateway from a single canary path into a
controlled multi-profile internal HPC gateway. This phase increases capability,
not platform surface area.

The target proof is:

the same gateway can admit more than one safe workload class without reopening
storage, ingress, HA, or topology.

## Phase Deliverables

- A frozen profile catalog with three approved workload classes:
  `cpu-short-v1`, `cpu-batch-v1`, and `gpu-single-v1`.
- A strict submission contract that accepts only `profile_id` and approved
  profile parameters.
- Gateway configuration that can surface `GET /profiles` and enforce
  profile-based admission on `POST /jobs/submit`.
- Validation scripts that exercise the three workload classes and write the
  expected B9.5 run bundle under `phase-b9/<RUN_ID>/workload-profiles/`.

## Approved Profiles

### `cpu-short-v1`

Purpose:
short-lived CPU-only single-node canary with deterministic small artifacts.

### `cpu-batch-v1`

Purpose:
slightly richer CPU-only single-node batch class with longer walltime and a
deterministic medium artifact bundle.

### `gpu-single-v1`

Purpose:
first GPU-backed single-node workload through the same gateway, with no MPI,
no multi-node behavior, and no storage dependency.

## Required API Surface

- `GET /profiles`
- `POST /jobs/submit`
- `GET /jobs/{job_id}`
- `GET /jobs/{job_id}/artifact-manifest`
- `GET /jobs/{job_id}/stdout`
- `GET /jobs/{job_id}/stderr`

`POST /jobs/submit` must not accept raw scheduler payloads, arbitrary job
scripts, arbitrary partitions, or arbitrary GPU counts. The service layer
remains a policy surface, not a scheduler tunnel.

## Validation Matrix

1. Submit `cpu-short-v1` through the gateway and verify completion plus
   artifact manifest retrieval.
2. Submit `cpu-batch-v1` through the same gateway and verify completion plus
   artifact manifest retrieval.
3. Submit `gpu-single-v1` through the same gateway and verify completion plus
   artifact manifest retrieval.
4. Confirm cluster and Slurm health after the matrix completes.

## Bounded Scope

Still out of scope for B9.5:

- MPI
- multi-node jobs
- arbitrary scripts
- arbitrary scheduler payloads
- arbitrary partitions or GPU counts from clients
- object-store publication
- persistent job database
- UI work
- ingress or edge reopening
- storage reopening
- HA
- `slurmdbd` dependency
- `r740` joining Kubernetes
- Slurm running inside Kubernetes

## Result

If B9.5 closes in GO, the platform state advances from
"single canary gateway" to "multi-profile internal HPC service layer" while
holding the same boundary conditions established in B9.4.

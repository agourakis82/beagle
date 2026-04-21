# HPC Agent Bootstrap

This is the shortest safe path for an agent entering the Beagle AI/HPC lab.

Read this before touching the stack.

Then read:

1. [DEV_WORKFLOW.md](/home/devsounio/beagle/k8s/hpc-sota/DEV_WORKFLOW.md)
2. [AGENTS.md](/home/devsounio/beagle/k8s/hpc-sota/AGENTS.md) or [CLAUDE.md](/home/devsounio/beagle/k8s/hpc-sota/CLAUDE.md)
3. [STACK_SEMAPHORE.md](/home/devsounio/beagle/k8s/hpc-sota/STACK_SEMAPHORE.md)
4. [PROJECT_ONBOARDING_BLUEPRINT.md](/home/devsounio/beagle/k8s/hpc-sota/PROJECT_ONBOARDING_BLUEPRINT.md) if the task is about admitting, shaping, or promoting another project
5. the exact track README you are changing
6. if the task touches a personal Tailnet control surface:
   - [TAILNET_DIRECT_CLUSTER_ACCESS.md](/home/devsounio/beagle/k8s/hpc-sota/TAILNET_DIRECT_CLUSTER_ACCESS.md)

## What is actually live

These are real, proven lanes, not design docs:

- `K8s + JobSet + Kueue + OrangeFS`
- `Slurm/Slinky + OrangeFS + K8s`

These workload tracks are green:

- `pbpk`
- `omics`
- `pl-runtime`

These operational proofs are green:

- OrangeFS shared data plane
- Kubernetes training canary
- Slurm QoS proof (`burst > normal`)
- Slurm GPU scheduling
- real CUDA compute in Slurm via PyTorch
- Tailscale node-agnostic access for Sounio workspace and Grafana

## First mental model

Always decide the lane first.

Use Kubernetes when the task is about:

- distributed training
- `JobSet`
- `Kueue`
- cluster-native experiments
- controller behavior

Use Slurm when the task is about:

- HPC batch
- `PBPK`
- `omics`
- `pl-runtime`
- QoS
- partitions
- accounting
- queue semantics

## Current control-plane truths

These are the truths agents should not casually fight:

- machine-level source of truth: `/home/devsounio`
- live lab root: `/home/devsounio/beagle/k8s/hpc-sota`
- current Slurm accounting source of truth: externalized K8s MariaDB candidate via `slurmdbd-mariadb-ext.darwin.lan`
- current worker-safe Kubernetes API endpoint: `https://k8s-api.darwin.lan:6443`
- current worker resolution for that endpoint: `k8s-api.darwin.lan -> 10.100.100.2`
- current Tailnet direct-access strategy for trusted personal machines: advertise
  the Kubernetes underlay `10.100.100.0/24` and keep using
  `https://k8s-api.darwin.lan:6443`
- do not casually revert workers back to `https://192.168.3.169:6443` until that path is repaired
- `192.168.3.169` remains the Proxmox/t560 management IP on `vmbr0`; this workaround does not change the host management surface
- root cause of the earlier worker outage: `t560` was accepting the overlapping Tailscale subnet route `192.168.3.0/24`, which hijacked replies for the management LAN away from `vmbr0`
- current safety setting on `t560`: `tailscale set --accept-routes=false`
- `slurm-pilot-mariadb` remains a dormant migration artifact at `0/0`
- `slurm-pilot-mariadb-ext` is the active live backend:
  - current state is `1/1 Running`
  - stable alias: `slurmdbd-mariadb-ext.darwin.lan`
  - latest preflight against that alias is green
  - `slurmdbd` currently points at that alias
- current Sounio implementation source of truth: `/home/devsounio/sounio`
- current Sounio dev branch: `integration/sounio-dev-ready-base`
- current promoted Sounio workspace surface: `sounio-workspace-habitat` behind stable service `sounio-workspace`
- if workspace tailnet services ever show `IngressSvcNoBackendsConfigured`
  while the habitat is healthy, verify the VIP dataplane before touching the
  workspace itself; a known operator churn mode can leave stale workspace
  tailnet `Service` status that is repaired by recreating only:
  - `beagle/sounio-workspace-tailnet-http`
  - `beagle/sounio-workspace-tailnet-ssh`
  - use:
    - `/home/devsounio/beagle/k8s/hpc-sota/ops/repair-workspace-tailnet-services.sh`

## The commands agents should start with

From the lab root:

```bash
cd /home/devsounio/beagle/k8s/hpc-sota
./ops/hpc-bootstrap.sh
./ops/hpc-route-doctor.sh
./ops/slurmdbd-backend-doctor.sh
./ops/workspace-platform-doctor.sh
source ops/lab-ops.sh
lab_status
lab_slurm_status
lab_orangefs_status
```

That is the minimum safe health check before changing scheduler, workload, or storage behavior.

Note:

- `ops/lab-ops.sh` assumes non-interactive SSH access to `OPS_HOST`
- if that SSH trust is not in place, prefer the local read-only entrypoints first

If you want one combined read-only entrypoint from anywhere on the machine:

```bash
/home/devsounio/bootstrap-dev-plane.sh
```

What the bootstrap/doctor pair now answers quickly:

- whether you are talking to the cluster locally or through the remote ops host
- whether `k8s-api.darwin.lan` still resolves and routes to `10.100.100.2`
- whether the Kubernetes API is answering `/readyz`
- whether Kueue, Slurm, OrangeFS, Grafana, and the Sounio workspace surface are visible
- whether the current `slurmdbd` backend still has a viable read and rollback path
- whether the workspace platform catalog and promoted workspace surfaces are healthy enough to admit another project

If you only want one read-only command to orient yourself, start with:

```bash
cd /home/devsounio/beagle/k8s/hpc-sota
./ops/hpc-bootstrap.sh
./ops/hpc-route-doctor.sh
./ops/slurmdbd-backend-doctor.sh
./ops/workspace-platform-doctor.sh
```

## The commands agents should prefer

### Slurm lane

```bash
source ops/lab-ops.sh
lab_copy_and_run slurm-pilot/scripts/55-submit-pbpk-cpuops.sh
lab_copy_and_run slurm-pilot/scripts/57-submit-omics-cpuops.sh
lab_copy_and_run slurm-pilot/scripts/58-submit-plruntime-gpuorangefs.sh
lab_copy_and_run slurm-pilot/scripts/64-submit-plruntime-torch-gpucompute.sh
```

### Kubernetes lane

```bash
bash orangefs-hybrid/run-k8s-orangefs-training-canary.sh
bash orangefs-hybrid/run-k8s-orangefs-cuda-pilot.sh
bash orangefs-hybrid/run-k8s-orangefs-artifact-probe.sh
```

## Golden rules

1. Prefer proven scripts over ad hoc commands.
2. Use local scratch first; promote durable outputs to OrangeFS.
3. Do not use OrangeFS as shared scratch by default.
4. Do not run heavy Slurm GPU jobs and heavy K8s GPU jobs on the same nodes unless contention is intentional.
5. Do not touch `slurmdbd` migration artifacts during unrelated work.
6. If local `kubectl` is uncertain, use `ops/lab-ops.sh` rather than improvising.
7. If Sounio workspace behavior matters, read [WORKSPACE_K8S.md](/home/devsounio/projects/sounio/WORKSPACE_K8S.md) before editing workspace infrastructure.

## Observability and verification

Official Grafana endpoint:

- `http://darwin-grafana.tail21cbc4.ts.net`

Current top-tier dashboards:

- `Darwin HPC Control Room`
- `Darwin Sounio Dev Loop`
- `Darwin Slurm Ops`
- `Darwin Sounio Compiler Pipeline`

If something looks wrong, verify in this order:

1. `lab_status`
2. `lab_slurm_status`
3. `lab_orangefs_status`
4. [STACK_SEMAPHORE.md](/home/devsounio/beagle/k8s/hpc-sota/STACK_SEMAPHORE.md)
5. the exact submit script or manifest used
6. Grafana dashboards
7. only then infrastructure edits

## Agent checklist before edits

1. Identify the lane: K8s or Slurm.
2. Confirm source-of-truth docs for the target area.
3. Run the health checks.
4. Use the smallest proven workload or smoke first.
5. Keep artifacts and evidence.

## Agent checklist after edits

1. Re-run health checks.
2. Re-run the smallest relevant proven workload.
3. Confirm artifacts or metrics moved as expected.
4. Update the nearest README if behavior changed.
5. Call out any yellow-zone risk explicitly.

## Yellow zones

These files are not casual edit targets:

- [slurm-pilot/SLURMDBD_EVOLUTION.md](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/SLURMDBD_EVOLUTION.md)
- [slurm-pilot/values/mariadb-values.yaml](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/values/mariadb-values.yaml)
- [slurm-pilot/values/slurm-pilot-values.external-db.example.yaml](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/values/slurm-pilot-values.external-db.example.yaml)
- [beagle/k8s/sounio-workspace/configmap.yaml](/home/devsounio/beagle/k8s/sounio-workspace/configmap.yaml)
- [projects/sounio/WORKSPACE_K8S.md](/home/devsounio/projects/sounio/WORKSPACE_K8S.md)

Only touch them when the task is explicitly about migration, workspace bootstrap, or platform resilience.

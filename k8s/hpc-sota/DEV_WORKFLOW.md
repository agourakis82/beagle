# Dev Workflow

This is the practical "how do I actually use this lab" guide.

If you are a human, start here.

If you are an agent, read this file first, then:

- [AGENTS.md](/home/devsounio/beagle/k8s/hpc-sota/AGENTS.md) for Codex-style work
- [CLAUDE.md](/home/devsounio/beagle/k8s/hpc-sota/CLAUDE.md) for Claude Code-style work

## What is live right now

These paths are already working:

- Kubernetes-native path:
  - `K8s + JobSet + Kueue + OrangeFS`
- Classical HPC path:
  - `Slurm/Slinky + OrangeFS + K8s`

These workload lanes are already green:

- `pbpk`
- `omics`
- `pl-runtime`

These operational proofs are already green:

- OrangeFS shared data plane
- DDP training canary
- QoS policy in Slurm (`burst > normal`)
- GPU scheduling through Slurm
- real CUDA compute inside a Slurm batch job using PyTorch

## The simplest mental model

Use the stack in two lanes:

1. Kubernetes lane
   - use for distributed training
   - use for `JobSet`, `Kueue`, and cluster-native experiments
   - OrangeFS stores durable datasets and checkpoints
   - scratch stays local with `emptyDir` or local NVMe
2. Slurm lane
   - use for classical HPC batch work
   - use for `PBPK`, `omics`, and `pl-runtime` batch jobs
   - OrangeFS stores shared outputs and checkpoints
   - QoS and accounting live here

Short version:

- if the job is "distributed training / cloud-native batch", start in Kubernetes
- if the job is "HPC batch / domain workload / queue semantics", start in Slurm

## Critical rules

Follow these rules unless you are intentionally changing the platform:

1. Do not run heavy Kubernetes GPU jobs and heavy Slurm GPU jobs on the same GPU nodes at the same time unless you explicitly want contention.
2. Do not use OrangeFS as shared scratch by default.
3. Use OrangeFS for durable outputs:
   - datasets
   - checkpoints
   - shared results
4. Use local scratch for temporary files:
   - `/tmp`
   - pod `emptyDir`
   - local NVMe
5. For new jobs, write locally first and then promote durable artifacts to OrangeFS.
6. Treat the current `slurmdbd` backend on `t560` as the source of truth until a cutover is explicitly completed.
7. If end-of-job writes to OrangeFS are flaky, prefer `worker_local + fetch` over forcing persistence in place.
8. If a node shows pod-level dataplane faults, quarantine it from the workload lane instead of letting the scheduler keep rediscovering the failure.
9. Treat `sbcast` as a supported but newer lane on this Slurm path.
   - keep `embedded` as the conservative default
   - use `sbcast` when you explicitly want to exercise the recovered transfer path
10. Treat the `stepmgr` fix as an operator-image rollout.
   - build a patched operator image
   - install it with explicit image overrides
   - keep `ENABLE_STEPMGR=false` unless you intentionally want to re-enable it globally

## Paths that matter

Repo root:

- [README.md](/home/devsounio/beagle/k8s/hpc-sota/README.md)

OrangeFS path:

- [orangefs-hybrid/README.md](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/README.md)

Slurm path:

- [slurm-pilot/README.md](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/README.md)

Workload tracks:

- [workloads/README.md](/home/devsounio/beagle/k8s/hpc-sota/workloads/README.md)
- [workloads/pbpk/README.md](/home/devsounio/beagle/k8s/hpc-sota/workloads/pbpk/README.md)
- [workloads/omics/README.md](/home/devsounio/beagle/k8s/hpc-sota/workloads/omics/README.md)
- [workloads/pl-runtime/README.md](/home/devsounio/beagle/k8s/hpc-sota/workloads/pl-runtime/README.md)

Helper functions:

- [ops/lab-ops.sh](/home/devsounio/beagle/k8s/hpc-sota/ops/lab-ops.sh)

## Quick start for humans

From a shell in this repo:

```bash
cd /home/devsounio/beagle/k8s/hpc-sota
source ops/lab-ops.sh
```

Then:

```bash
lab_status
lab_slurm_status
```

That gives you:

- Kubernetes node and pod status from `t560`
- Slurm controller, partitions, and job status

`ops/lab-ops.sh` now auto-selects local mode when the current shell already has
working Kubernetes credentials (for example `~/.kube/config` on the machine
source of truth). It only falls back to SSHing into `t560` when local `kubectl`
is not available.

## Quick start for agents

Agents should use the same helper file:

```bash
cd /home/devsounio/beagle/k8s/hpc-sota
source ops/lab-ops.sh
lab_status
lab_slurm_status
```

If a submit script must run on `t560`, copy it there and execute it through:

```bash
lab_copy_and_run slurm-pilot/scripts/55-submit-pbpk-cpuops.sh
```

That avoids assuming local `kubectl` works or that the repo is already synced on `t560`.

## Daily health check

Run these before changing anything important:

```bash
source ops/lab-ops.sh
lab_status
lab_slurm_status
lab_orangefs_status
```

Healthy means:

- Kubernetes nodes are `Ready`
- `t560-proxmox` is free of kubelet `DiskPressure`
- `slurm-pilot` pods are `Running`
- `scontrol ping` is `UP`
- `sinfo` shows `gpu-orangefs` and `cpu-ops`
- OrangeFS mount is visible on `t560`

For the sovereign public/private shell surfaces, the current mechanical checks
are:

- public surfaces:
  - `/home/devsounio/beagle/scripts/infrastructure/check_project_cockpit_public_surfaces.sh`
- public HTML/assets via pod:
  - `/home/devsounio/beagle/scripts/infrastructure/check_project_cockpit_public_assets.sh`
- private inference fabric:
  - `/home/devsounio/beagle/scripts/infrastructure/check_project_cockpit_private_inference.sh`
- tailnet VIP sanity:
  - `/home/devsounio/beagle/scripts/infrastructure/check_sounio_tailnet_vips.sh`
- full shell chain:
  - `/home/devsounio/beagle/scripts/infrastructure/check_project_cockpit_full_shell.sh`

Those checks currently validate:

- `project-cockpit` health on the cockpit VIP
- Vision control-room, Apple-brief, Apple-launchpad, operator-board, runtime-matrix, route-atlas, mission-timeline, sovereign-bridge, sovereign-cockpit-preview, packet-graph, and handoff public APIs
- public showcase inference-fabric truth, packet graph, sovereign bridge, and sovereign cockpit preview
- public HTML routes and their live asset bundles from inside the cockpit pod
- private `SGLang + Dynamo` runtime truth
- workspace HTTP reachability on the correct tailnet port (`:8080`)

## The main development loops

### A. Run a Slurm workload

Use this path for:

- `PBPK`
- `omics`
- `pl-runtime`
- queue-sensitive HPC jobs

Example commands:

```bash
source ops/lab-ops.sh
lab_copy_and_run slurm-pilot/scripts/55-submit-pbpk-cpuops.sh
lab_copy_and_run slurm-pilot/scripts/57-submit-omics-cpuops.sh
lab_copy_and_run slurm-pilot/scripts/58-submit-plruntime-gpuorangefs.sh
lab_copy_and_run slurm-pilot/scripts/64-submit-plruntime-torch-gpucompute.sh
```

Where to inspect results:

- OrangeFS artifacts under:
  - `/var/lib/orangefs-lab/client-runtime/mnt/training-orangefs/slurm-pilot/`
- Slurm state:
  - `lab_slurm_status`
  - `lab_slurm_exec sacct -S now-1day`

### B. Run a Kubernetes workload

Use this path for:

- DDP training canaries
- `JobSet` experiments
- Kueue-admitted distributed jobs

Example commands:

```bash
bash orangefs-hybrid/run-k8s-orangefs-training-canary.sh
bash orangefs-hybrid/run-k8s-orangefs-cuda-pilot.sh
bash orangefs-hybrid/run-k8s-orangefs-artifact-probe.sh
```

Use this lane when the job naturally belongs in Kubernetes.

### C. Add a new workload

Use this checklist:

1. choose the lane
   - Slurm for HPC batch
   - Kubernetes for distributed or cluster-native work
2. create the track manifest or submit script
3. write transient files locally first
4. promote durable outputs to OrangeFS
5. store artifacts under a stable prefix
6. add a README entry for the track
7. rerun health checks

## How to choose the lane

Choose Slurm if you need:

- `sbatch`
- partitions
- QoS
- accounting
- CPU-only or GPU batch semantics
- classical HPC queueing

Choose Kubernetes if you need:

- `JobSet`
- `Kueue`
- controller-driven distributed jobs
- training canaries
- pod-native experiments

## Proven submit paths

These are the current known-good submit scripts:

- Slurm smoke:
  - [50-submit-orangefs-smoke.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/50-submit-orangefs-smoke.sh)
- PBPK:
  - [55-submit-pbpk-cpuops.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/55-submit-pbpk-cpuops.sh)
- Omics:
  - [57-submit-omics-cpuops.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/57-submit-omics-cpuops.sh)
- PL runtime basic:
  - [58-submit-plruntime-gpuorangefs.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/58-submit-plruntime-gpuorangefs.sh)
- PL runtime stress:
  - [61-submit-plruntime-gpu-stress.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/61-submit-plruntime-gpu-stress.sh)
- PL runtime real CUDA compute:
  - [64-submit-plruntime-torch-gpucompute.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/64-submit-plruntime-torch-gpucompute.sh)
- `sbcast` smoke repro:
  - [65-submit-sbcast-smoke.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/65-submit-sbcast-smoke.sh)
- gpuorangefs node gate:
  - [66-gpuorangefs-gate.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/66-gpuorangefs-gate.sh)
- QoS validation:
  - [59-prove-burst-priority.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/59-prove-burst-priority.sh)
  - [63-run-qos-validation.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/63-run-qos-validation.sh)

## Known caveats

- `sbcast` has been recovered, but it is still newer than the long-proven
  `embedded` path.
  - the operator patch removed the hidden `enable_stepmgr` runtime behavior
  - standalone smoke `job 155` and `job 182` completed and wrote
    `hello-from-sbcast`
  - an ABIDE campaign smoke completed end-to-end with
    `PAYLOAD_TRANSFER_MODE=sbcast` on the `worker_local + fetch` lane
  - after persistence hardening, `sbcast + orangefs` campaign validation also
    completed and fetched cleanly on both admitted workers:
    - `job 186` on `gpuorangefs-r770-proxmox`
    - `job 183` on `gpuorangefs-r740-proxmox`
  - keep `embedded` as the conservative default until `sbcast` has more
    production mileage
- `r740-proxmox` was repaired by:
  - upgrading the live Cilium images from `1.19.1` to `1.19.2`
  - keeping the node-scoped base canary active
  - validating both pod-level reachability and a real Slurm smoke on the node

1. Local `kubectl` may not be configured.
   - Use the helper functions that tunnel through `t560`.
2. `t560` can occasionally show stale OrangeFS reads after heavy write churn.
3. The `gpuorangefs` Slurm worker lane is gated by the node label
   `sounio.dev/slurm-worker-gpuorangefs=true`.
   - `r770-proxmox` is admitted.
   - `r740-proxmox` is admitted again after the real `1.19.2` image upgrade and
     a clean pass of:
     - `cilium-health`
     - ordinary pod endpoint reachability
     - Slurm smoke on `gpuorangefs-r740-proxmox`
   - the official re-validation gate is
     [66-gpuorangefs-gate.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/66-gpuorangefs-gate.sh)
     and it takes separate `K8S_NODE_NAME` and `SLURM_NODE_NAME` values for the
     Kubernetes hostname and the Slurm node name
   - the gate now waits up to `60s` for `cilium-health` to converge during
     agent restart windows instead of failing immediately on transient `0/0`
     output
   - the gate also waits for the matching Slurm node to register before
     submitting the smoke job, which avoids a transient `Invalid node name
     specified` failure during fresh worker admission
   - the canonical admit/quarantine helper is
     [68-manage-gpuorangefs-worker.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/68-manage-gpuorangefs-worker.sh)
   - `68-manage-gpuorangefs-worker.sh` now serializes admissions per node and
     stamps an admission ID annotation so an older failed run cannot tear down
     a newer successful admission
   - it also exposes a canonical `repair` action for admitted workers that
     regress into `NOT_RESPONDING`: recycle node-local `cilium`, recreate the
     worker pod, and rerun the gate before keeping the node admitted
   - use
     [69-autoheal-gpuorangefs-worker.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/69-autoheal-gpuorangefs-worker.sh)
     for safe non-mutating checks on admitted workers; it only escalates to
     `repair` when the node is unhealthy and idle
   - the pool-level periodic runner is
     [70-autoheal-gpuorangefs-pool.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/70-autoheal-gpuorangefs-pool.sh)
     and the live timer installer is
     [71-install-gpuorangefs-autoheal-timer.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/71-install-gpuorangefs-autoheal-timer.sh)
   - `slurm-pilot-gpuorangefs-autoheal.timer` is now installed and active on
     `t560`
   - the pool runner emits node-exporter textfile metrics at
     `/var/lib/node_exporter/textfile/slurm_gpuorangefs_autoheal.prom`
   - Prometheus now alerts separately for:
     - stale timer runs
     - repaired workers
     - deferred repairs due to active jobs
     - hard autoheal failures
4. For ABIDE and similar long-running campaign jobs, `worker_local + fetch`
   remains the safest default persistence mode.
   - On healthy `r770` runs, `PERSIST_MODE=orangefs` is good enough to persist
     the final bundle archive, job log, and run config.
   - Do not assume the extracted `results/` tree will already exist on the
     shared mount; treat the bundle archive as the canonical shared artifact.
   - Use
     [66-gpuorangefs-gate.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/66-gpuorangefs-gate.sh)
     before re-admitting or trusting a repaired worker node.
5. `sbcast` is available again on the current Slurm `25.11.4` lane.
  - the canonical smoke remains
    [65-submit-sbcast-smoke.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/65-submit-sbcast-smoke.sh)
  - the underlying `stepmgr` rendering bug was fixed in the promoted operator
    image
  - ABIDE campaign smoke has passed end-to-end with `PAYLOAD_TRANSFER_MODE=sbcast`
    on the `worker_local + fetch` lane
  - after OrangeFS persistence hardening, `sbcast + orangefs` has now been
    validated on both admitted workers:
    - `job 186` on `r770`
    - `job 183` on `r740`
  - `worker_local + fetch` remains a good fallback when you want the most
    failure-isolated recovery path
  - still prefer `embedded` as the default unless you explicitly want the
    `sbcast` path
6. The external K8s MariaDB backend for `slurmdbd` is not the source of truth yet.
   - The working accounting backend is still the host-local MariaDB on `t560`.
7. The CuPy-based GPU compute proof is not the recommended path right now.
   - Use the PyTorch proof script instead:
   - [64-submit-plruntime-torch-gpucompute.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/64-submit-plruntime-torch-gpucompute.sh)

## Operational helpers

- gpuorangefs node admission gate:
  - [66-gpuorangefs-health-gate.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/66-gpuorangefs-health-gate.sh)
  - validation-only legacy helper; do not use it to mutate node admission
- stepmgr runtime diagnosis:
  - [67-diagnose-stepmgr-runtime.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/67-diagnose-stepmgr-runtime.sh)

## What to avoid

Avoid these unless the task is explicitly infrastructure work:

- changing `slurmdbd` backend settings
- cutting over to K8s MariaDB
- changing OrangeFS client/runtime units
- changing Slurm QoS defaults
- scheduling heavy K8s and Slurm GPU jobs at the same time

## If something breaks

Use this order:

1. `lab_status`
2. `lab_slurm_status`
3. `lab_orangefs_status`
4. inspect the workload artifact path in OrangeFS
5. inspect the exact submit script that was used
6. only then edit infrastructure

## The safe baseline for ongoing dev

If you just want to keep moving:

1. source [ops/lab-ops.sh](/home/devsounio/beagle/k8s/hpc-sota/ops/lab-ops.sh)
2. run `lab_status` and `lab_slurm_status`
3. use the proven submit scripts
4. keep durable outputs in OrangeFS
5. do not touch the `slurmdbd` migration path unless that is the task

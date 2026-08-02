# Slurm Pilot

## Goal

This is the no-BS pilot for adding a classical HPC scheduling plane beside the
current Kubernetes-native AI/HPC path.

The target shape is:

- Kubernetes remains the platform control plane
- OrangeFS remains the shared AI/HPC data plane
- local scratch remains local
- Slurm is added in parallel for classical HPC semantics

## Cluster shape

This pilot is designed for the current lab:

- `t560-proxmox`
  - control-plane
  - OrangeFS client mounted
  - hosts Slurm control-plane pods for the pilot
- `r740-proxmox`
  - GPU node
  - OrangeFS client mounted
  - eligible for Slurm NodeSet
- `r770-proxmox`
  - GPU node
  - OrangeFS client mounted
  - eligible for Slurm NodeSet

## Slurm pilot design

- namespace: `slurm-pilot`
- Slurm controller, accounting, REST API, and login are currently pinned to
  `r770-proxmox`
- Slurm NodeSet pods can target `r740` and `r770`, but only nodes that pass the
  worker gate should carry the `sounio.dev/slurm-worker-gpuorangefs=true` label
- partition: `gpu-orangefs`
- OrangeFS mounted into login and compute pods at:
  - `/orangefs/training`

## Current live status

Installed and validated on `2026-04-05`.

- `cert-manager`: installed
- `slurm-operator`: installed
- `slurm-pilot`: installed
- host `MariaDB` on `t560`: installed and backing `slurmdbd`
- host `MariaDB` hardening: installed
- host `MariaDB` backup timer: installed
- `slurmdbd`: healthy
- `slurmctld`: healthy
- `slurmrestd`: healthy
- `login`: healthy
- `gpu-orangefs` workers:
  - `gpuorangefs-r740-proxmox`
  - `gpuorangefs-r770-proxmox`
- `cpu-ops` worker:
  - `cpuops-t560-proxmox`
  - restored after clearing `t560` kubelet `DiskPressure` and replacing
    Docker Hub helper images with Slinky-hosted images already used by the
    lane
  - Sounio compiler bootstrap toolchain is now baked into the durable worker
    image:
    `192.168.3.207:5003/slurmd-sounio-toolchain:25.11-ubuntu24.04-gcc-20260523T090133Z`
  - Slurm compile smoke job `1643` proved `/usr/bin/cc` after recycling the
    worker onto that image
- worker gate status:
  - `r770-proxmox`: admitted
  - `r740-proxmox`: admitted again after the real Cilium `1.19.2` image
    upgrade and a clean pass of the canonical worker gate
  - periodic safe autoheal timer:
    - `slurm-pilot-gpuorangefs-autoheal.timer`
    - installed and active on `t560`
    - first run completed successfully
    - emits textfile metrics into:
      - `/var/lib/node_exporter/textfile/slurm_gpuorangefs_autoheal.prom`
    - alerting now distinguishes:
      - stale timer
      - repaired workers
      - deferred repairs
      - hard autoheal failures
  - ABIDE runner metrics timer:
    - `darwin-t560-sounio-abide-runner-metrics.timer`
    - installed and active on `t560`
    - emits textfile metrics into:
      - `/var/lib/node_exporter/textfile/sounio_abide_runner.prom`
    - tracks the latest observed ABIDE campaign submit:
      - submit age
      - payload transfer mode (`embedded` vs `sbcast`)
      - persist mode (`orangefs` vs `worker_local`)
- partitions:
  - `gpu-orangefs`
  - `cpu-ops`
- accounts:
  - `lab`
  - `pbpk`
  - `omics`
  - `plruntime`
- QoS:
  - `normal`
  - `burst`
  - `long`
  - `cpuops`
  - `gpuorangefs`
- OrangeFS smoke job:
  - submitted through `sbatch`
  - completed successfully
  - wrote `/orangefs/training/slurm-pilot/slurm-orangefs-smoke-1.txt`
- PBPK CPU batch job:
  - submitted through `sbatch`
  - job `2` completed successfully
  - wrote `/orangefs/training/slurm-pilot/pbpk/pbpk-cpuops-summary.json`
- Omics CPU batch job:
  - submitted through `sbatch`
  - job `4` completed successfully
  - wrote `/orangefs/training/slurm-pilot/omics/omics-expression-summary.csv`
  - wrote `/orangefs/training/slurm-pilot/omics/omics-preprocess-summary.json`
- PL runtime GPU batch job:
  - submitted through `sbatch`
  - job `7` completed successfully
  - account `plruntime`, partition `gpu-orangefs`, QoS `gpuorangefs`
  - wrote `/orangefs/training/slurm-pilot/plruntime/pl-runtime-metrics.json`
  - wrote `/orangefs/training/slurm-pilot/plruntime/pl-runtime-run.txt`
- PL runtime GPU stress batch job:
  - submitted through `sbatch`
  - job `16` completed successfully
  - account `plruntime`, partition `gpu-orangefs`, QoS `burst`
  - wrote `/orangefs/training/slurm-pilot/plruntime-stress/pl-runtime-stress-metrics.json`
  - wrote `/orangefs/training/slurm-pilot/plruntime-stress/pl-runtime-stress.txt`
- PL runtime real PyTorch CUDA batch job:
  - submitted through `sbatch`
  - job `25` completed successfully
  - account `plruntime`, partition `gpu-orangefs`, QoS `burst`
  - used official PyTorch `2.6.0+cu124` wheels
  - proved CUDA compute on `NVIDIA L4`
  - wrote `/orangefs/training/slurm-pilot/plruntime-torch/pl-runtime-torch-metrics.json`
  - wrote `/orangefs/training/slurm-pilot/plruntime-torch/pl-runtime-torch-run.txt`
- QoS execution proof:
  - blocker `17` completed
  - normal `18` completed
  - burst `19` completed
  - `burst` started before `normal` under contention on the same GPU node
  - wrote `/orangefs/training/slurm-pilot/qos-proof/17-blocker.json`
  - wrote `/orangefs/training/slurm-pilot/qos-proof/18-normal.json`
  - wrote `/orangefs/training/slurm-pilot/qos-proof/19-burst.json`
- `slurmdbd` migration snapshot:
  - logical snapshot created under `/var/backups/slurm-pilot-mariadb/snapshots/20260405-113416/`
- K8s MariaDB migration path:
  - externalized candidate remains `slurm-pilot-mariadb-ext`
  - the candidate service still owns the stable ClusterIP:
    - `10.96.196.141`
  - current live accounting backend has been rolled back to the host-local
    MariaDB on `10.100.100.2`
  - current reason:
    - the live lane is already healthy on `10.100.100.2`
    - the externalized candidate is not the source of truth today
  - prepared stopgap candidate:
    - `cockpit` VM on `10.100.100.166`
    - MariaDB is installed and listening on `10.100.100.166:3306`
    - the VM now has a persistent route back to pod CIDR `10.0.0.0/16`
      via `10.100.100.2`
    - Helm overlay for planned cutover:
      - [`values/slurm-pilot-values.cockpit-vm-db.yaml`](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/values/slurm-pilot-values.cockpit-vm-db.yaml)
  - stable alias reserved for the next preflight round:
    - `slurmdbd-mariadb-ext.darwin.lan`
  - `.svc.cluster.local` is visible from pods but is not the right final endpoint for host-side preflight on `t560`
  - historical note:
    - the candidate previously passed preflight and apparmor hardening work
    - it is still kept as a resumable path, not the active backend
  - the host-local MariaDB on `t560` remains the rollback target and backup source

The pilot is now live as a parallel HPC scheduling plane beside the existing
Kubernetes-native `JobSet + Kueue + OrangeFS` path.

## GPU lane gate

When re-validating a `gpuorangefs` node after networking or scheduler changes,
use:

```bash
slurm-pilot/scripts/66-gpuorangefs-gate.sh
```

The gate performs Cilium cluster checks, an ordinary pod netcheck pinned to a
specific K8s node, and a tiny Slurm smoke pinned to the matching Slurm node.
Override `K8S_NODE_NAME` and `SLURM_NODE_NAME` when gating a node pair other
than the defaults. Treat it as the recommended admission test before leaving a
node in the `sounio.dev/slurm-worker-gpuorangefs=true` pool.

The gate tolerates short Cilium restart windows and waits briefly for
`cilium-health` to converge before failing the node. It also waits for the
matching Slurm node to register before submitting the smoke job, which avoids a
false negative during fresh worker admission.

The canonical admission helper is:

```bash
slurm-pilot/scripts/68-manage-gpuorangefs-worker.sh <node> status
slurm-pilot/scripts/68-manage-gpuorangefs-worker.sh <node> quarantine
slurm-pilot/scripts/68-manage-gpuorangefs-worker.sh <node> admit
slurm-pilot/scripts/68-manage-gpuorangefs-worker.sh <node> repair
```

`admit` now serializes per node with a local lock and stamps an admission ID on
the node so an older failed run cannot remove a newer successful admission.
`repair` is the canonical self-heal path when a previously admitted worker
regresses into `NOT_RESPONDING` or loses pod-level reachability; it recycles
the node-local `cilium` pod, recreates the Slurm worker pod, and reruns the
gate before keeping the node admitted.
Use this helper as the only mutating path for the `gpuorangefs` pool.

For non-mutating health checks that can safely run while a node is admitted,
use:

```bash
slurm-pilot/scripts/69-autoheal-gpuorangefs-worker.sh <node>
```

It exits cleanly when the node is healthy, and only invokes `repair` when the
worker is unhealthy and the Slurm node is idle. Use `FORCE_REPAIR=1` only when
you intentionally accept interrupting active work on that node.

## Important operational rule

This pilot is meant to run **beside** Kubernetes batch, not in denial of it.

Use it honestly:

- do **not** schedule K8s GPU training and Slurm GPU jobs on the same nodes at
  the same time unless you intentionally accept contention
- for first validation, reserve a maintenance window or dedicate the pilot
  nodes during the smoke test

## What is here

- [values/slurm-operator-values.yaml](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/values/slurm-operator-values.yaml)
- [values/mariadb-values.yaml](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/values/mariadb-values.yaml)
- [values/slurm-pilot-values.yaml](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/values/slurm-pilot-values.yaml)
- [k8s/mariadb.yaml](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/k8s/mariadb.yaml)
- [scripts/00-prereq-check.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/00-prereq-check.sh)
- [scripts/10-install-cert-manager.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/10-install-cert-manager.sh)
- [scripts/15-install-mariadb.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/15-install-mariadb.sh)
- [scripts/16-install-mariadb-manifest.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/16-install-mariadb-manifest.sh)
- [scripts/17-install-host-mariadb.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/17-install-host-mariadb.sh)
- [mysql/61-slurm-pilot-hardening.cnf](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/mysql/61-slurm-pilot-hardening.cnf)
- [scripts/18-install-host-mariadb-hardening.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/18-install-host-mariadb-hardening.sh)
- [scripts/20-install-slurm-operator.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/20-install-slurm-operator.sh)
- [scripts/21-build-slurm-operator-stepmgr-image.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/21-build-slurm-operator-stepmgr-image.sh)
- [scripts/30-install-slurm-pilot.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/30-install-slurm-pilot.sh)
- [scripts/31-reconcile-slurm-pilot-scheduling.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/31-reconcile-slurm-pilot-scheduling.sh)
- [scripts/40-validate-slurm-pilot.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/40-validate-slurm-pilot.sh)
- [scripts/50-submit-orangefs-smoke.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/50-submit-orangefs-smoke.sh)
- [scripts/55-submit-pbpk-cpuops.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/55-submit-pbpk-cpuops.sh)
- [scripts/56-configure-accounts-qos.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/56-configure-accounts-qos.sh)
- [scripts/57-submit-omics-cpuops.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/57-submit-omics-cpuops.sh)
- [scripts/58-submit-plruntime-gpuorangefs.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/58-submit-plruntime-gpuorangefs.sh)
- [scripts/59-prove-burst-priority.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/59-prove-burst-priority.sh)
- [scripts/60-submit-long-cpuops.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/60-submit-long-cpuops.sh)
- [scripts/61-submit-plruntime-gpu-stress.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/61-submit-plruntime-gpu-stress.sh)
- [scripts/62-submit-plruntime-cupy-gpucompute.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/62-submit-plruntime-cupy-gpucompute.sh)
- [scripts/63-run-qos-validation.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/63-run-qos-validation.sh)
- [scripts/64-submit-plruntime-torch-gpucompute.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/64-submit-plruntime-torch-gpucompute.sh)
- [scripts/66-gpuorangefs-gate.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/66-gpuorangefs-gate.sh)
- [scripts/69-autoheal-gpuorangefs-worker.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/69-autoheal-gpuorangefs-worker.sh)
- [scripts/70-autoheal-gpuorangefs-pool.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/70-autoheal-gpuorangefs-pool.sh)
- [scripts/71-install-gpuorangefs-autoheal-timer.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/71-install-gpuorangefs-autoheal-timer.sh)
- [images/slurmd-sounio-toolchain/Dockerfile](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/images/slurmd-sounio-toolchain/Dockerfile)
- [scripts/72-build-slurmd-sounio-toolchain-image.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/72-build-slurmd-sounio-toolchain-image.sh)
- [patches/slurm-operator-v1.1.0-rc1-stepmgr-toggle.patch](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/patches/slurm-operator-v1.1.0-rc1-stepmgr-toggle.patch)
- [patches/slurm-operator-v1.1.0-rc1-strategic-merge-workloads.patch](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/patches/slurm-operator-v1.1.0-rc1-strategic-merge-workloads.patch)
- [patches/slurm-operator-v1.1.0-rc1-controller-default-initcontainers.patch](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/patches/slurm-operator-v1.1.0-rc1-controller-default-initcontainers.patch)
- [scripts/23-redeploy-k8s-mariadb.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/23-redeploy-k8s-mariadb.sh)
- [scripts/24-install-k8s-mariadb-ext.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/24-install-k8s-mariadb-ext.sh)
- [scripts/19-export-slurmdbd-snapshot.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/19-export-slurmdbd-snapshot.sh)
- [scripts/25-preflight-external-slurmdbd-db.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/25-preflight-external-slurmdbd-db.sh)
- [scripts/26-preflight-cockpit-vm-db.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/26-preflight-cockpit-vm-db.sh)
- [values/slurm-pilot-values.external-db.example.yaml](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/values/slurm-pilot-values.external-db.example.yaml)
- [scripts/backup-host-mariadb.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/backup-host-mariadb.sh)
- [systemd/slurm-pilot-mariadb-backup.service](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/systemd/slurm-pilot-mariadb-backup.service)
- [systemd/slurm-pilot-mariadb-backup.timer](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/systemd/slurm-pilot-mariadb-backup.timer)
- [systemd/slurm-pilot-gpuorangefs-autoheal.service](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/systemd/slurm-pilot-gpuorangefs-autoheal.service)
- [systemd/slurm-pilot-gpuorangefs-autoheal.timer](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/systemd/slurm-pilot-gpuorangefs-autoheal.timer)
- [SLURMDBD_EVOLUTION.md](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/SLURMDBD_EVOLUTION.md)
- [SLURMDBD_MIGRATION_BLUEPRINT.md](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/SLURMDBD_MIGRATION_BLUEPRINT.md)

## Install order

1. Run the prereq check
2. Install `cert-manager`
3. Install MariaDB for `slurmdbd`
4. Install the `slurm-operator`
5. Install the Slurm pilot cluster
6. Validate the cluster
7. Submit the OrangeFS smoke job
8. Submit a real `sbatch` workload

If you want the patched operator path that turns global `stepmgr` into an
explicit rollout choice, use:

1. build and push the patched image:
   - [scripts/21-build-slurm-operator-stepmgr-image.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/21-build-slurm-operator-stepmgr-image.sh)
2. install the operator with:
   - `ENABLE_STEPMGR=false`
   - `SLURM_OPERATOR_IMAGE_REPOSITORY=...`
   - `SLURM_OPERATOR_IMAGE_TAG=...`
   - [scripts/20-install-slurm-operator.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/20-install-slurm-operator.sh)

The installer now applies every local
`slurm-operator-*.patch` from
[patches/](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/patches) before the
Helm install so the source-of-truth patch set stays reproducible.

## Expected outcome

If the pilot is healthy, we should end up with:

- a live Slurm login pod on `t560`
- Slurm compute pods on `r740` and `r770`
- a CPU-only Slurm worker on `t560`
- `scontrol ping` healthy
- `sinfo` showing the `gpu-orangefs` and `cpu-ops` partitions
- `sacctmgr` and `sacct` working through `slurmdbd`

## Taint drift note

If new pods start hanging in `Pending` and the scheduler reports a failed call to:

- `podsbinding-v1.kb.io`

check the `slurm-operator` and `slurm-operator-webhook` deployments first.

In this lab, the practical failure mode was:

- `t560-proxmox` carried:
  - `node-role.kubernetes.io/control-plane:NoSchedule`
  - `node.kubernetes.io/disk-pressure:NoSchedule`
- workers carried:
  - `sounio.dev/pool=gpu-batch:NoSchedule`
  - `sounio.dev/compute=heavy:NoSchedule`

With only the old `control-plane` toleration, the operator and webhook had no
place left to land, the webhook service lost all endpoints, and unrelated new
pods stopped scheduling.

The values file now keeps the operator and webhook schedulable on the validated
worker pair as well:

- [values/slurm-operator-values.yaml](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/values/slurm-operator-values.yaml)
- accounts and QoS working for the domain tracks:
  - `pbpk -> cpuops`
  - `omics -> cpuops`
  - `plruntime -> gpuorangefs`
- `PriorityWeightQOS = 10000` and `PriorityWeightAge = 100` active in
  `slurmctld`
- operational QoS tiers now exist:
  - `burst` for short high-priority GPU runs
  - `normal` as the default baseline
  - `long` for longer CPU-oriented batch work
- QoS behavior is now proved in execution:
  - `burst` starts ahead of `normal` when both contend for the same GPU after a blocker releases
- an `sbatch` smoke job writing into OrangeFS under:
  - `/orangefs/training/slurm-pilot/`
- a real PBPK-style batch workload writing into OrangeFS under:
  - `/orangefs/training/slurm-pilot/pbpk/`
- a real omics-style batch workload writing into OrangeFS under:
  - `/orangefs/training/slurm-pilot/omics/`
- a real PL-runtime-style GPU batch workload writing into OrangeFS under:
  - `/orangefs/training/slurm-pilot/plruntime/`
- a heavier PL-runtime GPU stress workload writing into OrangeFS under:
  - `/orangefs/training/slurm-pilot/plruntime-stress/`
- a real PyTorch CUDA PL-runtime workload writing into OrangeFS under:
  - `/orangefs/training/slurm-pilot/plruntime-torch/`

That outcome has now been achieved.

## Important implementation note

The worker `NodeSet` needed one hardening change to become reliable across both
GPU nodes:

- explicit Kubernetes DNS search domains for the worker pods

Without that, `slurmd` on `r740` intermittently failed to resolve the
controller service name used by configless startup.

Also:

- the default sample `nodesets.slinky` worker was disabled

That keeps the pilot clean and focused on the real GPU-backed partition instead
of leaving an unrelated sample worker pending.

## Important implementation note

`slurmdbd` is live and is currently backed by the host-local MariaDB on
`t560` at `10.100.100.2`.

That host-backed default is intentional right now:

- it removed unnecessary churn around container-local UNIX socket behavior
- it restored a healthy accounting plane quickly
- it keeps the control-plane accounting path simple while the pilot is young

External database targets now exist as explicit overlays instead of implicit
defaults:

- K8s MariaDB / alias example:
  - [`values/slurm-pilot-values.external-db.example.yaml`](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/values/slurm-pilot-values.external-db.example.yaml)
- prepared stopgap VM on the `10.x` fabric:
  - [`values/slurm-pilot-values.cockpit-vm-db.yaml`](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/values/slurm-pilot-values.cockpit-vm-db.yaml)

The shared data plane for jobs is still OrangeFS. The MariaDB backend is only
for Slurm accounting state.

It is now also minimally hardened for pilot operations:

- UTF-8 defaults enabled
- `skip_name_resolve = ON`
- `innodb_buffer_pool_size = 512M`
- `innodb_flush_method = O_DIRECT`
- daily backup timer at `03:30`
- rotating dumps under `/var/backups/slurm-pilot-mariadb/`

## Honest GPU caveat

The `plruntime` Slurm job now proves:

- GPU partition allocation
- `CUDA_VISIBLE_DEVICES`
- `/dev/nvidia*` device visibility inside the batch job
- `libcuda.so.1` and `nvidia-smi` visible from the native loader path inside the
  batch job
- `libnvidia-ptxjitcompiler.so.1` visible for CUDA PTX JIT loading inside the
  batch job
- artifact persistence into OrangeFS

The current `slurmd` image still does not bundle the NVIDIA userland natively.
Instead, the pilot now mounts the needed host userland into the standard system
paths inside the worker and keeps `/host-nvidia` as a compatibility path for
older submitters. The worker refreshes `ld.so.cache` on startup so native jobs
can discover both `libcuda.so.1` and `libnvidia-ptxjitcompiler.so.1` without
custom loader exports.

## `slurmdbd` resilience note

The pilot now also has a concrete migration helper for the accounting backend:

- [scripts/19-export-slurmdbd-snapshot.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/19-export-slurmdbd-snapshot.sh)

That script generates:

- a logical SQL dump
- per-table row counts
- metadata and checksum files

Use it before changing the live backend again or before moving from the
externalized K8s backend to a dedicated external database endpoint.

## References

- SchedMD Slurm on Kubernetes:
  - https://slurm.schedmd.com/kubernetes.html
- Slinky:
  - https://slinky.schedmd.com/

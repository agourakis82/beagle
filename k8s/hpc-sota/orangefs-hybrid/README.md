# OrangeFS Hybrid Moonshot

This is the current-OS-friendly open-source AI/HPC storage pivot for the
cluster:

- `OrangeFS` as the high-performance shared filesystem for the heavy data plane
- `zfast` / ZFS / simple NFS as user and platform storage
- local NVMe on GPU nodes as the hot tier
- `Kueue` as the admission and coexistence layer for mixed workloads

## Why OrangeFS

OrangeFS is documented by the Linux kernel as:

- an LGPL userspace scale-out parallel storage system
- ideal for HPC, genomics, and bioinformatics
- distributing file data among multiple file servers
- supporting simultaneous access by multiple clients
- storing file data and metadata on servers using local filesystems
- easy to install and maintain because the implementation is user-space heavy

The OrangeFS project documentation also states:

- the server and client are user-level code
- the upstream Linux kernel module is the preferred method of kernel integration
- performance improved significantly as of Linux `5.13` with full integration
  with the Linux page cache

That makes OrangeFS a very compelling path for this cluster because the current
nodes are already on a modern Linux base and we want an AI/HPC filesystem
without immediately reimaging everything.

## 2026 hybrid split

### OrangeFS

Use OrangeFS for:

- `/orangefs/datasets`
- `/orangefs/checkpoints`
- shared AI/HPC data paths

Keep transient pod-local scratch off the shared filesystem unless a workload
specifically needs shared scratch semantics.

### User / platform storage

Keep user and platform data on:

- `zfast`
- host-local storage
- simple NFS if needed

This includes:

- live workspaces
- service configs
- observability state
- anything that should stay simple and boring

### Local NVMe

Use local NVMe per GPU node for:

- shard cache
- model cache
- checkpoint spill
- runtime cache
- fast temporary data near the GPU

## Why this fits the mission

This cluster wants to become a small research supercomputing platform for:

- SounioLang and epistemic computation
- hypercomplex algebra workloads
- omics foundation model work
- PBPK and systems-biology jobs
- fMRI and multimodal scientific pipelines

That mission wants:

- a real shared HPC filesystem
- good fit for genomics and bioinformatics
- a path that does not require an immediate OS pivot

OrangeFS checks those boxes unusually well.

## Execution files

- [role map](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/ROLE_MAP.md)
- [support notes](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/SUPPORT_NOTES.md)
- [migration plan](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/MIGRATION_PLAN.md)
- [first rollout plan](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/FIRST_ROLLOUT_PLAN.md)
- [package strategy](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/PACKAGE_STRATEGY.md)
- [configure notes](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/CONFIGURE_NOTES.md)
- [benchmark ritual](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/BENCHMARK_RITUAL.md)
- [lightweight benchmark results](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/LIGHTWEIGHT_BENCHMARK_RESULTS.md)
- [K8s canary results](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/K8S_CANARY_RESULTS.md)
- [K8s canary results on r770](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/K8S_R770_CANARY_RESULTS.md)
- [K8s benchmark attempt notes](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/K8S_BENCHMARK_ATTEMPT_NOTES.md)
- [K8s benchmark results](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/K8S_BENCHMARK_RESULTS.md)
- [multi-node K8s benchmark results](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/MULTINODE_K8S_BENCHMARK_RESULTS.md)
- [checkpoint repro notes](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/CHECKPOINT_REPRO_NOTES.md)
- [proven workflow results](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/PROVEN_WORKFLOW_RESULTS.md)
- [proven workflow results at 512 MiB](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/PROVEN_WORKFLOW_512_RESULTS.md)
- [CephFS comparison prep](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/CEPHFS_COMPARISON_PREP.md)
- [OrangeFS adoption path](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/ORANGEFS_ADOPTION.md)
- [OrangeFS training canary status](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/TRAINING_CANARY_STATUS.md)
- [OrangeFS real workload path](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/REAL_WORKLOAD_PATH.md)
- [systemd deployment results](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/SYSTEMD_DEPLOYMENT_RESULTS.md)
- [current OS proof](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/CURRENT_OS_PROOF.md)
- [two-node proof plan](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/TWO_NODE_PROOF_PLAN.md)
- [GPU client proof](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/GPU_CLIENT_PROOF.md)
- [K8s consumption plan](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/K8S_CONSUMPTION_PLAN.md)
- [current OS client proof script](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/prove-current-os-client.sh)
- [single-node end-to-end proof](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/prove-t560-client-mount.sh)
- [two-node end-to-end proof](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/prove-t560-5860-two-node.sh)
- [two-node workstation launcher](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/launch-t560-5860-two-node-from-workstation.sh)
- [two-node config example](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/two-node-fs.conf.example)
- [persistent two-node island launcher](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/run-t560-5860-two-node-island.sh)
- [GPU client canary](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/prove-orangefs-client-canary.sh)
- [K8s canary runner](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/run-k8s-r740-canary.sh)
- [K8s canary runner for r770](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/run-k8s-r770-canary.sh)
- [K8s benchmark runner](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/run-k8s-r740-benchmark.sh)
- [multi-node K8s benchmark runner](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/run-k8s-multinode-orangefs-benchmark.sh)
- [dataset repro runner](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/run-k8s-orangefs-dataset-repro.sh)
- [OrangeFS proven workflow runner](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/run-k8s-orangefs-proven-workflow.sh)
- [OrangeFS proven workflow canary runner](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/run-k8s-orangefs-proven-workflow-canary.sh)
- [OrangeFS training canary runner](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/run-k8s-orangefs-training-canary.sh)
- [OrangeFS training canary JobSet](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/k8s/jobset-ddp-training-canary-orangefs.yaml)
- [CephFS shared PVC example](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/k8s/pvc-cephfs-shared-compare.example.yaml)
- [CephFS workflow template example](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/k8s/pod-cephfs-proven-workflow-template.example.yaml)
- [systemd installer](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/install-systemd-runtime.sh)
- [source build plan](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/SOURCE_BUILD_PLAN.md)
- [single-node proof plan](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/SINGLE_NODE_PROOF_PLAN.md)
- [build preflight script](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/preflight-orangefs-build.sh)
- [bootstrap t560 source build](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/bootstrap-t560-source-build.sh)
- [prepare t560 single-node proof](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/prepare-t560-single-node-proof.sh)

## Current proof line

OrangeFS is no longer just a paper architecture here.

We have already proven:

- single-node server build and mount on `t560`
- second-node server build on `5860`
- shared two-node namespace mounted from `t560`
- successful canary I/O through the shared namespace
- direct client mounts from `r740` and `r770`
- first lightweight benchmark numbers against local storage
- first Kubernetes hostPath canary on `r740` writing checkpoints into OrangeFS
- first Kubernetes hostPath canary on `r770` writing checkpoints into OrangeFS
- first OrangeFS vs Ceph K8s benchmark scaffold in place
- first OrangeFS vs Ceph K8s benchmark results recorded
- second benchmark profile recorded for streaming-heavy workload shape
- first live `systemd` deployment for server and client runtime services
- first live OrangeFS tuning round applied and benchmarked
- first multi-node shared-data benchmark across `r740 + r770`
- first checkpoint repro isolated beyond the original benchmark
- second targeted tuning round applied with `DefaultNumDFiles 1`
- checkpoint repro fixed in both single-node and concurrent forms after Round 2
- dataset publication/fan-out path split into its own repro so OrangeFS can be
  judged by proven pieces instead of the older monolithic benchmark
- first clean end-to-end OrangeFS proven workflow completed under one `RUN_ID`
  with:
  - dataset publish
  - cross-node fan-out reads
  - concurrent checkpoint write/readback
  - host-side file evidence
- the same proven workflow also completed cleanly at `512 MiB` dataset and
  `512 MiB` checkpoints per node
- the OrangeFS-backed DDP training canary now completes under the current
  baseline:
  - `torchrun`
  - `gloo`
  - OrangeFS for datasets and checkpoints
  - local pod `emptyDir` scratch
- the training canary launcher now uses a fixed topology:
  - `leader` on `r770`
  - `worker` on `r740`
- the training canary timer is now installed on `t560`
- `t560` now also has the OrangeFS client runtime mounted for operational
  visibility
- the first simple real workload (`orangefs-artifact-probe`) has completed on
  the promoted OrangeFS baseline and now reports `cuda=true`
- the next promoted single-node workload is now defined and has completed:
  - [orangefs-cuda-pilot](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/k8s/job-orangefs-cuda-pilot.yaml)
- the `orangefs-cuda-pilot.timer` is now installed on `t560`

## Current highest-value blocker

The next thing to decide is no longer basic OrangeFS viability or first
distributed-train adoption. Those are already real.

The current highest-value question is now operational polish:

- let the installed training-canary timer produce a clean scheduled run
- watch whether the residual late elastic/TCPStore shutdown warnings remain
  harmless across repeated runs
- then pick the next real AI/HPC workload to migrate onto the OrangeFS
  baseline

For future benchmarking, the comparison should use the proven workflow shape:

- `torchrun`
- OrangeFS for datasets/checkpoints
- local scratch

and it should avoid leaning only on the older monolithic Orange-vs-Ceph run.

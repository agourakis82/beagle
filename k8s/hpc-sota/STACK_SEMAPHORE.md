# Beagle HPC Stack Semaphore

This is the shortest honest status board for the live stack.

Use it together with:

1. [AGENT_BOOTSTRAP.md](/home/devsounio/beagle/k8s/hpc-sota/AGENT_BOOTSTRAP.md)
2. [DEV_WORKFLOW.md](/home/devsounio/beagle/k8s/hpc-sota/DEV_WORKFLOW.md)
3. `/home/devsounio/bootstrap-dev-plane.sh`
4. [PROJECT_ONBOARDING_BLUEPRINT.md](/home/devsounio/beagle/k8s/hpc-sota/PROJECT_ONBOARDING_BLUEPRINT.md)

Refresh commands:

```bash
cd /home/devsounio
./bootstrap-dev-plane.sh

cd /home/devsounio/beagle/k8s/hpc-sota
./ops/darwin-control-plane-status.sh
./ops/hpc-bootstrap.sh
./ops/hpc-route-doctor.sh
./ops/hpc-surface-doctor.sh
./ops/slurmdbd-backend-doctor.sh
./ops/workspace-platform-doctor.sh
```

Fast agent entrypoint:

```bash
darwin-status
darwin-status --json
darwin-status --deep
```

Slurm truth for Darwin supercomputing is the `slurm-pilot` login lane. The
legacy host-local Slurm services on `t560-proxmox` are intentionally stopped
and masked so bare host commands cannot masquerade as the live scheduler. Use
`darwin-status` or the Slurm login pod when deciding GPU lane health.

## Green

These areas are currently operational and have recent proof:

- Kubernetes control plane is healthy and all nodes are `Ready`
- `k8s-api.darwin.lan:6443` is the worker-safe API endpoint
- `t560` Tailscale route doctor is healthy
- Sounio remote-first workspace is healthy:
  - stable service `sounio-workspace`
  - currently backed by `sounio-workspace-control` on `t560-proxmox`
  - browser + SSH + Zellij flow
  - no GPU request; GPUs stay in Slurm/Foundry lanes
- Grafana and Prometheus observability stack pass the current verifier
- Slurm core scheduling is operational
- Slurm QoS proof (`burst > normal`) is operational
- `5860-proxmox` is admitted into `gpu-orangefs` again:
  - Slurm node: `gpuorangefs-5860-proxmox`
  - latest admission smoke: job `1621` completed
- Proven workload lanes are green:
  - `pbpk`
  - `omics`
  - `pl-runtime`
  - `sounio-compiler-foundry` dry-run/snapshot path
- OrangeFS training canary is green again after live reconciliation:
  - current known-good run id: `1775437389`
  - launcher mode: `torchrun`
  - backend: `gloo`
  - both ranks completed `step=0..4`
  - both ranks wrote:
    - dataset artifacts
    - checkpoint artifacts
    - local scratch artifacts
- `darwin-hpc-gateway` is healthy again:
  - currently pinned to `t560-proxmox`
  - recovered via control-plane toleration + nodeSelector
  - `/healthz` returns `200` through the legacy catalog bridge
  - `darwin-slurm-control-adapter` mode is `legacy-catalog-only`
  - host `slurmctld`/`slurmrestd` are intentionally inactive/masked
  - active scheduler lane is `slurm-pilot` in Kubernetes/Slinky

## Yellow

These areas are usable but still deserve caution:

- OrangeFS is not yet "boring" under churn:
  - there are still historical repros with `Errno 5` and `FileNotFoundError`
- Slurm accounting now points at the externalized K8s MariaDB candidate:
  - `StorageHost=slurmdbd-mariadb-ext.darwin.lan`
  - `slurm-pilot-mariadb-ext-0` is `1/1 Running`
  - latest external-backend preflight finished green
  - smoke job `29` completed after cutover
- the current accounting guard-rail is backup/restore, not failover:
  - host-local `mariadb` on `t560` remains the rollback target
  - enabled `slurm-pilot-mariadb-backup.timer`
  - logical dumps under `/var/backups/slurm-pilot-mariadb/`
  - migration-grade snapshots under `/var/backups/slurm-pilot-mariadb/snapshots/`
  - successful `sacctmgr` and `sacct` reads from the Slurm login pod
- GPU worker/CNI behavior still shows periodic noise and restarts
- Kueue `Workload Finished=True` is not enough by itself for success claims:
  - agents must check `JobSet`, child jobs, and pod terminal states too
- OrangeFS training canary required live reconciliation on `2026-04-05`:
  - root cause 1: image missing on `r770` while manifest used `imagePullPolicy: Never`
  - root cause 2: launcher drifted back to headless-service rendezvous instead of the deterministic coordinator pod hostname

## Red

No global stack-red blockers are active at the moment of this snapshot.

If any of the following happen, treat the stack as red until explained:

- worker nodes stop being `Ready`
- `./ops/hpc-route-doctor.sh` goes unhealthy
- `./ops/hpc-surface-doctor.sh` starts failing on API/Grafana/Sounio shared surfaces
- Sounio workspace or Grafana tailnet surfaces stop answering
- OrangeFS canary regresses from `Completed` to launcher/runtime failure

## Runbook

### If the stack feels green

Proceed with the smallest proven workload first.
If the task is onboarding a new project, use
[PROJECT_ONBOARDING_BLUEPRINT.md](/home/devsounio/beagle/k8s/hpc-sota/PROJECT_ONBOARDING_BLUEPRINT.md)
before creating a new workspace, lane, or queue contract.

### If the stack feels yellow

1. Run:
   - `./ops/hpc-bootstrap.sh`
   - `./ops/hpc-route-doctor.sh`
   - `./ops/hpc-surface-doctor.sh`
   - `./ops/slurmdbd-backend-doctor.sh`
   - `./ops/workspace-platform-doctor.sh`
2. Verify the exact lane:
   - Slurm or Kubernetes
3. Re-run the smallest relevant canary
4. Keep evidence before editing infra

### If the stack feels red

1. Stop changing manifests casually
2. Reconfirm API, nodes, route doctor, and tailnet surfaces
3. Triage the broken lane in isolation
4. Update the nearest README/handoff before handing off work

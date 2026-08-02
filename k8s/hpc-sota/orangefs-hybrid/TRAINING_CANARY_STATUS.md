# OrangeFS Training Canary Status

## Summary

The OrangeFS-backed DDP training canary is now operational with the current
baseline:

- `torchrun`
- `gloo`
- OrangeFS for durable paths:
  - `/datasets`
  - `/checkpoints`
- local pod scratch via `emptyDir`

Latest live reconciliation:

- current known-good run id:
  - `1775437389`
- both ranks completed successfully on:
  - `r770-proxmox`
  - `r740-proxmox`
- both ranks logged:
  - `phase=init_process_group_done`
  - `step=0..4`
  - `phase=dataset_write_done`
  - `phase=checkpoint_write_done`
  - `phase=scratch_write_done`
  - `phase=destroy_process_group`

What is already working:

- `JobSet` launches correctly with workers split across `r740` and `r770`
- the two ranks complete the 5-step reduction loop
- dataset artifacts are written on both ranks
- checkpoint artifacts are written on both ranks
- scratch artifacts are written locally on both ranks
- the `JobSet` reaches `Completed`

Recent hardening added to the canary path:

- phase toggles via env:
  - `WRITE_DATASET`
  - `WRITE_CHECKPOINT`
  - `WRITE_SCRATCH`
- serialized artifact writes via `SERIALIZE_ARTIFACT_WRITES`
- chunked scratch writes
- early-phase logging plus `faulthandler` stack dumps
- `run-k8s-orangefs-training-canary.sh` now force-cleans stale pods before
  relaunching the `JobSet`
- rank 0 now resolves the `net1` address locally from the container interface
  instead of falling back to the Kubernetes API when the network-status env is
  missing

## Current known-good evidence

The latest full run used:

- `LAUNCHER_MODE=torchrun`
- `FORCE_BACKEND=gloo`
- `WRITE_DATASET=1`
- `WRITE_CHECKPOINT=1`
- `WRITE_SCRATCH=1`
- scratch mounted locally with `emptyDir`

The current promoted topology is:

- `leader` pinned to `r770-proxmox`
- `worker` pinned to `r740-proxmox`
- `NODE_RANK` sourced from `job-global-index`

The run completed successfully for:

- `orangefs-train-workers-0-0-tqlks`
- `orangefs-train-workers-1-0-n2wh9`

Both ranks logged:

- `phase=init_process_group_done`
- `step=0..4`
- `phase=post_training_barrier_done`
- `phase=dataset_write_done`
- `phase=checkpoint_write_done`
- `phase=scratch_write_done`
- `phase=destroy_process_group`

Representative paths from the successful full run:

- `/datasets/rank-0/dataset.json`
- `/datasets/rank-1/dataset.json`
- `/checkpoints/rank-0/checkpoint.pt`
- `/checkpoints/rank-1/checkpoint.pt`

The run ID was:

- `fullprobe1775386457`
- `1775387817`

## Automation status

The training-canary timer is now installed on `t560`:

- `orangefs-training-canary.timer`

The service baseline was also launched manually after promotion.

The live drift found on `2026-04-05` was narrower than the docs previously
claimed:

- the launcher path in `orangefs-hybrid` had drifted back to the headless
  service rendezvous hostname:
  - `orangefs-train-rdzv.beagle.svc.cluster.local`
- meanwhile the documented green baseline depended on the deterministic
  coordinator pod hostname:
  - `orangefs-train-leader-0-0.orangefs-train.beagle.svc.cluster.local`
- the same live drift also exposed an operational image issue on `r770`:
  - `sounio/pytorch-rdma:2.7.1-cuda12.8-rdma` was missing there while the
    manifest still used `imagePullPolicy: Never`

Live reconciliation applied:

- restored the image on `r770`
- corrected the launcher wrapper to resolve from the coordinator hostname
  carried by:
  - `metadata.annotations['jobset.sigs.k8s.io/coordinator']`

Current interpretation:

- the promoted OrangeFS training baseline remains valid
- the live launcher path is now re-aligned with that baseline
- the canary is green again with the current known-good run `1775437389`

## Previous blockers

Two important blockers are now fixed:

- rank 0 on `r740` could previously hang during coordinator discovery because
  it fell through to Kubernetes API lookup before the rendezvous even started
- after adding local interface-IP discovery for `net1`, both ranks now reach
  `phase=init_process_group_start`
- a stable headless rendezvous service now exists:
  - `orangefs-train-rdzv`
- with `FORCE_BACKEND=gloo` and `INIT_METHOD_MODE=env`, the no-artifact DDP
  canary completes cleanly on both nodes using the service-backed rendezvous

## Residual note

The latest successful full run still emitted late shutdown warnings from the
elastic rendezvous/TCPStore layer on rank 1 after both ranks had already:

- completed training
- written dataset artifacts
- written checkpoints
- written local scratch artifacts
- exited the process group

Current interpretation:

- these warnings are noisy but not a promotion blocker for the OrangeFS canary
- the workload itself completed successfully
- OrangeFS durable paths are no longer the blocker for this canary
- the fixed `leader`/`worker` topology is the current preferred baseline

## Current interpretation

OrangeFS has already cleared the most important adoption gates:

- live server/client runtime
- K8s hostPath consumption on GPU nodes
- proven workflow for datasets/checkpoints
- distributed training group creation

The remaining work is now about keeping this launcher path from drifting again
and reducing late elastic shutdown noise, not proving OrangeFS viability for
the canary.

## Promotion gate

The DDP canary is now green when both ranks:

1. complete the 5 reduction steps
2. write dataset artifacts
3. write checkpoint artifacts
4. write scratch artifacts
5. exit `Completed`

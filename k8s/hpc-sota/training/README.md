# Training Canaries

This directory holds "more real than a smoke test" distributed training
canaries for the lab.

Design goals:

- keep the existing Kueue admission path in place
- keep the proven secondary GPU fabric (`net1`) as the transport lane
- use per-rank ephemeral PVCs instead of sharing a single `ReadWriteOnce`
  volume across nodes
- write visible artifacts to datasets / checkpoints / scratch so the storage
  path is exercised alongside NCCL

## Files

- `jobset-ddp-training-canary.yaml`
  - a two-rank synthetic DDP training canary
  - uses `nvidia` runtime class
  - uses the `hpc-training` LocalQueue
  - mounts `datasets`, `checkpoints`, and `scratch` as generic ephemeral PVCs
    so each rank gets its own RBD-backed volume

## Run

```bash
kubectl apply -f /home/devsounio/beagle/k8s/hpc-sota/training/jobset-ddp-training-canary.yaml
kubectl get jobs,pods -n beagle -l jobset.sigs.k8s.io/jobset-name=sounio-train-canary -o wide
kubectl logs -n beagle <pod-name>
```

## Why ephemeral PVCs here

The current HPC storage classes in this lab are RBD-backed and therefore
`ReadWriteOnce`. For multi-node DDP canaries, that is a good fit for:

- per-rank scratch
- per-rank checkpoints
- per-rank staged datasets

It is **not** the ideal fit for a single shared dataset volume across ranks.
For that future step, prefer a RWX-capable shared filesystem such as CephFS.

# Local Runtime Tier on `r770`

This tier exposes a carve-out inside `/mnt/ai-runtime` on `r770-proxmox` to
Kubernetes as a local PersistentVolume.

## Purpose

- hot local cache for model weights
- wheel / image staging
- inference runtime cache
- temporary artifact staging close to the `L4`

## Live path

- host path: `/mnt/ai-runtime/k8s-local-runtime-cache`
- node: `r770-proxmox`

## Kubernetes objects

- `StorageClass/local-ai-runtime-r770`
- `PersistentVolume/local-ai-runtime-r770-pv`
- `PersistentVolumeClaim/local-ai-runtime-r770-cache`
- `Job/local-ai-runtime-r770-canary`

## Notes

- this is a local PV, not a replicated durable volume
- use it for acceleration and caches, not as the only copy of important state
- the live canary writes a timestamp, a 64 MiB file, and a sha256 checksum into
  `/cache` on `r770-proxmox`

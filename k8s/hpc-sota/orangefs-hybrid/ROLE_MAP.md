# OrangeFS Hybrid Role Map

## Current nodes

### t560-proxmox

- best fit:
  - first OrangeFS server
  - platform anchor
  - live `zfast` workspace tier
  - observability anchor

Why:

- already behaves like a service-heavy node
- already holds the active workspace hot tier

### 5860-proxmox

- best fit:
  - second OrangeFS server
  - optional converged compute participant

Why:

- strong SSD inventory
- already participates in GPU-side work

Current reality after the `2026-04-24` repair:

- `5860` is still the live `server02`
- the repaired backend now lives on `/srv/orangefs-server02-store`
- this keeps the current namespace healthy
- it should still be treated as a temporary capacity anchor because the backing
  local-lvm thin pool is already close to full

### r740-proxmox

- role:
  - GPU compute
  - local premium NVMe tier
  - OrangeFS client

- observed growth candidate:
  - `/mnt/hpc-local-nvme`
  - near-GPU storage, but do not promote to OrangeFS server duty without a
    maintenance window and client canaries

### r770-proxmox

- role:
  - GPU compute
  - local runtime/model cache tier
  - OrangeFS client

- observed growth candidate:
  - `/mnt/darwin-fast`
  - near-GPU storage, but promotion would mix compute and storage authority
    unless explicitly accepted

## Incoming node

### HP DL380 G10 with NVMe and GPU

Runbook:

- [DL380_ONBOARDING.md](/home/devsounio/beagle/k8s/hpc-sota/DL380_ONBOARDING.md)

- role from day one:
  - GPU compute
  - local NVMe hot tier
  - OrangeFS client

- preferred later role:
  - next real OrangeFS growth server if we want the shared namespace to become
    genuinely multi-terabyte

- optional later role:
  - additional OrangeFS server capacity if we want to split metadata and data
    more aggressively after the first real capacity jump

## First hybrid recommendation

- `t560`: first OrangeFS server
- `5860`: second OrangeFS server
- `r740`, `r770`, `DL380`: clients

Keep outside OrangeFS:

- `BEAGLE` live workspace path on `zfast`
- `SOUNIO` live workspace path on `zfast`
- Grafana / Prometheus / K8s state

Local hot tiers:

- `r740`: `/mnt/hpc-local-nvme`
- `r770`: `/mnt/ai-runtime/k8s-local-runtime-cache`
- future `DL380`: local NVMe cache root

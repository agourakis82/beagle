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

### r740-proxmox

- role:
  - GPU compute
  - local premium NVMe tier
  - OrangeFS client

### r770-proxmox

- role:
  - GPU compute
  - local runtime/model cache tier
  - OrangeFS client

## Incoming node

### HP DL380 G10 with NVMe and GPU

- role from day one:
  - GPU compute
  - local NVMe hot tier
  - OrangeFS client

- optional later role:
  - additional OrangeFS server capacity if we want to split metadata and data
    more aggressively

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

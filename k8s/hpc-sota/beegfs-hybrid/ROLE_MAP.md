# BeeGFS Hybrid Role Map

## Current nodes

### t560-proxmox

- best fit:
  - BeeGFS management service
  - first metadata service
  - user/platform storage anchor
  - observability anchor

Why:

- already hosts the live `zfast` workspace tier
- already behaves like a service/control node
- management is not performance-critical

### 5860-proxmox

- best fit:
  - first BeeGFS storage server
  - optional converged client if it stays in the GPU pool

Why:

- strong SSD inventory
- already participates in GPU-side work

### r740-proxmox

- role:
  - GPU compute
  - local premium NVMe tier
  - BeeGFS client

### r770-proxmox

- role:
  - GPU compute
  - local runtime/model cache tier
  - BeeGFS client

## Incoming node

### HP DL380 G10 with NVMe and GPU

- role from day one:
  - GPU compute
  - local NVMe hot tier
  - BeeGFS client

- optional later role:
  - additional BeeGFS metadata or storage service if we decide the cluster wants
    more dedicated filesystem capacity

## First hybrid recommendation

### BeeGFS path

- `t560`: mgmtd + meta
- `5860`: storage
- `t560`: storage too if we want a converged two-server start
- `r740`, `r770`, `DL380`: clients

### Keep outside BeeGFS

- `BEAGLE` live workspace path on `zfast`
- `SOUNIO` live workspace path on `zfast`
- Grafana / Prometheus / K8s state

### Local hot tiers

- `r740`: `/mnt/hpc-local-nvme`
- `r770`: `/mnt/ai-runtime/k8s-local-runtime-cache`
- future `DL380`: local NVMe cache root

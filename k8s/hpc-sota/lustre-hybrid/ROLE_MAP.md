# Lustre Hybrid Role Map

## Current nodes

### t560-proxmox

- strongest candidate for:
  - Lustre MGS/MDT host later
  - user/platform exports
  - observability anchor
- reasons:
  - already hosts `zfast`
  - stable service role
  - not currently a GPU execution node

### 5860-proxmox

- candidate for:
  - Lustre OSS/OST host later
  - optional GPU client
- reasons:
  - strong SSD inventory
  - already participates in GPU workloads

### r740-proxmox

- role:
  - GPU compute
  - local NVMe premium cache tier
  - Lustre client

### r770-proxmox

- role:
  - GPU compute
  - runtime/model cache tier
  - Lustre client

## Incoming node

### HP DL380 G10 with NVMe and GPU

- ideal role on arrival:
  - GPU compute
  - local NVMe cache
  - Lustre client from day one
- optional later role:
  - add NVMe-backed OSTs if the node is not always saturated by GPU work

## Initial moonshot recommendation

### Data plane

- Lustre for:
  - `/lustre/datasets`
  - `/lustre/checkpoints`
  - `/lustre/scratch`

### Platform plane

- ZFS / local tiers for:
  - `/srv/workspaces`
  - `/srv/services`
  - `/srv/observability`

### Local hot tiers

- `r740`: `/mnt/hpc-local-nvme`
- `r770`: `/mnt/ai-runtime/k8s-local-runtime-cache`
- future `DL380`: local NVMe cache root

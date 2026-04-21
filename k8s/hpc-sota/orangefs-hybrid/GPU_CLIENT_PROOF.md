# OrangeFS GPU Client Proof

Date:

- `2026-04-04`

## Target clients

- `r740-proxmox`
- `r770-proxmox`

## Goal

Prove that the current OrangeFS two-node namespace can be consumed directly
from the GPU nodes without changing their OS baseline.

## What was used

- shared namespace:
  - `tcp://10.100.100.2:3334/orangefs_lab_2n`
- source of client binaries/libs:
  - `t560-proxmox`
- client nodes:
  - `r740-proxmox`
  - `r770-proxmox`

## Result

Both GPU nodes mounted the shared namespace successfully:

- `tcp://10.100.100.2:3334/orangefs_lab_2n on /var/lib/orangefs-lab/client-canary/mnt type pvfs2`

Both GPU nodes completed a write/read canary successfully:

- `orangefs-client-canary-r740-proxmox-2026-04-04T21:43:44-03:00`
- `orangefs-client-canary-r770-proxmox-2026-04-04T21:43:43-03:00`

Visible namespace contents included:

- `lost+found`
- `orangefs-canary-2n.txt`
- `orangefs-client-canary.txt`

## Meaning

This closes the next important gate:

- OrangeFS is not only buildable on the current OS
- it is not only mountable on the server anchor node
- it is now also consumable from the current GPU client nodes

## Reusable script

- [prove-orangefs-client-canary.sh](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/prove-orangefs-client-canary.sh)

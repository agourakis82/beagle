# BeeGFS Support and License Notes

## Architecture facts from official docs

BeeGFS officially documents:

- separate metadata and storage services
- direct client communication with storage servers
- converged layouts as a supported model
- RDMA support on clients and servers
- user-space server daemons

That makes it a very strong fit for an evolving AI/HPC cluster.

## Kernel and OS reality for this cluster

Current nodes:

- Debian 13
- Proxmox kernels `6.17.x-pve`

BeeGFS clients are built as kernel modules for the running kernel.
This is more compatible with the current cluster than trying to stand up first
generation Lustre servers directly on the same PVE stack.

That said, the safe path is still:

- validate package support for Debian on the target BeeGFS release
- test client module builds on one node before broad rollout
- keep the workspace/platform plane on the already-working local tiers during the
  transition

## Community Edition reality

BeeGFS Community Edition is self-supported and available-source.

Important nuance for 2026:

- BeeGFS 8 introduces licensing for some enterprise features
- storage pools are documented as enterprise-only in BeeGFS 8

This means the zero-cost design should avoid depending on:

- storage pools
- other enterprise-only features

The zero-cost path can still be very strong by using:

- core parallel filesystem capabilities
- deliberate namespace layout
- separate service placement
- local NVMe tiers outside the BeeGFS control plane

## Recommended moonshot stance

For a no-cost pivot:

1. start with BeeGFS Community Edition
2. do not assume storage pools
3. use local NVMe tiers explicitly rather than waiting for licensed policy
4. keep platform/workspace storage on ZFS/local tiers

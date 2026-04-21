# Lustre Support Matrix Notes

## What the public matrix says

The late-2025 public Lustre support matrix from Whamcloud shows:

- server test baseline: `RHEL 8.10`
- client test baselines: `RHEL 9.7`, `SLES 15 SP6`, `Ubuntu 22.04`

Reference:

- https://wiki.whamcloud.com/display/PUB/Lustre%2BSupport%2BMatrix

## What this means for the current cluster

Current nodes:

- Debian 13
- Proxmox kernels `6.17.x-pve`

This makes a direct server-side Lustre deployment on the current hosts a poor
moonshot target if we want a supportable and reproducible build.

## Practical interpretation

- do not build the first Lustre servers directly on Debian 13 + PVE kernels
- instead, use a supported server OS for the Lustre storage/control roles
- keep the existing cluster stable while preparing the split

## Recommended moonshot move

For the first serious Lustre pivot:

1. keep current Kubernetes and local storage alive
2. provision Lustre server roles on supported OS images
3. benchmark before moving training datasets and checkpoints

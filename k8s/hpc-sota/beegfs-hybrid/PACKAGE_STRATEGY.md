# BeeGFS Package Strategy for Debian 13 + PVE

This document turns the current platform reality into an install strategy.

## Current cluster reality

All current nodes are:

- `Debian 13 (trixie)`
- `6.17.x-pve`

That combination matters because BeeGFS clients build a kernel module for the
running kernel, while the server daemons are user-space services.

## Official package reality

BeeGFS currently publishes package repositories for:

- `bookworm`
- `bullseye`
- `focal`
- `jammy`
- `noble`
- `rhel8`
- `rhel9`
- `rhel10`
- `sles15`
- `trixie`

That is a very good sign for this cluster because `trixie` is already present
in the official release repositories.

For BeeGFS `8.3`, the official repository index exposes:

- `https://www.beegfs.io/release/beegfs_8.3/dists/`
- `beegfs-trixie.list`

That gives us a concrete no-license package path for the Debian side of the
cluster.

## Support reality for this exact cluster

BeeGFS `8.3` release notes state:

- the full integration test suite was run on `Debian 13`
- packages are provided for `Debian 11, 12, and 13`
- server services are fully supported on the packaged distributions
- client support prioritizes distribution kernels and custom kernels might or
  might not work

That last line is the critical nuance for us because `6.17.x-pve` is not the
default Debian kernel.

## What that means for us

The zero-cost path should use the official BeeGFS packages and proceed in this
order:

1. add the `trixie` repository on a single client node first
2. install `beegfs-client` and `beegfs-tools`
3. build and validate the client module against `6.17.x-pve`
4. only after that, install server packages on `t560` and `5860`

Recommended first repository file:

- `/etc/apt/sources.list.d/beegfs-trixie.list`

Recommended first role canary:

- `r740`

## Packages by role

### Client nodes

Install:

- `beegfs-client`
- `beegfs-tools`

Optional for RDMA server-side use or later client tuning:

- `libbeegfs-ib`

### Management node

Install:

- `beegfs-mgmtd`
- `beegfs-tools`

### Metadata node

Install:

- `beegfs-meta`

### Storage node

Install:

- `beegfs-storage`

For RDMA-enabled server paths:

- `libbeegfs-ib`

## Safe repository stance

Use the official BeeGFS release channel for:

- `v8.3.x` if we want latest stable

Fallback only if a regression appears on `trixie` client builds:

- pin to the most recent stable version that still provides the `trixie`
  repository and passes client builds cleanly on `6.17.x-pve`

## Canary rule

Do not add BeeGFS packages cluster-wide first.

Canary sequence:

1. `r740`
2. `r770`
3. `t560`
4. `5860`

That preserves the current live path while we validate the kernel/client story.

## Current canary outcome

The `r740` canary proved:

- official `trixie` packages install cleanly
- the client module build currently fails on `6.17.13-2-pve`

So the present blocker is:

- client-kernel compatibility on the `pve` kernel, not Debian packaging

## Why this is better than the Lustre-first path here

For the current cluster:

- BeeGFS server daemons are user-space
- BeeGFS officially publishes `trixie` packages
- BeeGFS client auto-builds the kernel module for the running kernel

That makes BeeGFS a much more credible near-term moonshot on the current
Debian/PVE base than forcing a first-generation Lustre rollout immediately.

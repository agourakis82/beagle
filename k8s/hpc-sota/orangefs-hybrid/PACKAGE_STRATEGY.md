# OrangeFS Package and Build Strategy

This document turns the current OS reality into an execution plan.

## Current cluster reality

All current nodes are:

- `Debian 13 (trixie)`
- `6.17.x-pve`

## What we learned on the current OS

Two facts matter a lot:

1. Debian package discovery on the current nodes does **not** expose ready-made
   `orangefs` packages through the configured APT sources.
2. the current `pve` kernel already ships an in-tree `orangefs.ko` module.

That is a very different picture from the BeeGFS client canary:

- BeeGFS had packages but failed on the client-module build
- OrangeFS does not currently show package availability in the configured APT
  sources, but the kernel-side client support already exists

## Practical implication

The most credible current-OS path is:

1. use the in-tree kernel client module
2. build or stage the OrangeFS user-space pieces from the OrangeFS project
3. start with a single-node proof on `t560`
4. then move to a two-server proof on `t560 + 5860`

## Client paths

OrangeFS documents multiple Linux client paths:

- kernel module
- direct interface
- FUSE client

For this cluster:

- preferred first client path: kernel module
- fallback path for experimentation: FUSE client

## Safe rollout stance

Do **not** start by trying to install OrangeFS cluster-wide.

Canary order:

1. prove the kernel module path on `t560`
2. stage one OrangeFS server proof on `t560`
3. validate client access from `r740`
4. validate client access from `r770`
5. only then widen the rollout

## Why this is strategically strong

OrangeFS may be the best current-OS moonshot because:

- the kernel already knows the filesystem
- server and client lean heavily on user-space code
- the official docs explicitly target HPC, genomics, and bioinformatics
- it avoids the exact BeeGFS blocker we already measured on `pve 6.17`

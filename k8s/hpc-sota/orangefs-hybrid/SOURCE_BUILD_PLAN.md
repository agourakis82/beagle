# OrangeFS Source Build Plan

This is the practical source-build path for OrangeFS on the current cluster.

## Why source build is the current path

On the current nodes:

- APT does not currently expose ready-made OrangeFS packages through the
  configured repositories
- the current Proxmox kernel already ships the in-tree `orangefs` module

That means the most credible next step is:

- source-build the OrangeFS user-space components
- use the in-tree kernel module for the Linux client path

## Source origin

Current upstream source path observed:

- `https://github.com/waltligon/orangefs.git`

Verified repository access:

- `HEAD = f4854f7cd201c77e02cc4a2764c389e010d6fca4`

## First build target

First build target:

- `t560`

Reason:

- already acts as service/platform anchor
- already carries the live `zfast` workspace tier
- is the safest place to run the first single-node OrangeFS proof

## First build objectives

Build enough of OrangeFS user space to prove:

- configuration generation works
- server binaries are available
- single-node proof can start and stop cleanly
- client path can be exercised from the current kernel client

## Safe sequence

1. clone source on `t560`
2. install build dependencies
3. compile user-space components
4. create a minimal single-node config
5. start a single-node proof only on `t560`
6. validate mount/client behavior locally
7. only then plan the two-server proof with `5860`

## Why this is better than forcing packages right now

The cluster already proved:

- BeeGFS package path is easy but blocked on the `pve` client kernel
- OrangeFS package path is not immediately exposed in APT
- OrangeFS kernel client path is already present in the current kernel

So OrangeFS source-build is the most rational way to keep momentum without
changing OS first.

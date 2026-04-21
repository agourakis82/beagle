# OrangeFS Single-Node Proof Plan

This is the first live OrangeFS proof we should run.

Status:

- completed on `2026-04-04`

## Node

- `t560-proxmox`

## Why on t560

- service-heavy role already fits
- active `zfast` workspace tier already lives here
- safest node for the first storage-service proof

## Proof scope

Single-node proof means:

- one server node only
- no migration of production data
- no change to Kubernetes production paths
- no dependency from live workloads

## What the proof must validate

- OrangeFS user-space services can be built and started
- a minimal config can be created
- the in-tree kernel client path can mount/use the proof namespace
- start/stop is clean
- no regression to the existing host duties

## What the proof must not touch

- `BEAGLE` live workspace path
- `SOUNIO` live workspace path
- Prometheus / Grafana state
- Kubernetes control-plane state
- Ceph

## Success criteria

- single-node OrangeFS server starts
- client path works on the current OS
- a test namespace is mounted and usable
- proof can be torn down cleanly

## What is already proven

- `orangefs.ko` exists in-tree on `6.17.13-2-pve`
- the kernel module loads and unloads cleanly
- a dynamic `pvfs2-server` now builds on `t560`
- a minimal `fs.conf` works for:
  - `--mkfs`
  - foreground start
- the foreground start reached:
  - `PVFS2 Server ready.`
- proof storage landed under:
  - `/zfast/orangefs-lab/single-node-dyn`
- the client stack now builds on `t560`:
  - `pvfs2-client`
  - `pvfs2-client-core`
  - `mount.pvfs2`
- the namespace now mounts successfully at:
  - `/zfast/orangefs-lab/single-node-dyn/mnt`
- client-side read/write was proven with:
  - `orangefs-canary.txt`

## Next step after success

- widen to:
  - `t560`
  - `5860`

Then benchmark from:

- `r740`
- `r770`

before making any storage-plane promotion decision.

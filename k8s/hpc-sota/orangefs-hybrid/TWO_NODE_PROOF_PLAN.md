# OrangeFS Two-Node Proof Plan

Status:

- completed on `2026-04-04`
- milestones reached:
  - `5860` source-build workspace bootstrapped
  - dynamic `pvfs2-server` binary built on `5860`
  - shared two-node config generated
  - both proof servers started successfully
  - `t560` mounted the two-node namespace
  - read/write canary succeeded

## Target shape

- `t560-proxmox`
  - first metadata anchor
  - first proof client mount
- `5860-proxmox`
  - first additional storage/server node

## Why this is the next gate

The single-node proof is already done. The next useful question is not whether OrangeFS
can run at all, but whether it can become a small shared storage island without changing
the current OS baseline.

## What this proof must validate

- `5860` can build the OrangeFS server user-space on its current OS
- `5860` can run the same OrangeFS server binary family as `t560`
- a two-node config can be generated cleanly
- the proof remains isolated from:
  - live Beagle/Sounio paths
  - Ceph
  - Prometheus/Grafana state
  - Kubernetes control-plane state

## Immediate milestones

1. bootstrap `5860` source-build workspace
2. build dynamic `pvfs2-server` on `5860`
3. generate shared two-node config for `t560 + 5860`
4. start both servers in a proof namespace
5. mount from `t560`
6. run read/write canary

## What is already done

- `5860` current OS confirmed:
  - `Debian 13.3`
  - `6.17.4-2-pve`
- in-tree `orangefs.ko` present on `5860`
- source-build deps installed on `5860`
- source cloned into:
  - `/var/lib/orangefs-lab/orangefs-src`
- dynamic server-only build output now exists at:
  - `/var/lib/orangefs-lab/orangefs-build-serveronly-dyn/src/server/pvfs2-server`
- shared two-node config exists in repo:
  - [two-node-fs.conf.example](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/two-node-fs.conf.example)
- reusable two-node proof script exists in repo:
  - [prove-t560-5860-two-node.sh](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/prove-t560-5860-two-node.sh)
- workstation launcher exists in repo:
  - [launch-t560-5860-two-node-from-workstation.sh](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/launch-t560-5860-two-node-from-workstation.sh)
- successful mount output included:
  - `tcp://10.100.100.2:3334/orangefs_lab_2n on /zfast/orangefs-lab/two-node/mnt type pvfs2`
- successful canary output included:
  - `orangefs-two-node-2026-04-04T21:37:20-03:00`

## Promotion criteria

- both nodes can run the proof server cleanly
- `t560` can mount the two-node namespace
- canary I/O succeeds
- teardown is clean

Status:

- achieved

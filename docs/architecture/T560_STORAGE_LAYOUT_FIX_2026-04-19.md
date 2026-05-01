# T560 Storage Layout Fix - 2026-04-19

## What Actually Failed

`t560-proxmox` did not run out of total disk.

The failure was that Kubernetes `DiskPressure` was being triggered by the small
root filesystem on `pve-root`, while the large `zfast` pool still had abundant
free space.

At the time of diagnosis:

- `/` on `pve-root` was about `196G` total and over `95%` full
- `/zfast` was about `2.6T` total and only about `2%` used

The node therefore looked "full" to kubelet even though the machine still had
substantial raw capacity.

## Root Cause

The hot paths that grow quickly were landing on the wrong filesystem:

- `/home/devsounio/.local/share/containers`
- `/home/devsounio/beagle/target`
- journald and local container runtime state on `/var`

This made the cluster fragile because:

- the node had plenty of storage overall
- but the paths that matter for kubelet health were consuming the root LV
- `beagle-core` had also been pinned to `t560` with node-local storage, so one
  rootfs pressure event could destabilize the control/cognitive path

## Immediate Fixes Applied

### Cluster/runtime

- `beagle-core` was moved off `t560` and onto `r770`
- `beagle-core` now uses the Ceph-backed `beagle-data` PVC again
- `project-cockpit` was increased to `2` replicas with more memory headroom

### Host/storage

- old journals were vacuumed
- unused rootless Podman images were pruned
- the heavy user-owned paths were moved onto `zfast` with persistent bind mounts:
  - `/home/devsounio/.local/share/containers`
  - `/home/devsounio/beagle/target`

The bind mounts are persisted in `/etc/fstab`.

Backups were preserved in place:

- `/home/devsounio/.local/share/containers.pre-zfast`
- `/home/devsounio/beagle/target.pre-zfast`

## Result

After the move:

- `DiskPressure` cleared on `t560`
- root free space returned to healthy levels
- the public Cockpit/native boundary remained healthy during validation

## Architectural Lesson

The mistake was not "Ceph used all the disks" and not "the GPU path was bad."

The real design error was letting critical growth paths live on the small root
filesystem while the large local pool sat mostly unused.

## Safer Placement Rule Going Forward

### Use networked or resilient storage for critical product state

- `beagle-core`
- control/cognitive services
- durable product state

### Use large local pools for hot, fast, disposable growth

- build artifacts
- rootless container/image storage
- caches
- scratch workspaces

## Do Not Regress

- do not pin critical cluster-brain services to `t560` root-backed assumptions
- do not tolerate `DiskPressure` for those critical services
- do not let fast-growing developer/runtime paths accumulate on `/` when `zfast`
  is available

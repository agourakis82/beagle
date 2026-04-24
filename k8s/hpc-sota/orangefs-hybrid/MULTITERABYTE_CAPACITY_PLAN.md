# OrangeFS Multi-Terabyte Capacity Plan

## Goal

Turn the repaired two-server OrangeFS island into a real multi-terabyte shared
AI/HPC data plane instead of a small island that merely looks healthy again.

## Current repaired truth

As of `2026-04-24`, the outage is fixed:

- GPU workers see the OrangeFS export at roughly `933G` total
- worker-side free space is roughly `748G`
- text-integrity probes are green on both `r740` and `r770`
- the live namespace is no longer stuck at `100%` full

The repaired layout is:

- `t560-proxmox`
  - `orangefs-server01.service`
  - backend rooted under `/zfast/orangefs-lab`
  - host backing has roughly `2.5T` free on `zfast`
- `5860-proxmox`
  - `orangefs-server02.service`
  - backend rooted under `/srv/orangefs-server02-store`
  - dedicated server02 filesystem is roughly `492G` total with `374G` free

## Why the cluster still is not multi-terabyte

The worker-visible export is still bounded by the smaller live server backend.

That means the repaired namespace is honest, but still small:

- server01 on `t560` has room
- server02 on `5860` is the limiting backend
- the export therefore remains in the sub-terabyte class even though the lab
  has far more raw storage across other nodes

The cluster-wide `47TB` headline is not the same thing as OrangeFS capacity.
Only storage that is actually exported through the active OrangeFS servers
counts toward the shared data plane.

## Real bottleneck on 5860

The current `5860` backend is safer than the old broken layout, but it is not a
good long-term capacity anchor.

Measured reality after the repair:

- `/srv/orangefs-server02-store` is a `500G` thin-backed filesystem
- the underlying `pve/data` thin pool is already about `98.47%` full

So even though the dedicated server02 LV itself is only about `20%` used, the
pool beneath it is already nearly exhausted.

This is why the current state should be read as:

- outage repaired
- namespace integrity restored
- still not safe to market as multi-terabyte OrangeFS

## What does not count as a safe fix

These are tempting but misleading:

- counting client nodes like `r740` or `r770` as OrangeFS capacity
- counting unrelated raw disks elsewhere in the cluster
- counting thin-provisioned local-lvm virtual sizes as real free space
- reusing stopped-VM sparse disks on the same saturated thin pool as if they
  were fresh dedicated media

Those approaches make the numbers look larger without actually making the
shared filesystem safer.

## Promotion options

### Option 1: Replace 5860 as the growth server

Best long-term path:

- keep `t560` as server01 and control anchor
- promote a node with genuine large local storage as the next OrangeFS server
- best current candidate: the incoming `HP DL380 G10 with NVMe`

Why:

- real expansion path
- avoids betting the data plane on a nearly full thin pool
- aligns with the long-term supercomputing layout

### Option 2: Add a third OrangeFS server on real storage

Use when we want to grow capacity without an immediate server02 swap:

- keep `t560` and current `5860` online short-term
- add a new server on genuine NVMe or large local disk
- migrate or rebalance toward the new server as the durable capacity anchor

This is the least disruptive growth path if new storage arrives before we want
to reassign roles.

### Option 3: Give 5860 a real dedicated storage pool

Only valid if `5860` receives storage that is genuinely outside the current
`pve/data` thin pool.

This could work if:

- a new local SSD/NVMe device is added
- or a new VG/LV stack is created on real unused physical media

It is **not** enough to enlarge the current thin-provisioned illusion.

## Recommended path

### Now

- keep the repaired `933G` namespace in service
- keep worker-side validation and text-integrity probes green
- expose server-side backend ceilings in operator tooling

### Next

- treat `5860` as a temporary repaired server, not the final capacity anchor
- choose the next real storage host for OrangeFS growth
- prefer the future `DL380` if its NVMe inventory is available soon

### Later

- rebalance OrangeFS onto genuinely large backing devices
- then revisit whether metadata and data should stay converged or be split more
  aggressively across servers

## Operational rule

Until OrangeFS is backed by genuinely large exported server storage, the
cluster should describe it as:

- a repaired shared AI/HPC data plane
- suitable for current datasets, checkpoints, and canaries
- not yet the final multi-terabyte supercomputing storage layer

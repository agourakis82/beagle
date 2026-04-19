# Supercomputing Egress and 10Gb Assessment

## Executive summary

The current cluster has **four independent 1Gb internet egress paths**, one per
node, all using the management network:

- `t560-proxmox` -> `vmbr0` -> `nic0` -> `192.168.3.1`
- `r770-proxmox` -> `vmbr0` -> `nic1` -> `192.168.3.1`
- `r740-proxmox` -> `vmbr0` -> `nic0` -> `192.168.3.1`
- `5860-proxmox` -> `vmbr0` -> `nic1` -> `192.168.3.1`

Observed live link state:

- all four management uplinks are currently `1000Mb/s`, full duplex, with
  carrier
- the 100Gb fabrics (`10.100`, `10.200`, `10.210`) are east-west only today and
  are not the current north-south internet path

That means:

- **distributed outbound bandwidth already exists at the cluster level**
  - if work is spread across nodes, the lab can consume multiple 1Gb uplinks in
    parallel
- **combined outbound bandwidth does not exist for a single node or workload**
  - no node currently has a bonded multi-uplink internet edge
  - no dedicated egress gateway is fronting the cluster

Additional switch truth from the Arista:

- `Et1/1` is already the live `t560` 100Gb backbone port
- `Et30/1` is already the live `t560` secondary 100Gb fabric port
- `Et33` is the current 10Gb service-fabric attempt and is still pinned to the
  broken `5860` copper-vs-SX path
- `Et34` is the only other visible free 10Gb switch port today

So the cluster can still build a cleaner 10Gb service edge on `t560`, but this
specific switch does **not** currently offer an obvious `2x10G` free pair for a
bonded egress edge.

## Port reality by node

### `t560-proxmox`

- management uplink:
  - `nic0`
  - live at `1000Mb/s`
- spare high-speed candidates:
  - `ens6f0`
  - `ens6f1`
  - both are **10G fibre-class ports**
  - neither is part of the current live egress path
- 100Gb fabric ports:
  - `nic6`
  - `nic7`

Conclusion:
- `t560` is the cleanest candidate for a **future 10G or 2x10G egress/service
  edge**
- it is better suited than a GPU node because it already acts as control-plane
  infrastructure and has spare dedicated 10G ports
- with the currently observed Arista inventory, `t560` is the best candidate
  for a **single 10G** service/egress edge on `Et34`
- a true `2x10G` bonded edge would require either:
  - additional free 10G switch ports, or
  - a different upstream/switch design than the current `Et33`/`Et34` pair

### `r740-proxmox`

- management uplink:
  - `nic0`
  - live at `1000Mb/s`
- extra copper ports:
  - `nic1`, `nic2`, `nic3`
  - these are **1Gb copper-class**, not 10Gb
- fabric ports:
  - `nic4`
  - `nic5`
  - these are the 100Gb-capable fabric interfaces already used for cluster
    fabrics

Conclusion:
- `r740` is **not** the dormant 10Gb candidate
- it can participate in distributed egress through its existing 1Gb management
  uplink, but it is not the best place to build a new internet edge

### `r770-proxmox`

- management uplink:
  - `nic1`
  - live at `1000Mb/s`
- high-speed fabric ports:
  - `nic3`
  - `nic5`
- no spare 10Gb internet-oriented port was identified in the current live role

Conclusion:
- `r770` should stay focused on `cluster-core` and stable GPU service lanes

### `5860-proxmox`

- management uplink:
  - `nic1`
  - live at `1000Mb/s`
- additional service-fabric candidate:
  - `nic0`
  - copper interface supporting up to `10Gb/s`
- current blocker:
  - the host-side service bridge is configured correctly as `vmbr30`
  - Arista `Ethernet33` is configured in VLAN `130`
  - but `Et33` currently reports `Type 1000BASE-SX`, while `nic0` is copper
  - result: `NO-CARRIER` / `notconnect`

Conclusion:
- `5860` can still be a 10Gb service edge, but **only after the media mismatch
  on `Et33` is fixed**
- operationally it is less attractive than `t560` because it is also a GPU node

## What “distribute” vs “combine” means here

### Distributed bandwidth

This is already available:

- each node has its own 1Gb uplink through the management plane
- concurrent pulls, package installs, and external API traffic can already be
  spread across nodes
- the cluster can therefore use more than 1Gb aggregate internet bandwidth
  **if the workload is distributed**

Good uses:

- concurrent image pulls on different nodes
- package installation during multiple builds
- model downloads split across several nodes

### Combined bandwidth

This is **not** available yet for one node or one service:

- a single node cannot currently exceed its own physical uplink speed
- a single pod cannot “merge” the internet bandwidth of multiple nodes
- true combination requires one of:
  - multiple uplinks on the same node bonded with upstream switch support
  - a dedicated egress gateway with multiple physical uplinks and LACP or
    multi-WAN policy

## Best HPC recommendation

### Option A: preferred

Make `t560-proxmox` the dedicated supercomputing service/egress edge.

Why:

- spare 10G fibre ports already exist there
- it is already the infrastructure/control node
- it avoids pushing service-plane duties onto a GPU node
- it is the best place for:
  - registry cache
  - package cache
  - DNS control plane
  - artifact proxy
  - outbound egress gateway

Target shape:

- keep the current per-node 1Gb management egress as fallback
- add one 10G uplink on `t560` first, most likely `ens6f0 <-> arista:Et34`
- do **not** plan around `2x10G` on the current switch until a second free 10G
  path is actually provisioned
- route heavy internet-adjacent cluster traffic through `t560` over the 100Gb
  east-west fabrics

### Option B: acceptable fallback

Finish the `5860` 10Gb service-fabric on `nic0 <-> Et33`.

Why:

- much of the service-plane design is already written for `5860`
- host-side `vmbr30` now exists live

Why it is weaker than Option A:

- `5860` is also a GPU/service node
- the current link is blocked by copper vs `1000BASE-SX` media mismatch
- service-edge duties on a GPU node increase role coupling

## Practical near-term plan

1. Keep the current per-node 1Gb management egress alive as the baseline.
2. Decide whether the dedicated 10Gb service/egress edge should live on:
   - `t560` preferred
   - `5860` fallback
3. If `t560` is chosen:
   - use `Et34` as the first concrete SFP+ target unless the switch plan
     changes
   - provision the correct fibre optics/cabling
   - terminate `ens6f0` or `ens6f1` there
   - build the 10Gb service plane there instead of on `5860`
4. If `5860` is kept:
   - replace the `Et33` optic/cable path with the correct copper-capable 10G
     media
   - verify carrier comes up on `nic0` and `Vlan130`
5. After one real 10Gb edge exists:
   - move registry/package/model egress through that edge
   - keep the cluster’s heavy downloads on the 100Gb east-west fabric plus the
     cache, not as repeated internet pulls from every node

## Bottom line

- `r740` is not the dormant 10Gb answer
- `t560` is the strongest clean 10Gb egress candidate
- `5860` remains viable, but only after fixing the `Et33` media mismatch
- current internet bandwidth is already **distributed**
- true **combined** bandwidth still needs an intentional egress-edge design and
  more than one real upstream high-speed port
- if the lab's `10Gb` upstream is currently forced through the `1Gb` Ubiquiti
  switch, move that high-speed handoff into the Arista domain and terminate the
  cluster-side edge on `t560`, while keeping Ubiquiti as the management/access
  switch

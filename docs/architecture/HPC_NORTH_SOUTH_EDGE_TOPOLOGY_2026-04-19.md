# HPC North-South Edge Topology

## Executive recommendation

Do **not** keep the lab's only 10Gb internet handoff trapped behind the
1Gb-only Ubiquiti switch if the goal is a real supercomputing-capable
north-south edge.

The best near-term architecture is:

1. keep the Ubiquiti switch as the **management / access / PoE** switch
2. land the **10Gb upstream handoff** on the Arista switching domain
3. terminate the cluster's **10Gb service/egress edge** on `t560-proxmox`
4. keep the cluster's heavy package / model / registry egress flowing through
   `t560` over the 100Gb east-west fabrics

That gives the lab:

- a clean high-speed north-south path
- a non-GPU service edge
- continued 1Gb fallback on the management plane
- less coupling between GPU service nodes and internet-edge duties

## What the current evidence says

### Current bottleneck

- the lab receives a `10Gb` upstream, but the 16-port Ubiquiti switch is only
  providing `1Gb` switching to the current nodes
- all four nodes currently default-route via:
  - `192.168.3.1`
  - over `vmbr0`
  - at `1Gb/s`

So today:

- the cluster already has **distributed** internet egress
- but each node is capped by its own `1Gb` management uplink
- and no single workload gets a true high-speed north-south path

### Arista truth

- the Arista already carries the high-speed east-west cluster fabrics
- `Et33` is currently the broken `5860` 10Gb service-fabric attempt
- `Et34` is the only clearly free 10Gb switch port at the moment
- the Arista is **not** currently acting as the routed internet gateway:
  - `no ip routing`
  - default route exists only for switch management via `Management1`

This is important:

- connecting the 10Gb handoff directly to the Arista is useful
- but the Arista alone is not currently the router/NAT/firewall appliance
- it should be treated as the **10Gb transit switch**, not the whole edge stack

## Best target shape

### Preferred design

Use `t560-proxmox` as the HPC north-south edge host.

Why `t560`:

- it is already the infrastructure/control host
- it has spare 10G fibre-class ports:
  - `ens6f0`
  - `ens6f1`
- it is not a GPU compute/service node
- it is the right place for:
  - registry caches
  - package caches
  - DNS forwarders
  - artifact proxies
  - egress policy / NAT / proxy functions

### Role split

- Ubiquiti:
  - keep as management/access/PoE switch
  - keep low-speed administrative devices and legacy copper there
- Arista:
  - high-speed transit / fabric switch
  - carry the 10Gb upstream and cluster-side high-speed edge links
- `t560`:
  - actual lab service/egress edge host
  - 10Gb service-plane gateway
  - north-south cache/proxy/NAT anchor

## Recommended practical topology

### Option A: best near-term

- upstream `10Gb` handoff -> Arista `10Gb` port
- Arista `Et34` -> `t560:ens6f0` as the cluster-side 10Gb edge link
- keep Arista `Management1` on the Ubiquiti management network
- keep Ubiquiti attached for 1Gb management/access only

In this shape:

- the 10Gb path no longer depends on the Ubiquiti data plane
- the cluster can still be managed through the existing 1Gb management network
- the service/egress plane can be built on `t560`

### Option B: fallback

Fix `5860:nic0 <-> Arista Et33` and keep `5860` as the 10Gb service edge.

This is operationally weaker because:

- `5860` is a GPU node
- `Et33` is currently a copper-vs-SX mismatch
- service-edge duties on a GPU node create unnecessary role coupling

## What “bridge the switches” should mean

The right interpretation is:

- keep a **1Gb bridge/uplink** between the Ubiquiti and Arista for management
  and legacy access
- do **not** make the Ubiquiti the required transit path for the 10Gb internet
  handoff

That means:

- yes, the two switches should remain connected
- no, the 10Gb handoff should not stay logically trapped behind the Ubiquiti if
  you want real north-south throughput

## Routing / NAT reality

Right now the Arista is not doing routed internet edge duties:

- `no ip routing`
- its default route is only for its own management plane

So if the current Ubiquiti device is also your NAT/firewall/router, then simply
moving a cable to the Arista is not enough by itself.

One of these must own the actual edge behavior:

- the existing upstream router/firewall
- `t560` as a Linux service-edge host
- a dedicated firewall/router appliance

For the lab as it exists today, the pragmatic path is:

- use the Arista as the 10Gb switching/transit domain
- use `t560` as the actual service/egress edge host
- leave the Ubiquiti in place for management and legacy access

## Bandwidth truth

### What already exists

- four independent `1Gb` management egress paths
- aggregate cluster outbound can exceed `1Gb` if work is distributed

### What does not yet exist

- no single node has a high-speed internet edge in production
- no single job/workload gets “combined” bandwidth
- no bonded multi-uplink edge exists yet

### What a better HPC design gives you

After moving the 10Gb path to Arista + `t560`:

- one real high-speed north-south edge for registry/model/package traffic
- cluster-wide acceleration through cache/proxy reuse
- reduced repeated internet pulls across nodes
- continued per-node 1Gb fallback if the 10Gb edge is down

## Recommended next steps

1. Keep the current per-node 1Gb management egress unchanged as the fallback.
2. Treat `t560` as the preferred HPC service/egress edge host.
3. Use Arista `Et34` as the first cluster-side 10Gb target for `t560`.
4. Keep the Ubiquiti-Arista link for management/access only.
5. Do not plan around `2x10G` yet; this switch currently shows only one clearly
   free 10Gb port.
6. Move the service-plane gateway/caches/proxies onto `t560` once the physical
   10Gb path exists.
7. Only keep `5860 <-> Et33` as the fallback path if the media mismatch is
   fixed and you intentionally choose the GPU-node edge design.

## Bottom line

It is worth moving the 10Gb handoff off the 1Gb-only Ubiquiti bottleneck.

The best current architecture is:

- `Ubiquiti` for management/access
- `Arista` for high-speed transit/fabric
- `t560` for the cluster's real 10Gb service/egress edge

That is the cleanest supercomputing posture the current hardware supports.

# Sounio 100Gb Networking

This directory is the source of truth for the cluster underlay plan.

## Current reality

The physical fabric is already better than the Kubernetes underlay:

- `t560-proxmox`
  - management: `192.168.3.169/24` on `vmbr0`
  - primary 100Gb: `10.100.100.2/24` on `vmbr100`
  - secondary 100Gb: `10.200.0.2/24` on `vmbr200`
- `r770-proxmox`
  - management: `192.168.3.228/24` on `vmbr0`
  - primary 100Gb: `10.100.100.1/24` on `vmbr2`
  - secondary 100Gb: `10.200.0.1/24` on `vmbr1`
- `r740-proxmox`
  - management: `192.168.3.168/24` on `vmbr0`
  - primary 100Gb: `10.100.100.4/24` on `vmbr100`
  - secondary 100Gb: `10.200.0.4/24` on `vmbr200`
- `5860-proxmox`
  - management: `192.168.3.207/24` on `vmbr0`
  - primary 100Gb: `10.100.100.3/24` on `vmbr100g`
  - secondary 100Gb: `10.200.0.3/24` on `vmbr200`

All four hosts expose the 100Gb bridges with `mtu 9000`.

## The serious gap

Kubernetes still identifies the nodes by the management network:

- `t560-proxmox` -> `192.168.3.169`
- `r770-proxmox` -> `192.168.3.228`
- `r740-proxmox` -> `192.168.3.168`
- `5860-proxmox` -> `192.168.3.207`

Cilium is also still configured for overlay mode:

- `routing-mode: tunnel`
- `tunnel-protocol: vxlan`
- `auto-direct-node-routes: "false"`

That means the cluster underlay is still management-first, not 100Gb-first.

## Target state

1. **Primary underlay**
   - Kubernetes node `InternalIP` should move to `10.100.100.x`
   - this becomes the default east-west fabric for cluster traffic
2. **Secondary underlay**
   - reserve `10.200.0.x` for storage, replication, migrations, and future special-purpose traffic
3. **Cilium datapath**
   - move from VXLAN tunnel to native/direct routing after the node IP migration is complete
4. **MTU**
   - keep jumbo MTU on the 100Gb fabric only after end-to-end validation
   - do not assume the management network can safely carry `9000`

## Recommended order

1. Run `inventory-fabric.sh` and `preflight-k8s-underlay.sh`
2. Standardize the bridge naming in documentation only. Do not rename live Linux bridges yet.
3. Migrate kubelet/node IP selection so node `InternalIP` becomes `10.100.100.x`
4. Re-check node health, Ceph, and service reachability
5. Move Cilium from VXLAN to native/direct routing
6. Only after that, tune performance, MTU, and offload knobs

## Why this order

Changing Cilium first while the nodes still identify as `192.168.3.x` would preserve the wrong underlay.
The cluster has to know that the 100Gb fabric is the real east-west path before the datapath switch matters.

## Control-plane assets

- `lab-network-inventory.yaml`
  - the current live inventory for management, underlay, storage, and GPU
    fabric planning
- `CONTROL_PLANE.md`
  - the policy document for VLANs, gateways, DNS, and IPAM
- `arista-7060x-fabric.example.cfg`
  - the switch intent skeleton for SVIs and VLANs
- `lab-dns/`
  - a lightweight CoreDNS deployment authoritative for `lab.sounio`

## Scripts

- `inventory-fabric.sh`
  - collects live host fabric inventory and current Kubernetes/Cilium addressing
- `preflight-k8s-underlay.sh`
  - fails loudly when the cluster is still using management IPs
  - checks the live Cilium datapath via `cilium-dbg status`, instead of trusting only the ConfigMap
- `cutover-cilium-native.sh`
  - switches Helm values to native/direct routing
  - restarts the Cilium DaemonSet and operator so the agents actually load the new datapath

## Working stance now

The serious baseline is now:

1. `10.100.100.0/24`
   - live Kubernetes underlay
2. `10.200.0.0/24`
   - live jumbo-clean storage/migration fabric
   - also the honest pilot lane for early RDMA work
3. `10.210.0.0/24`
   - reserved for the dedicated GPU fabric once the switch side is ready

That means the cluster is no longer “just wired”; it has an explicit network
control-plane in git.

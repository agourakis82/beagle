# Sounio Lab Network Control Plane

This document turns the current lab wiring into an intentional network control
plane. The goal is to stop treating the cluster fabric as "just links that
work" and start treating it as a governed substrate for workspaces, storage,
and distributed GPU jobs.

## Target layers

1. Management
   - subnet: `192.168.3.0/24`
   - purpose: Proxmox UI, SSH administration, BMC/IPMI, tailnet bootstrap
   - rule: no heavy east-west traffic

2. Kubernetes underlay
   - subnet: `10.100.100.0/24`
   - purpose: node `InternalIP`, Cilium native routing, cluster east-west
   - status: live
   - rule: this is the default fabric for pod, service, and controller traffic

3. Storage and migration
   - subnet: `10.200.0.0/24`
   - purpose: Ceph replication, data seeding, artifact movement, backup/restore
   - status: live, jumbo validated end-to-end
   - rule: keep it clean and deterministic so storage and migration do not
     fight the cluster underlay

4. GPU RDMA fabric
   - preferred future subnet: `10.210.0.0/24`
   - fallback pilot subnet: `10.200.0.0/24`
   - purpose: RoCE/GPUDirect RDMA, NCCL all-reduce, multi-node training
   - status: pilot live on `10.200`, dedicated `10.210` live on GPU nodes
   - rule: isolate RDMA from generic cluster traffic

5. Service and egress fabric
   - subnet: `10.30.0.0/24`
   - purpose: DNS forwarder/cache, DHCP, registry/artifact cache, general egress
   - status: host and switch configured on
     `5860-proxmox:nic0 <-> arista-7060:Ethernet33`, but still `NO-CARRIER`
     / `lowerlayerdown`
   - rule: keep services and internet-adjacent traffic off the 100Gb fabrics

## Why split the fabrics

- `10.100` should stay boring and reliable for Kubernetes.
- `10.200` is already a good place for storage and migration.
- `10.30` is a good place for services, egress, and caches that should not
  pollute the 100Gb paths.
- RDMA/RoCE wants different tuning and failure semantics than the control plane.
- When PFC or ECN enters the picture, we want the blast radius constrained to
  the GPU fabric instead of poisoning the entire cluster.

## Recommended L3 ownership

Prefer putting gateways and VLAN SVIs on the Arista switch pair instead of
distributing L3 state across the Proxmox hosts.

Recommended gateway scheme:
- management: `192.168.3.254`
- k8s underlay: `10.100.100.254`
- storage/migration: `10.200.0.254`
- gpu-rdma: `10.210.0.254`
- service-egress: `10.30.0.1` today on `5860-proxmox`, with `10.30.0.254`
  on the Arista as the diagnostics SVI

Current live note:
- `5860-proxmox` now has `vmbr30` with `10.30.0.1/24`, `nic0` enslaved, and
  MTU `9000`
- `arista-7060` has `Ethernet33` in access VLAN `130` and `Vlan130` as
  `10.30.0.254/24`
- the remaining activation blocker is physical/electrical carrier on the 10Gb
  link, not missing Linux or switch configuration
- current observed mismatch:
  - `5860-proxmox:nic0` is a twisted-pair copper interface
  - `arista-7060:Ethernet33` currently reports `Type 1000BASE-SX`
  - until `Ethernet33` has the correct copper-capable transceiver/cable path,
    the 10Gb service fabric will remain `lowerlayerdown`

If you keep the current flat setup for a while, still reserve those addresses
now so the migration later is mechanical rather than creative.

## DNS and naming

Use three layers:

1. Kubernetes DNS
   - `*.svc.cluster.local`
   - leave CoreDNS responsible for service discovery only

2. Lab DNS
   - example zone: `lab.sounio`
   - purpose: physical hosts, gateways, storage endpoints, stable infra names
   - examples:
     - `t560.lab.sounio`
     - `r770.lab.sounio`
     - `r740.lab.sounio`
     - `pve-5860.lab.sounio`
     - `workspace.lab.sounio`
     - `svc10g-gw.lab.sounio`
     - `dockerhub-cache.svc10g.lab.sounio`
     - `ghcr-cache.svc10g.lab.sounio`
     - `k8s-registry-cache.svc10g.lab.sounio`
     - `dns-admin.svc10g.lab.sounio`
     - `ipam.svc10g.lab.sounio`

3. Tailnet identity
   - purpose: remote human entrypoint from notebooks
   - examples:
     - `workspace.tailnet-name.ts.net`
     - `r770.tailnet-name.ts.net`

Recommended rule:
- humans enter through tailnet names
- machines inside the lab resolve `lab.sounio`
- pods keep using `cluster.local`

## IPAM / source of truth

Do not scale to 21 projects and a growing GPU fleet with ad hoc IP notes.

Minimum acceptable source of truth:
- the `lab-network-inventory.example.yaml` in this directory, versioned in git

Better source of truth:
- NetBox for prefixes, VLANs, IP allocations, interfaces, and rack/device roles

Pragmatic path:
1. keep the YAML inventory in git now
2. migrate that inventory into NetBox once the fabric stabilizes
3. then sync DNS records and labels from the source of truth

## Suggested VLAN map

These IDs are proposed, not yet enforced live:

- VLAN 3: management
- VLAN 100: k8s underlay
- VLAN 200: storage and migration
- VLAN 210: gpu-rdma
- VLAN 130: 10Gb service fabric

The important part is not the exact number. The important part is that RDMA gets
its own domain instead of piggybacking forever on a shared fabric.

## Operational order

1. Keep `10.100` as the live Kubernetes underlay.
2. Keep `10.200` healthy and jumbo-clean for storage/migration.
3. Keep `10.30` healthy as the services and egress lane.
4. Stand up lab DNS and document gateways/VLANs.
5. Reserve `10.210` and wire the Arista side for GPU RDMA.
6. Keep the current pilot substrate on `10.200` healthy while `10.210` is built.
7. Install the final dedicated GPU fabric after step 5 exists.
8. Move distributed GPU traffic to the RDMA fabric.
9. Keep the live lab inventory and DNS records versioned in git until NetBox
   becomes the formal source of truth.

## Deep-networking posture

When you want the lab to feel production-grade, the next upgrades are:

- NetBox for IPAM and inventory
- Technitium or Unbound for `lab.sounio`
- explicit VLAN/SVI/gateway ownership on the Arista
- a dedicated 10Gb service fabric with DNS and cache services
- Network Operator + Multus for GPU RDMA
- benchmark and alerting for both `10.100` and `10.200`/`10.210`
- a simple authoritative DNS plane for `lab.sounio`

## Assets in this repo

- `lab-network-inventory.yaml`
  - the live inventory we should trust first
- `arista-7060x-fabric.example.cfg`
  - the switch-side intent we should converge toward
- `lab-dns/`
  - a lightweight authoritative zone for `lab.sounio`
- `GPU_RDMA_PHASE3.md`
  - the phase-3 plan for the dedicated `10.210` GPU VLAN

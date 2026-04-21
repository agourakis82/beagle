# Normalize the GPU fabric interface name

The secondary 100Gb fabric is healthy, but the raw host interface names are
still heterogeneous:

- `t560-proxmox` -> `nic7`
- `r770-proxmox` -> `nic3`
- `r740-proxmox` -> `nic4`
- `5860-proxmox` -> `ens5f1np1`

For the pilot substrate we already normalized the bridge layer with a common
altname:

- `gpufabricbr0`

Current live bridge mapping:
- `r770-proxmox` -> `vmbr1` + altname `gpufabricbr0`
- `r740-proxmox` -> `vmbr200` + altname `gpufabricbr0`
- `5860-proxmox` -> `vmbr200` + altname `gpufabricbr0`

That is why the pilot `NetworkAttachmentDefinition` can safely use:

- `master: gpufabricbr0`

Before the full NVIDIA Network Operator / RDMA phase becomes pleasant to
operate, converge the secondary GPU fabric to one host-level interface name on
every GPU node:

- preferred name: `gpufabric0`

Why:
- one `NetworkAttachmentDefinition`
- one `NicClusterPolicy`
- one set of training pod annotations

Do **not** do a live rename casually on an active host. The safe path is:

1. pick the exact interface for each host from `lab-network-inventory.yaml`
2. generate a persistent `.link` file
3. update the host network config to use the new name
4. reboot in a maintenance window

The desired end state for the final dedicated GPU VLAN is:
- raw NIC or bond name normalized to `gpufabric0`
- `master: gpufabric0` or `master: gpufabricbr0`, depending on whether the
  final design stays bridge-based or goes direct-device
- `ifNames: ["gpufabric0"]` in the RDMA shared device plugin if the final
  design moves from bridge pilot to direct NIC ownership

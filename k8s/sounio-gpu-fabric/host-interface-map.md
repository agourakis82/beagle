# Secondary 100Gb Fabric Interface Map

This is the current live mapping for the `10.200.0.x` fabric.

## Nodes

- `t560-proxmox`
  - bridge: `vmbr200`
  - IP: `10.200.0.2/24`
  - physical interface: `nic7`
  - altname: `enp153s0f1np1`

- `r770-proxmox`
  - bridge: `vmbr1`
  - IP: `10.200.0.1/24`
  - physical interface: `nic3`
  - altnames:
    - `enP1p100s0f0np0`
    - `enP1s3f0np0`

- `r740-proxmox`
  - bridge: `vmbr200`
  - IP: `10.200.0.4/24`
  - physical interface: `nic4`
  - altname: `enp59s0f0np0`

- `5860-proxmox`
  - bridge: `vmbr200`
  - IP: `10.200.0.3/24`
  - physical interface: `ens5f1np1`
  - altname: `enp16s0f1np1`

## Important note

The interface names are not homogeneous across the nodes.

For the first honest RDMA rollout, plan for:
- node-specific master names in the operator policy, or
- a later host-level normalization step if you want one generic config

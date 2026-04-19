# 10Gb Service Fabric

This fabric is currently prototyped on the dedicated 10Gb link between
`5860-proxmox:nic0` and `arista-7060:Ethernet33`, but the cleaner long-term
target is a non-GPU service edge on `t560-proxmox`.

## Intended role

- outbound internet and package egress
- local DNS forwarder/cache
- local DHCP for future service-plane clients
- registry/artifact cache landing zone
- future bridge for non-cluster appliances that should not ride the 100Gb fabrics

## Addressing

- VLAN: `130`
- Subnet: `10.30.0.0/24`
- `5860-proxmox` gateway: `10.30.0.1/24`
- `arista-7060` SVI: `10.30.0.254/24`

## Current design

- `Ethernet33` on the Arista is an access port in VLAN `130`
- `nic0` on `5860-proxmox` is bridged into `vmbr30`
- `vmbr30` carries `10.30.0.1/24`
- `5860-proxmox` NATs `10.30.0.0/24` out `vmbr0`
- dedicated `dnsmasq` systemd unit on `5860-proxmox` serves DHCP and DNS on `vmbr30`
- `arista-7060` exposes `Vlan130` as `10.30.0.254/24` for diagnostics and future routing work

## Current live state

- host-side bridge is configured live on `5860-proxmox`
  - `nic0` MTU `9000`
  - `vmbr30` exists with `10.30.0.1/24`
  - `vmbr30` is bridged to `nic0`
- switch-side config is present live on `arista-7060`
  - `Ethernet33` is an access port in VLAN `130`
  - `Vlan130` is configured as `10.30.0.254/24`
- activation is still incomplete because the physical 10Gb link is currently
  down
  - `5860-proxmox:nic0` shows `NO-CARRIER`
  - `5860-proxmox:vmbr30` is `DOWN`
  - `arista-7060:Vlan130` is `down/lowerlayerdown`
  - `arista-7060:Ethernet33` currently reports `Type 1000BASE-SX`, while
    `5860-proxmox:nic0` is a twisted-pair copper NIC
  - this is now diagnosed as a physical media/transceiver mismatch, not a
    missing host or switch configuration problem

## Preferred next shape

- keep `5860:nic0 <-> Et33` as the documented fallback path
- prefer migrating the 10Gb service edge to:
  - `t560-proxmox:ens6f0` or `ens6f1`
  - `arista-7060:Ethernet34`
- reason:
  - `t560` is the infrastructure/control node
  - `t560` has spare 10G fibre-class ports
  - `Et34` is currently free on the Arista
  - this avoids coupling the service edge to a GPU node

Current hard truth:

- the Arista only shows one clearly free 10G port right now: `Et34`
- so the practical next step is **one clean 10G service edge**, not an assumed
  `2x10G` bonded edge

## DNS behavior

- general upstream: `192.168.3.1`
- lab zone upstream: `10.96.80.85` for `lab.sounio`

Clients on this fabric should use:

- gateway: `10.30.0.1`
- DNS: `10.30.0.1`

## Service control plane on top of `10.30`

The current service plane now has a concrete next layer:

- `registry-cache`
  - official Docker Distribution pull-through caches
  - binds on:
    - `10.30.0.1:5000`
    - `10.100.100.3:5000`
    - `192.168.3.207:5000`
  - companion mirrors:
    - `10.100.100.3:5001` / `192.168.3.207:5001` for `ghcr.io`
    - `10.100.100.3:5002` / `192.168.3.207:5002` for `registry.k8s.io`
- `registry-push`
  - writable OCI registry for lab-built images
  - binds on:
    - `10.30.0.1:5003`
    - `10.100.100.3:5003`
    - `192.168.3.207:5003`
  - intended stable names:
    - `push-registry.svc10g.lab.sounio`
    - `push-registry.lab.sounio`
- `technitium`
  - recursive DNS control plane with web UI
  - DNS backend listens on `127.0.0.1:5353`
  - web UI binds on:
    - `10.30.0.1:5380`
    - `192.168.3.207:5380`
- `netbox`
  - IPAM/source-of-truth control plane
  - web UI binds on:
    - `10.30.0.1:8080`
    - `192.168.3.207:8080`
  - seeded through the ORM for compatibility with NetBox v4 token changes

Assets for this layer:

- `service-fabric-stack.compose.yaml`
- `registry-push.yml`
- `registry-config.yml`
- `netbox.env.example`
- `seed-netbox.py`
- `netbox/seed-lab-foundation-orm.py`
- `netbox/seed-lab-devices-orm.py`
- `verify-netbox.py`
- `verify-technitium.sh`
- `deploy-stack.sh`
- `containerd-dockerhub-mirror-hosts.toml`
- `containerd-lab-push-registry-hosts.toml`
- `containerd-ghcr-mirror-hosts.toml`
- `containerd-registry-k8s-mirror-hosts.toml`
- `apply-containerd-dockerhub-mirror.sh`
- `apply-containerd-lab-push-registry.sh`
- `apply-containerd-registry-mirrors.sh`
- `verify-registry-mirrors.sh`

## Validation

Run the host-side preflight from this repo:

```bash
/home/devsounio/beagle/k8s/sounio-networking/service-fabric-10g/preflight.sh
```

Expected outcome after full activation:

- `vmbr30` exists on `5860-proxmox`
- `nic0` is enslaved to `vmbr30`
- `10.30.0.1/24` is present
- `dnsmasq` is active and bound to `10.30.0.1:53`
- NAT rule exists for `10.30.0.0/24 -> vmbr0`
- `nic0` has carrier
- `Vlan130` is up on the Arista
- the Arista can ping `10.30.0.1`

## Cluster-side mirror usage

For Kubernetes nodes, the intended mirror paths are:

- `docker.io` -> `http://10.100.100.3:5000`
- `ghcr.io` -> `http://10.100.100.3:5001`
- `registry.k8s.io` -> `http://10.100.100.3:5002`

For lab-built images that should stop depending on node-local `localhost/...`,
the intended stable push/pull path is:

- push from the management plane to:
  - `192.168.3.207:5003`
- pull from cluster nodes through:
  - `10.100.100.3:5003`

The template files and rollout helpers are:

- `containerd-dockerhub-mirror-hosts.toml`
- `apply-containerd-dockerhub-mirror.sh`
- `containerd-lab-push-registry-hosts.toml`
- `apply-containerd-lab-push-registry.sh`
- `containerd-ghcr-mirror-hosts.toml`
- `containerd-registry-k8s-mirror-hosts.toml`
- `apply-containerd-registry-mirrors.sh`

## Live validation status

The current service plane has been validated live against the cluster:

- `containerd` on the nodes now reports `configPath=/etc/containerd/certs.d`
- `docker.io` mirror traffic from `r740-proxmox` has been observed on
  `registry-cache-dockerhub`
- `ghcr.io` mirror traffic from `r740-proxmox` has been observed on
  `registry-cache-ghcr`
- `registry.k8s.io` mirror traffic from `r740-proxmox` has been observed on
  `registry-cache-k8s`
- `netbox` is live on:
  - `http://10.30.0.1:8080/`
  - `http://192.168.3.207:8080/`
- `technitium` admin login has been recovered and validated live
- the lab foundation in NetBox includes:
  - site `sounio-lab`
  - VLAN group `sounio-fabrics`
  - VLANs `100`, `130`, `200`, `210`
  - prefixes `10.100.100.0/24`, `10.200.0.0/24`, `10.210.0.0/24`,
    `10.30.0.0/24`, and `192.168.3.0/24`
- the live topology seed in NetBox now also includes:
  - devices `t560-proxmox`, `r770-proxmox`, `r740-proxmox`,
    `5860-proxmox`, and `arista-7060`
  - 9 physical cables between the Arista and the host uplinks
  - host-side logical interfaces for management, underlay, storage,
    GPU fabric, and the 10Gb service plane

Run the mirror proof again with:

```bash
/home/devsounio/beagle/k8s/sounio-networking/service-fabric-10g/verify-registry-mirrors.sh
```

Run the NetBox verification with a valid token, for example:

```bash
export NETBOX_URL=http://192.168.3.207:8080
export NETBOX_API_TOKEN_V2=...token...
/home/devsounio/beagle/k8s/sounio-networking/service-fabric-10g/verify-netbox.py
```

Run the Technitium verification with:

```bash
TECHNITIUM_PASSWORD='...password...' \
/home/devsounio/beagle/k8s/sounio-networking/service-fabric-10g/verify-technitium.sh
```

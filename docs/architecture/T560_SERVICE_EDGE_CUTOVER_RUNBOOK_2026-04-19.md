# T560 Service Edge Cutover Runbook

## Goal

Move the lab's `10Gb` service/egress edge from the currently live
`5860-proxmox <-> Arista Et33` path to a cleaner non-GPU edge on `t560-proxmox`
without breaking:

- internet access for the Ubiquiti management/access network
- the live `10.30.0.0/24` service plane
- registry caches, DNS, NetBox, and package/model acceleration

## Current live state

As of `2026-04-19`, the service/egress fabric is live on:

- `5860-proxmox:nic0`
- `Arista Ethernet33`
- `Vlan130 = 10.30.0.254/24`
- `5860 vmbr30 = 10.30.0.1/24`

Validated services on the live path:

- registry mirrors on `5000-5003`
- Technitium on `5380`
- NetBox on `8080`

This is now a working baseline, not a theoretical backup.

## Target state

### Physical topology

1. upstream `10Gb` handoff lands on `Arista Ethernet34`
2. `Arista Ethernet33` or another dedicated `10Gb` port lands on
   `t560:ens6f0` or `t560:ens6f1`
3. `t560` becomes the real north-south edge host
4. Ubiquiti remains the `1Gb` management/access switch behind the internal side

### Role ownership after cutover

- `Arista`
  - `10Gb` transit/fabric switch only
  - no internet edge policy or NAT ownership
- `t560`
  - default service-edge gateway
  - NAT/router for lab egress if the upstream handoff is L2 transit
  - cache/proxy/DNS anchor
  - upstream provider for the Ubiquiti-side management network
- `Ubiquiti`
  - management/access/legacy distribution
  - not the bottleneck for the `10Gb` upstream

## Interface intent

### T560

- `ens6f0` or `ens6f1`
  - `10Gb` north-south edge uplink inside the Arista domain
- existing management interface
  - remains reachable on the current `192.168.3.0/24` network
- internal bridge/service-plane interface
  - owns the future `10.30.0.1/24` service fabric address after cutover

### 5860

- keep `nic0/vmbr30` live until `t560` has been validated
- after cutover, either:
  - retire `vmbr30` as the primary edge, or
  - keep it as a documented fallback path only

## Preconditions

Do not start the cutover until all of these are true:

1. `Et34` is available for the upstream `10Gb` handoff
2. a matching `10Gb` transceiver/cable path exists for `t560`
3. `t560` has a final interface choice (`ens6f0` or `ens6f1`)
4. current `5860` service-fabric health is green:
   - `Et33 connected 10Gb`
   - `Vlan130 up/up`
   - `10.30.0.1` responds from Arista
   - service endpoints answer on `10.30.0.1`
5. maintenance window exists for default-route or NAT changes

## Cutover sequence

### Phase 1: stage `t560`

1. cable `t560:ens6f0` or `ens6f1` to the chosen Arista `10Gb` port
2. verify carrier and negotiated speed on both ends
3. configure the `t560` service-edge bridge/interface without stealing the
   active `10.30.0.1` identity yet
4. validate L2/L3 reachability between `t560` and `Vlan130`
5. stage cache/proxy/DNS services on `t560` bound to temporary addresses or
   local-only sockets

### Phase 2: stage edge behavior

1. configure `t560` to own WAN-side routing/NAT behavior for the new upstream
2. confirm `t560` can:
   - reach the internet over the `10Gb` handoff
   - resolve DNS
   - pull from upstream registries/package sources
3. keep Ubiquiti and all nodes on the old gateway path during this validation

### Phase 3: service-plane migration

1. move `10.30.0.1/24` ownership from `5860` to `t560`
2. rebind or migrate service-plane listeners:
   - registry mirrors
   - Technitium
   - NetBox
   - any package/model proxy services
3. validate from another node that:
   - `10.30.0.1:5000-5003` answer
   - `10.30.0.1:5380` answers
   - `10.30.0.1:8080` answers

### Phase 4: management-side gateway migration

1. decide whether Ubiquiti receives internet from:
   - `t560` directly, or
   - an existing upstream router/firewall with only cluster high-speed traffic
     moved
2. if `t560` becomes the true upstream for Ubiquiti:
   - point the Ubiquiti-side default route/NAT upstream to `t560`
   - verify management clients retain internet access
3. validate node internet egress still works on the management side

### Phase 5: retire or demote the old edge

1. mark `5860 vmbr30` as fallback-only
2. keep the `Et33` path available until at least one full validation day passes
3. only then decide whether to:
   - repurpose `Et33`
   - keep it as standby

## Validation checklist

### Fabric checks

- `t560` `10Gb` link shows carrier
- Arista interface shows `connected` at the expected speed
- `Vlan130` remains `up/up`

### Service-plane checks

- `curl http://10.30.0.1:5000/v2/`
- `curl http://10.30.0.1:5001/v2/`
- `curl http://10.30.0.1:5002/v2/`
- `curl http://10.30.0.1:5003/v2/`
- `curl http://10.30.0.1:5380/`
- `curl http://10.30.0.1:8080/`

### Internet checks

- `t560` can reach the upstream internet over the new `10Gb` path
- a management client behind the Ubiquiti still has internet access
- at least one cluster node can still pull from upstream package/model sources

## Rollback plan

If anything breaks during Phases 3-4:

1. restore `10.30.0.1/24` to `5860 vmbr30`
2. restore service listeners to the current `5860` edge host
3. restore the previous management-side default-route/NAT path
4. leave the staged `t560` configuration in place but inactive

Because `5860 <-> Et33` is live and validated, rollback is operationally safe as
long as the old path is not dismantled during the same window.

## Notes

- `t560` remains the preferred future edge because it is a non-GPU host and is
  the cleaner HPC role split.
- `5860` is now a valid live edge, so the migration should be deliberate rather
  than urgent.
- Do not promise `2x10G` during this cutover. The current switch inventory only
  supports one cleanly identified next `10Gb` port for this role.

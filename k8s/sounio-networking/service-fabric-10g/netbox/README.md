# NetBox

This is the IPAM and inventory control plane for the lab service edge.

## Endpoints

- `http://10.30.0.1:8080`
- `http://192.168.3.207:8080`
- `http://10.100.100.3:8080`

## Port Truth

The live service-fabric stack publishes NetBox on `8080`.

Earlier helper files used `8081` during an intermediate compose layout, but the
running control plane now uses `8080` consistently across the service fabric.

## Scope

The first live scope is intentionally modest:

- prefixes
- VLANs
- gateway addresses
- physical devices

That is enough to stop relying on memory and scattered notes while the lab
keeps evolving.

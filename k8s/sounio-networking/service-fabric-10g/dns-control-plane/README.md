# DNS Control Plane

This keeps `dnsmasq` as the stable DHCP and port-53 frontend on the 10Gb
service fabric while Technitium provides a better operator-facing DNS control
plane behind it.

## Design

- `dnsmasq` stays on `10.30.0.1:53` for DHCP and stable DNS service
- Technitium listens on `127.0.0.1:5353` for DNS backend duties
- Technitium web UI is exposed on:
  - `http://10.30.0.1:5380`
  - `http://192.168.3.207:5380`
  - `http://10.100.100.3:5380`

## Bootstrap posture

The safe initial posture is:

- keep `dnsmasq` serving DNS exactly as today
- add friendly records for service-plane apps in `dnsmasq`
- bring up Technitium for managed DNS control-plane work
- optionally later point selected zones from `dnsmasq` into Technitium

This avoids breaking working DNS while still giving us a serious DNS console.


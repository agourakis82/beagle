# Lab DNS for `lab.sounio`

This is the lightweight DNS control-plane for the lab fabric.

It is intentionally simple:
- CoreDNS authoritative for `lab.sounio`
- static zone file in git
- no dependency on Kubernetes service discovery for infrastructure names

Use this to make the fabric legible:
- `t560.lab.sounio`
- `r770.lab.sounio`
- `r740.lab.sounio`
- `pve-5860.lab.sounio`
- gateway records for each fabric

This does **not** replace:
- CoreDNS for `cluster.local`
- Tailscale MagicDNS for notebook entry

It gives the lab an internal DNS source of truth that you can later front with:
- the Arista gateway SVIs
- DHCP options
- NetBox-driven zone generation

## Apply

```bash
kubectl apply -k /home/devsounio/beagle/k8s/sounio-networking/lab-dns
```

## Test

```bash
kubectl -n infra get svc lab-dns
kubectl -n infra run -it --rm dns-test --restart=Never --image=busybox:1.36 -- nslookup t560.lab.sounio lab-dns.infra.svc.cluster.local
```

The service is intentionally cluster-internal for now. Promoting it to host or
gateway DNS is a separate operational step.

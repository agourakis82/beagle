# Tailnet Direct Cluster Access

This document describes the safe way to let a personal machine such as the
always-on Mac Pro talk directly to the live Kubernetes control plane.

## Why we are not exposing the API server as a Tailscale `Service`

The Kubernetes API already has a stable worker-safe endpoint:

- `https://k8s-api.darwin.lan:6443`

And that name currently resolves to:

- `k8s-api.darwin.lan -> 10.100.100.2`

The current API certificate and kubeconfig flow are already aligned with that
name. Publishing the API server as a new Tailscale service hostname would
introduce a second identity surface and force certificate/SAN work that we do
not need right now.

So the preferred path is:

1. expose the cluster underlay `10.100.100.0/24` through a Tailnet subnet route
2. keep using `k8s-api.darwin.lan:6443`
3. keep the browser/TCP surfaces (`workspace`, `Grafana`) on Tailscale service
   identities

## Current live state

On `t560-proxmox`:

- management network:
  - `192.168.3.169/24` on `vmbr0`
- Kubernetes underlay:
  - `10.100.100.2/24` on `vmbr100`
- safety rule:
  - `tailscale set --accept-routes=false`
- advertised Tailnet subnet route:
  - `10.100.100.0/24`

Important:

- `accept-routes=false` on `t560` stays in place because the earlier outage was
  caused by importing an overlapping management-LAN route through Tailscale.
- Advertising `10.100.100.0/24` is about letting trusted client machines reach
  the cluster underlay. It must not reintroduce overlapping route import on the
  cluster host itself.

## Recommended client model

The target client for this flow is the always-on Mac Pro.

The intended topology is:

1. the Mac Pro stays online in the Tailnet
2. the Mac Pro accepts the cluster underlay route
3. the Mac Pro has a kubeconfig pointed at `https://k8s-api.darwin.lan:6443`
4. the notebook screen-shares into the Mac Pro when mobility matters

This reduces the number of fragile moving parts on the notebook:

- the notebook no longer needs to be the primary cluster-control surface
- `kubectl`, Grafana, and the VS Code Kubernetes extension can live on the
  Mac Pro directly
- the notebook becomes a visual control surface instead of the place where the
  cluster session must survive

## Mac Pro prerequisites

On the Mac Pro:

1. Tailscale must be installed and logged in
2. subnet routes must be accepted:
   ```bash
   sudo tailscale set --accept-routes=true
   ```
3. the API hostname must resolve locally:
   ```bash
   echo '10.100.100.2 k8s-api.darwin.lan' | sudo tee -a /etc/hosts
   ```
4. a kubeconfig pointed at `https://k8s-api.darwin.lan:6443` must be installed
5. Screen Sharing or Remote Management should be enabled in macOS Sharing
   settings

## Exporting a kubeconfig for a Tailnet client

From `t560-proxmox`, use:

```bash
cd /home/devsounio/beagle/k8s/hpc-sota
./ops/export-tailnet-kubeconfig.sh /tmp/darwin-k8s-admin.kubeconfig
```

That script:

- flattens the current kubeconfig
- rewrites the server to `https://k8s-api.darwin.lan:6443`
- writes an exportable kubeconfig bundle for a trusted Tailnet client

Then copy it securely to the Mac Pro and install it there as `~/.kube/config`.

## Mac Pro bootstrap pack

The canonical Mac Pro control-surface pack lives at:

- `/home/devsounio/macpro-root-pack`

Bootstrap on the Mac Pro with:

```bash
bash ~/macpro-root-pack/bootstrap-macpro.sh
```

The pack installs:

- `darwin-cluster-status`
- `darwin-grafana`
- `darwin-workspace-web`
- `darwin-k8s-host-alias`
- `darwin-kubeconfig-install`
- `darwin-screen-share`

## Screen-sharing model

Recommended daily workflow:

1. leave the Mac Pro logged into Tailscale
2. keep cluster tools and VS Code Kubernetes extension on the Mac Pro
3. from the notebook, use macOS Screen Sharing into the Mac Pro
4. use the notebook only as the visual/interactive surface

This is intentionally different from the remote-workspace model:

- workspace editing remains remote-first in the habitat
- cluster control becomes direct from the Mac Pro
- the notebook stops being the only place where both have to work at once

## Current boundary

What is already live:

- workspace HTTP/SSH through Tailscale services
- Grafana through Tailscale service
- advertised subnet route for `10.100.100.0/24` from `t560`

What may still need explicit admin approval in the tailnet:

- route approval for the advertised subnet route

What is intentionally not done here:

- no new Tailscale service identity for the kube-apiserver
- no blind certificate/SAN changes
- no automatic Screen Sharing enablement on macOS from the cluster side

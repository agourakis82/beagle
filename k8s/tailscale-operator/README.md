# Sounio Tailnet Exposure

This directory is the installation and rollout package for exposing the
`sounio-workspace` workload to the tailnet with the Tailscale Kubernetes
Operator.

Current state in this cluster:
- the Tailscale Operator is installed and joined to the tailnet
- the `tailscale` namespace and CRDs exist
- the Sounio workspace tailnet `Service` resources exist
- the HA ingress `ProxyGroup` exists and its two proxy pods are running
- the workspace exposure is published and currently responds on:
  - `http://sounio-workspace.tail21cbc4.ts.net:8080`
  - `ssh -i /home/devsounio/.ssh/id_ed25519 -p 2222 openvscode-server@sounio-workspace-ssh.tail21cbc4.ts.net`
- Grafana can also be published through the same HA ingress group with:
  - `http://darwin-grafana.tail21cbc4.ts.net`
- the `darwin-platform` namespace quota must allow one Tailscale-backed
  `LoadBalancer`/`NodePort` service for the Grafana publish path, and that
  reapplicable patch lives in `darwin-platform-quota-grafana-tailnet.yaml`

## Known incident pattern: stale Service status after ingress churn

One real failure mode in this cluster is:

- the shared ingress `ProxyGroup` is `Ready`
- the workspace pod and `ClusterIP` services are healthy
- the VIP dataplane still responds on the old workspace VIPs
- but `service/sounio-workspace-tailnet-http` and
  `service/sounio-workspace-tailnet-ssh` fall back to:
  - `TailscaleIngressSvcConfigured=False`
  - `IngressSvcNoBackendsConfigured`
  - empty `.status.loadBalancer.ingress`

When that happens, do not assume the workspace backend is broken first.
Confirm the dataplane before changing the workspace:

```bash
curl -I --max-time 10 http://100.103.74.10:8080
nc -vz -w 5 100.124.91.219 2222
kubectl -n tailscale get proxygroup sounio-workspace-ingress -o yaml
```

If the VIPs are still alive but the two workspace tailnet `Service` objects are
stuck in `IngressSvcNoBackendsConfigured`, the shortest safe repair is to
recreate just those two `Service`s from the repo manifests:

```bash
/home/devsounio/beagle/k8s/hpc-sota/ops/repair-workspace-tailnet-services.sh
```

The script is intentionally narrow:

- it refuses to run unless `sounio-workspace-habitat` is already `Ready`
- it refuses to run unless `proxygroup/sounio-workspace-ingress` is `Ready`
- it only recreates:
  - `beagle/sounio-workspace-tailnet-http`
  - `beagle/sounio-workspace-tailnet-ssh`
- it exits cleanly without mutation when both services are already green

If you need the manual path anyway, it remains:

```bash
kubectl -n beagle delete svc sounio-workspace-tailnet-http sounio-workspace-tailnet-ssh --wait=true
kubectl apply -f /home/devsounio/beagle/k8s/tailscale-operator/sounio-workspace-tailnet-http.yaml \
              -f /home/devsounio/beagle/k8s/tailscale-operator/sounio-workspace-tailnet-ssh.yaml
```

Then verify:

```bash
kubectl -n beagle get svc sounio-workspace-tailnet-http sounio-workspace-tailnet-ssh -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{range .status.conditions[*]}{.type}={.status}({.reason}) {end}{"\t"}{.status.loadBalancer.ingress[0].ip}{"\t"}{.status.loadBalancer.ingress[0].hostname}{"\n"}{end}'
kubectl -n tailscale exec sounio-workspace-ingress-0 -- sh -lc 'cat /etc/tsconfig/sounio-workspace-ingress-0/cap-106.hujson'
```

Healthy end state:

- both workspace tailnet services return `TailscaleIngressSvcConfigured=True`
- the HTTP service advertises:
  - `100.103.74.10`
  - `sounio-workspace.tail21cbc4.ts.net`
- the SSH service advertises:
  - `100.124.91.219`
  - `sounio-workspace-ssh.tail21cbc4.ts.net`
- `AdvertiseServices` on the ingress contains:
  - `svc:sounio-workspace`
  - `svc:sounio-workspace-ssh`

Goal:
- move from node identity to service identity
- keep SSH and HTTP stable across notebook changes
- make the rollout additive and reversible
- keep the repo package aligned with the live cluster state

## Recommended apply order

1. Create the Tailscale tailnet policy entries from
   `tailnet-policy.example.hujson`.
   This is not just `tagOwners`: HA service exposure via `ProxyGroup` also
   needs `autoApprovers.services` so the proxy devices are allowed to advertise
   the workspace service VIPs on the tailnet.
2. Create the operator OAuth client and secret from
   `oauth-secret.example.yaml`.
3. Install the Tailscale Kubernetes Operator with
   `operator-values.example.yaml`.
4. Confirm the operator joins the tailnet and that the CRDs exist.
5. Apply `kustomization.yaml` in this directory to create the quota patch,
   `ProxyClass`, `ProxyGroup`, and tailnet-facing Services.
6. Validate the new tailnet names and confirm browser and SSH access work end
   to end.

## Exact next commands

1. Inspect the current cluster gap:
   ```bash
   /home/devsounio/beagle/k8s/tailscale-operator/preflight.sh
   ```

2. Install the operator with Helm:
   ```bash
   helm repo add tailscale https://pkgs.tailscale.com/helmcharts
   helm repo update
   helm upgrade \
     --install \
     tailscale-operator \
     tailscale/tailscale-operator \
     --namespace=tailscale \
     --create-namespace \
     --set-string oauth.clientId="<OAuth client ID>" \
     --set-string oauth.clientSecret="<OAuth client secret>" \
     --wait
   ```

3. Apply the tailnet exposure resources:
   ```bash
   kubectl apply -k /home/devsounio/beagle/k8s/tailscale-operator
   ```

4. Verify:
   ```bash
   /home/devsounio/beagle/k8s/tailscale-operator/verify-exposure.sh
   ```

## Notes

- The operator is versioned upstream and is safer to install from the official
  Helm chart than to vendor a copy here.
- These resources are additive and do not replace the live workspace until you
  explicitly migrate traffic to them.
- `Service`-based exposure is used for SSH/TCP and HTTP/TCP in this first pass.
- The same ingress `ProxyGroup` can publish more than one stable service
  hostname, so Grafana uses the shared HA ingress path instead of a
  second proxy fleet.
- `ProxyGroup` is included so the rollout can run HA across multiple nodes.
- `ProxyClass` is now part of the package because this cluster requires custom
  tolerations for the proxy pods to schedule.
- The final service publish step depends on `autoApprovers.services` in the
  tailnet policy. Without it, the proxy pods can be healthy while the
  `Service` remains stuck in `IngressSvcNoBackendsConfigured`.
- In the live cluster, both the Sounio workspace and Grafana are now published
  through the shared HA ingress group and respond on their tailnet hostnames.
- The helper scripts in this directory are intentionally read-only verification
  helpers; they do not install credentials or mutate the tailnet policy for you.

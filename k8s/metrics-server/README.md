# Metrics Server

Metrics Server provides the Kubernetes resource metrics API
`metrics.k8s.io`, which is required by HPAs such as
`cloudflare-system/cloudflared-mcp-hpa` and by `kubectl top`.

## Live Contract

- Upstream manifest: Kubernetes SIG Metrics Server `v0.8.1`
- APIService: `v1beta1.metrics.k8s.io`
- Namespace: `kube-system`
- Deployment: `metrics-server`

This lab uses tainted control and compute nodes, so the deployment needs
explicit `NoSchedule` tolerations for:

- `node-role.kubernetes.io/control-plane`
- `sounio.dev/pool`
- `sounio.dev/compute`

The current kubelet serving certificate setup also requires:

```text
--kubelet-insecure-tls
```

Remove that flag only after kubelet serving certificates are trusted by the
aggregated metrics client path.

## Apply

```bash
kubectl apply -k /home/devsounio/beagle/k8s/metrics-server
kubectl -n kube-system rollout status deployment/metrics-server --timeout=180s
kubectl top nodes
kubectl get hpa -A -o wide
```

## Verification Snapshot

Verified on 2026-05-25:

- `v1beta1.metrics.k8s.io` Available=True
- `kubectl top nodes` returns all four cluster nodes
- `cloudflared-mcp-hpa` reports CPU and memory targets instead of `<unknown>`

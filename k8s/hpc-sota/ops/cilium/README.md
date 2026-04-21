# Cilium Node Canaries

This directory holds node-scoped Cilium overrides and repair helpers for
cluster networking investigations.

Current first canary:

- `r740-slurmd-canary.yaml`
- next escalation canary:
  - `r740-slurmd-canary-kpr.yaml`
  - `r740-slurmd-canary-kpr-tunnel.yaml`
- upgrade note:
  - `UPGRADE_1_19_2.md`

Purpose:

- isolate pod-level dataplane failures on `r740-proxmox` without changing the
  whole cluster
- test whether the `slurm-pilot-worker-gpuorangefs` lane recovers when Cilium on
  that node disables selected fast-path features and enables verbose flow debug

Current cluster context:

- cluster is now running `Cilium v1.19.2`
- `r740-proxmox` had shown a node-local pod dataplane failure where ordinary
  pods could not reach `controller/accounting/login`, while host-network probes
  still worked
- `r740-proxmox` resolves its Kubernetes `InternalIP` on bridge `vmbr100`, so
  any per-node `kube-proxy-replacement` canary now pins both
  `devices=vmbr100` and `direct-routing-device=vmbr100` to avoid the agent
  failing device auto-detection on that node
- when testing the native `kube-proxy-replacement` canary on `r740`, keep
  `auto-direct-node-routes=true` so the node still programs remote pod CIDR
  routes like the healthy native-routing workers
- the live base canary on `r740` is:
  - `auto-direct-node-routes=false`
  - `enable-tcx=false`
  - `debug=true`
  - `debug-verbose=flow`
- after the cluster-wide patch upgrade to `1.19.2`, `r740` did recover
  transiently and passed both pod-level reachability and a Slurm smoke once
- a later re-flap put `r740` back into the same class of endpoint failures, so
  it is currently quarantined again from the `gpuorangefs` worker pool
- `r770-proxmox` remains the healthy admitted worker
- the `kpr` and `kpr+tunnel` canaries are still kept here as staged escalation
  artifacts, but they are no longer the active repair path
- if `r740` regresses again, start by re-validating the base canary on
  `1.19.2` before escalating to the `kpr` variants

Canary workflow:

1. apply the node config in `kube-system`:

```bash
kubectl apply -f /home/devsounio/beagle/k8s/hpc-sota/ops/cilium/r740-slurmd-canary.yaml
kubectl -n kube-system delete pod -l k8s-app=cilium \
  --field-selector spec.nodeName=r740-proxmox
```

2. watch Cilium on `r740`:

```bash
kubectl -n kube-system get pods -o wide | rg 'cilium|r740-proxmox'
kubectl -n kube-system logs ds/cilium --since=10m | tail -n 200
```

3. validate from an ordinary pod pinned to `r740`:

```bash
kubectl run -n default r740-netcheck --image=ghcr.io/slinkyproject/slurmd:25.11-ubuntu24.04 \
  --overrides='{"spec":{"nodeSelector":{"kubernetes.io/hostname":"r740-proxmox"}}}' \
  --restart=Never -- sleep 3600
kubectl exec -n default r740-netcheck -- bash -lc 'python3 - <<PY
import socket
for host, port in [("10.96.111.82", 6817), ("10.96.32.209", 6819), ("10.0.0.213", 22)]:
    s = socket.socket()
    s.settimeout(3)
    try:
        s.connect((host, port))
        print(host, port, "OK")
    except Exception as e:
        print(host, port, "FAIL", e)
    finally:
        s.close()
PY'
```

4. if validation passes, re-admit `r740` to the Slurm worker pool:

```bash
/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/68-manage-gpuorangefs-worker.sh \
  r740-proxmox admit
```

5. validate the full workload lane with the unified gate:

```bash
K8S_NODE_NAME=r740-proxmox \
  /home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/66-gpuorangefs-gate.sh
```

5. if validation fails, remove the canary and keep `r740` quarantined:

```bash
kubectl delete -f /home/devsounio/beagle/k8s/hpc-sota/ops/cilium/r740-slurmd-canary.yaml
```

Notes:

- this canary is intentionally node-scoped via `CiliumNodeConfig`
- `CiliumNodeConfig` must live in `kube-system` to be picked up by the agent
- keep `r740` out of the Slurm worker pool until an ordinary pod on that node
  can reliably reach the Slurm controller/accounting/login surfaces
- current durable state:
  - `r770` is admitted
  - `r740` is quarantined pending a clean re-run of the worker gate
- for the current cluster state, prefer the base canary first; only promote to
  `r740-slurmd-canary-kpr.yaml` if the base canary reproduces the failure and
  you want the next node-scoped test before attempting a cluster-wide Cilium
  upgrade
- if `r740-slurmd-canary-kpr.yaml` crashes with the direct-routing-device
  failure, the next candidate is `r740-slurmd-canary-kpr-tunnel.yaml`

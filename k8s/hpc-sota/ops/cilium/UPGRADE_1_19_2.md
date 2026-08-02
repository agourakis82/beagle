# Cilium Upgrade Notes: 1.19.1 -> 1.19.2

Current live status:

- cluster dataplane now reports `Cilium v1.19.2`
- the patch upgrade from `1.19.1` to `1.19.2` is complete
- all live agent pods now run `quay.io/cilium/cilium:v1.19.2`
- the live operator now runs `quay.io/cilium/operator-generic:v1.19.2`

Why this mattered here:

- `r740-proxmox` shows a node-local pod dataplane failure
- the base `r740` per-node canary was useful for narrowing hypotheses, but it
  was not sufficient on `1.19.1`
- the patch upgrade to `1.19.2`, while keeping the base canary active, restored
  ordinary pod connectivity from `r740` to the Slurm controller / accounting /
  login surfaces
- after the real image upgrade, `r740` again passed the full
  `66-gpuorangefs-gate.sh` validation:
  - `cilium-health`
  - ordinary pod netcheck to `kubernetes/controller/accounting/login`
  - Slurm smoke pinned to `gpuorangefs-r740-proxmox`
- `r740` is admitted again today and a real ABIDE smoke pinned to
  `gpuorangefs-r740-proxmox` completed successfully:
  - `job 170`
  - `RUN_ID=brain-ossm-abide-campaign-20260410T091059Z`

Official references:

- `https://docs.cilium.io/en/stable/operations/upgrade/`
- `https://helm.cilium.io/`
- `https://github.com/cilium/cilium/releases`

Important upgrade rule from the official guide:

- when upgrading chart version, do **not** use `--reuse-values`
- instead:
  1. export current values
  2. review / patch them
  3. pass them back explicitly with `-f`

What happened here in practice:

- the release metadata had already been moved to chart/app `1.19.2`
- but the live workload images were still pinned to `v1.19.1`
- so the effective repair was to re-run `helm upgrade` at `1.19.2` while
  explicitly overriding the stale image pins

Backups captured before the real upgrade:

- [`backups/cilium-manifest-pre-actual-1.19.2-upgrade.yaml`](/home/devsounio/beagle/k8s/hpc-sota/ops/cilium/backups/cilium-manifest-pre-actual-1.19.2-upgrade.yaml)
- [`backups/cilium-values-pre-actual-1.19.2-upgrade.yaml`](/home/devsounio/beagle/k8s/hpc-sota/ops/cilium/backups/cilium-values-pre-actual-1.19.2-upgrade.yaml)

Maintenance workflow that was actually used:

```bash
helm upgrade cilium cilium/cilium \
  --version 1.19.2 \
  --namespace kube-system \
  --reuse-values \
  --set image.tag=v1.19.2 \
  --set image.useDigest=false \
  --set operator.image.tag=v1.19.2 \
  --set operator.image.useDigest=false \
  --set preflight.image.tag=v1.19.2 \
  --set preflight.image.useDigest=false \
  --set clustermesh.apiserver.image.tag=v1.19.2 \
  --set clustermesh.apiserver.image.useDigest=false \
  --set cni.exclusive=false
```

Post-upgrade checks:

```bash
kubectl -n kube-system get pods -o wide | egrep '^cilium-|^cilium-envoy'
kubectl -n kube-system logs ds/cilium --since=10m | tail -n 200
kubectl get ciliumnodeconfig -A
kubectl -n kube-system get cm cilium-config -o jsonpath='{.data.cni-exclusive}{"\n"}'
```

For this lab, `cni.exclusive=false` is not optional. GPU fabric workloads use
Multus secondary networks, and Cilium's default exclusive CNI mode renames
`00-multus.conf` to `*.cilium_bak`, silently dropping `net1` from new pods.
After any Cilium rollout, verify that `cni-exclusive=false` and that GPU nodes
still have `/etc/cni/net.d/00-multus.conf`.

`r740` validation gate that passed after the real image upgrade:

1. keep `r740` out of the Slurm worker pool during the rollout
2. rerun the ordinary-pod `r740-netcheck`
3. only if pod-to-service and pod-to-host connectivity recovers, re-admit
   `r740` to `sounio.dev/slurm-worker-gpuorangefs=true`
4. validate with a real Slurm smoke pinned to `gpuorangefs-r740-proxmox`

Current recommendation:

- keep the live cluster on the base `r740` canary
- treat `r740-slurmd-canary-kpr.yaml` and
  `r740-slurmd-canary-kpr-tunnel.yaml` as node-scoped diagnostics, not
  permanent fixes
- treat the `1.19.2` image upgrade as the baseline repair step
- the gate now waits briefly for `cilium-health` to converge across agent
  restarts before failing the node
- if `r740` regresses again, start by re-validating the base canary on
  `1.19.2` before escalating to the `kpr` variants

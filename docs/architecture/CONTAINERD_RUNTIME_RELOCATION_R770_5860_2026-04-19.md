# Containerd Runtime Relocation Runbook (`r770` and `5860`) (2026-04-19)

This runbook captures the real blocker behind the failed GPU-native discussion
lab rollout.

The cluster can now recover its core services (`beagle-core`, `project-cockpit`,
`auth-bridge`, sovereign retrieval), but cold-starting serious GPU-serving
images such as `vllm/vllm-openai:v0.10.2` still trips kubelet
`DiskPressure` on:

- `r770-proxmox`
- `5860-proxmox`

The failure is not model-specific. It is a container runtime placement problem.

## What failed

- `Qwen/Qwen2.5-3B-Instruct` on `5860-proxmox` and `01-ai/Yi-6B-Chat` on
  `r770-proxmox` were converted to `vLLM`.
- The `vllm-openai` image is about `11.4 GiB`.
- Both nodes crossed back into `DiskPressure` during image pull/start.
- Kubelet began evicting pods for `ephemeral-storage`, including:
  - `discussion-lab-serving`
  - `discussion-lab-yi-serving`
- `Yi` was explicitly observed terminating with exit `137` after startup under
  `ephemeral-storage` pressure.
- Once pressure was asserted, kubelet would even reject a tiny privileged
  `busybox` debug pod.

Observed signals:

- `r770-proxmox`
  - `DiskPressure=True`
  - `node.kubernetes.io/disk-pressure:NoSchedule`
- `5860-proxmox`
  - `DiskPressure=True`
  - `node.kubernetes.io/disk-pressure:NoSchedule`

This happened even after byte-level stats recovered, which means kubelet does
not become trustworthy again until the underlying runtime layout is corrected
and the node is allowed to cool off.

## Why this happens

These nodes still treat the root filesystem as the effective container runtime
store. That is acceptable for small images, but it is not acceptable for modern
GPU-native serving stacks.

The cluster already has proper local runtime tiers:

- `r770-proxmox`
  - `/mnt/ai-runtime`
- `5860-proxmox`
  - dedicated non-root local storage must be used for runtime spill instead of
    the small root LV

But `containerd` itself is still effectively landing image/runtime state on
rootfs on both nodes, so every fresh heavy image pull threatens kubelet health.

## Target state

Move `containerd` root and state off the root filesystem:

- `r770-proxmox`
  - target root: `/mnt/ai-runtime/containerd`
  - target state: `/run/containerd` remains runtime state, but persistent image
    content must no longer be backed by `/var/lib/containerd` on root

- `5860-proxmox`
  - target root: a dedicated non-root local runtime tier, for example:
    - `/var/lib/orangefs-lab/containerd` only if that volume is intentionally
      reserved for shared runtime spill
    - or a better dedicated local mount if one exists
  - do **not** leave `containerd` on the small system LV

## Preconditions

Before changing `containerd` on either node:

1. Keep discussion lab deployments scaled to zero:
   - `discussion-lab-serving`
   - `discussion-lab-yi-serving`
2. Confirm the cluster core is healthy enough elsewhere:
   - `beagle-core`
   - `project-cockpit`
   - `auth-bridge`
   - sovereign embeddings/reranker
3. Accept that local images on the node may need to be re-pulled after the
   migration.

## High-level procedure

Perform one node at a time.

### Step 1. Prepare the target path

`r770-proxmox`

```bash
install -d -m 0711 /mnt/ai-runtime/containerd
```

`5860-proxmox`

```bash
install -d -m 0711 /path/to/non-root-runtime-tier/containerd
```

### Step 2. Drain node workloads intentionally

Use the narrowest drain compatible with the node role.

Examples:

```bash
kubectl cordon r770-proxmox
kubectl drain r770-proxmox --ignore-daemonsets --delete-emptydir-data --force
```

For `5860-proxmox`, do the same once no critical lab jobs are running.

### Step 3. Stop kubelet and containerd

On the node:

```bash
systemctl stop kubelet
systemctl stop containerd
```

### Step 4. Move existing containerd data

Preserve the old store first:

```bash
mv /var/lib/containerd /var/lib/containerd.pre-relocation-20260419
```

Then either:

- create a symlink, or
- change `config.toml` so `root = "<new-path>"`

Preferred approach: set explicit `root` in `containerd` config instead of
depending on a symlink.

Example target values:

```toml
root = "/mnt/ai-runtime/containerd"
state = "/run/containerd"
```

If the node uses a generated default config, regenerate intentionally before
editing:

```bash
containerd config default > /etc/containerd/config.toml
```

Then re-apply any existing mirror/registry config assumptions already used in
this cluster.

### Step 5. Start services

```bash
systemctl daemon-reload
systemctl start containerd
systemctl start kubelet
```

### Step 6. Validate on the host

```bash
systemctl is-active containerd
systemctl is-active kubelet
ctr -n k8s.io images ls | head
```

Also verify the new root path is being used:

```bash
du -sh /mnt/ai-runtime/containerd
du -sh /var/lib/containerd || true
```

### Step 7. Validate from Kubernetes

Wait for:

- `NodeHasNoDiskPressure`
- no `node.kubernetes.io/disk-pressure` taint

Then verify via kubelet summary:

```bash
kubectl get --raw /api/v1/nodes/r770-proxmox/proxy/stats/summary
kubectl get --raw /api/v1/nodes/5860-proxmox/proxy/stats/summary
```

Expected outcome:

- `fs.availableBytes` remains comfortably above threshold
- `imageFs.usedBytes` can grow without dragging root below kubelet thresholds

### Step 8. Uncordon and reintroduce workloads gradually

```bash
kubectl uncordon r770-proxmox
```

Then bring back only one heavy GPU-native lane at a time:

1. `discussion-lab-yi-serving` on `r770`
2. validate image pull, start, readiness, and `/v1/models`
3. only after success, repeat the same process on `5860`
4. then bring back `discussion-lab-serving`

## Rollback

If the node fails to recover cleanly:

1. stop `kubelet` and `containerd`
2. restore `/var/lib/containerd` from the preserved backup
3. revert `config.toml`
4. restart `containerd` and `kubelet`

Example:

```bash
systemctl stop kubelet
systemctl stop containerd
rm -rf /var/lib/containerd
mv /var/lib/containerd.pre-relocation-20260419 /var/lib/containerd
# restore previous config.toml
systemctl start containerd
systemctl start kubelet
```

## Success criteria

The relocation is successful only when all of the following are true:

1. `r770-proxmox` and `5860-proxmox` stay `DiskPressure=False`
2. the `node.kubernetes.io/disk-pressure` taint does not return during a cold
   `vllm-openai` pull
3. `discussion-lab-yi-serving` reaches `Running` and serves `/v1/models`
4. `discussion-lab-serving` reaches `Running` and serves `/v1/models`
5. the cluster core remains healthy while these image pulls happen

## What not to do

- Do not treat the temporary `hostUsers + privileged` pod posture as the final
  production runtime answer.
- Do not move `beagle-core` or `project-cockpit` onto the GPU nodes to work
  around this; that would confuse the architectural boundary again.

## Current truth

As of this note:

- `r770-proxmox`
  - `containerd` root is relocated to `/mnt/ai-runtime/containerd`
  - `discussion-lab-yi-serving` is live and serves `/v1/models`
- `5860-proxmox`
  - `containerd` root is relocated to `/var/lib/containerd-runtime` on a
    dedicated thin-LV runtime tier
  - `discussion-lab-serving` is live and serves `/v1/models`
- the original node-storage blocker is resolved on both discussion-lab GPU
  nodes
- the remaining runtime constraint is now narrower and explicit:
  - the current NVIDIA/container isolation path still requires `hostUsers: true`
    plus `privileged: true` for these `vLLM` pods because standard isolated pods
    deny `socketpair()` and fail CUDA initialization

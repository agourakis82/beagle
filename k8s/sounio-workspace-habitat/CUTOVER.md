# Habitat Cutover Runbook

This runbook is the safe migration path that moved the Sounio workspace from
the legacy controller path to the node-agnostic `StatefulSet`
`sounio-workspace-habitat`.

## Preconditions

- The stable `Service/sounio-workspace` remains healthy and reachable.
- The habitat manifests in this directory have already been reviewed.
- The new `StorageClass` `ceph-rbd-ssd-rwop` exists.
- Tailscale Operator exposure is ready if you plan to cut identity over during
  the same window.
- You have an interactive validation checklist ready: shell, `gh auth status`,
  `codex`, `claude`, `kimi`, `docker`, and `/workspace/sounio`.

## Naming

- Current PVC: `sounio-workspace-data`
- Habitat StatefulSet: `sounio-workspace-habitat`
- Habitat PVC after first create: `workspace-data-sounio-workspace-habitat-0`

## Safe Order

1. Apply the habitat manifests.
2. Wait for the new PVC `workspace-data-sounio-workspace-habitat-0` to exist.
3. Scale the habitat down to zero so it releases the new claim:
   ```bash
   kubectl -n beagle scale statefulset sounio-workspace-habitat --replicas=0
   kubectl -n beagle rollout status statefulset/sounio-workspace-habitat
   ```
4. If the legacy `Deployment/sounio-workspace` still exists, scale it down to
   zero so it releases the old claim:
   ```bash
   kubectl -n beagle scale deployment sounio-workspace --replicas=0
   kubectl -n beagle rollout status deployment/sounio-workspace
   ```
5. Run the seed Job in [seed-workspace-data-job.yaml](/home/devsounio/beagle/k8s/sounio-workspace-habitat/seed-workspace-data-job.yaml).
6. Verify the seed Job completed successfully.
7. Scale the habitat back to one replica:
   ```bash
   kubectl -n beagle scale statefulset sounio-workspace-habitat --replicas=1
   kubectl -n beagle rollout status statefulset/sounio-workspace-habitat
   ```
8. Validate the habitat pod interactively.
9. Switch the stable in-cluster service selector:
   ```bash
   /home/devsounio/beagle/k8s/sounio-workspace-habitat/cutover.sh switch-service
   ```
10. Switch Tailscale exposure and any remaining internal references to the habitat service.
11. Only after validation passes, leave the old `Deployment` retired. In the
    current cluster, that retirement has already happened.

## Rollback

If the habitat pod does not validate:

1. Move exposure back to the old workspace service only if the legacy
   `Deployment/sounio-workspace` still exists.
2. Patch the stable in-cluster service back to the old selector:
   ```bash
   /home/devsounio/beagle/k8s/sounio-workspace-habitat/cutover.sh rollback-service
   ```
3. Scale the habitat down to zero.
4. Scale the old `Deployment` back to one replica if it still exists.
5. Investigate before touching either PVC.

## Cluster-specific storage note

This cluster's Ceph CSI reports `topologyKeys: null` on every `CSINode`, so the
original `WaitForFirstConsumer` variant cannot provision successfully here.

The operational habitat baseline for this cluster is therefore:

- `ReadWriteOncePod`
- `Immediate`
- storage class `ceph-rbd-ssd-rwop`

## Current live state

Today the live path is already:

- stable service: `Service/sounio-workspace`
- live controller: `StatefulSet/sounio-workspace-habitat`
- live PVC: `workspace-data-sounio-workspace-habitat-0`
- retained rollback PVC: `sounio-workspace-data`

# Workspace Cutover To Local Storage

This directory moves the critical `BEAGLE + SOUNIO` data path off Ceph-backed
workspace PVCs and onto the local `zfast` tier on `t560-proxmox`.

## Why this exists

- The live workspaces are small enough to evacuate safely.
- `t560` already hosts the live workspace pods.
- `zfast` has enough free capacity and stays outside the Ceph blast radius
  while we redesign the wider storage fabric.

## Storage model

- `beagle-core` state: local PV on `/zfast/workspaces/live/beagle-core`
- `beagle-workspace`: local PV on `/zfast/workspaces/live/beagle-workspace`
- `sounio-workspace`: local PV on `/zfast/workspaces/live/sounio-workspace`

All three are pinned to `t560-proxmox` through local PersistentVolumes.

## Safe order

1. Seed `/zfast/workspaces/live/*` from the evacuation copies.
2. Apply the local storage objects in this directory.
3. Validate the `zfast` canary pod.
4. Quiesce the old Ceph-backed workspace controllers.
5. Patch `beagle-core` to use the new local PVC.
6. Bring up `beagle-workspace-local` and `sounio-workspace-local`.
7. Patch the stable Services to target the local controllers.
8. Run `compare-old-vs-local.sh` and confirm there is nothing `only-in-old`.
9. Validate shell, IDE, SSH, `/workspace/*`, and `beagle-core`.

Before step 4, run `seed-from-live.sh` to capture a fresh delta from the live
pods into `/zfast/workspaces/live/*`.

## Scripts

- `seed-from-live.sh`: sync a last-minute delta from the live Ceph-backed pods
  into `/zfast/workspaces/live/*`
- `compare-old-vs-local.sh`: mounts both the old and new PVCs in a throwaway pod
  and reports:
  - actual and apparent size
  - file counts
  - `only-in-old`
  - `only-in-new`
  - per-file size deltas
- `verify-local-storage.sh`: quick view of PV/PVC/pod state after the cutover
- `cutover.sh cleanup-ephemeral`: removes temporary canary/reconcile/compare pods

## Notes from the first live cutover

- `beagle-core` must be changed with `kubectl patch --type=merge --patch-file`,
  not `kubectl apply`, because `deployment-beagle-core-local-patch.yaml` is a
  patch fragment rather than a full Deployment manifest.
- A smaller `du` value on `zfast` does not automatically mean missing data.
  Compare old vs new explicitly before declaring victory, because compression and
  the creation of new runtime log files can both change the raw size profile.

## Rollback

- Keep the Ceph PVCs intact.
- Scale the `*-local` Deployments down.
- Patch the Services back to the old selectors.
- Scale the old controllers back up.

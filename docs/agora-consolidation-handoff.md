# HANDOFF — "## Agora" Companion-Consciousness Consolidation

Date: 2026-06-28
Scope: Give the companion grounded awareness of what it shows the user (Kp/Dst, body, sky) by consolidating live signals into a `## Agora` context, with matching iOS detail surfaces.

---

## Delivered (live + verified)

**Server**
- physiome `0.3.0` + cockpit `reconcile-1f3a1ba5` deployed.
- Companion knows live **Kp / Dst** in chat (no longer the strip-vs-prompt mismatch).
- `/api/mobile/v1/space-weather` and `/agora-history` endpoints live.
- **Dst** recorded via the `kyoto-dst` poller.

**iOS**
- Harvested onto the **Mac canonical** tree, compiles, and **INSTALLED on iPhone** (`dev.sounio.cockpit`).
- **Agora detail screen**: sky / ambiente / corpo + trends.
- **HRV** shows (via history fallback).
- **Barometer PRESSURE** now flows after the `WeatherSyncEngine` `@MainActor` location fix.

---

## Known gap

**WeatherKit temp/humidity: JWT auth fails** (`WDSJWTAuthenticatorServiceListener Code=2`).
- Entitlement + provisioning are **correct** → the failure is **Apple-service-side**, most likely the simulated **2026 clock vs real-time servers**.
- **Not code-fixable.**
- **Pressure (barometer)** and **HRV/sky** are **unaffected** — only WeatherKit temp/humidity is missing.

---

## Closed this cycle (from the workflow)

- **Mac iOS commit:** ✅ DONE (after the Mac came back online). Commit `87756a4e` on `integration/ios-physiome-merge`
  (9 harvest files, NOT pushed). Note: committing needs git-lfs on PATH — run with `export PATH=/opt/homebrew/bin:$PATH`
  over ssh (the repo has lfs filters for splat/ply assets; non-interactive ssh PATH lacks git-lfs → "remote end hung up").

- **t560 manifest commit:** Committed. Not pushed. `deployment.yaml` untouched; no other dirty/untracked files staged.
  - SHA: `f393bcb75a1d39cbcd93c2f0227c8da216a4f36a`
  - Branch: `reconcile/unify-beagle`
  - Files committed (2):
    - `k8s/physiome/build-job.yaml` (+4 / -2)
    - `k8s/project-cockpit/build-job.yaml` (+19 / -6)

---

## Open (need the user / next session)

- **NONE blocking.** Decision (2026-06-29): **t560 is the official cockpit home** — it has ~3x r770's disk
  (286G vs chronically-full 94G) and the cockpit is a light Node proxy. Committed in `deployment.yaml`
  (`243e292e`): hard role-pin to infra-control + control-plane toleration + Unconfined. The r770
  disk-cleanup + move-back chore is **RETIRED** (r770's full disk is still a latent cluster-hygiene issue,
  but no longer on this arc's critical path; old runbook kept below for reference if you ever rehome).

### Done in the closeout (2026-06-29)
- ✅ Mac iOS harvest committed + **pushed**: `87756a4e` → `integration/ios-physiome-merge`.
- ✅ t560 manifests committed + **pushed**: `f393bcb7` (build-jobs) + `236ce422` (CODEOWNERS + iOS branch guard) → `reconcile/unify-beagle`.
- ✅ t560 orphan iOS cruft cleaned (deleted parallel `SpaceWeather.swift` + `AgoraDetailView.swift`, reverted 8 superseded edits).
- ✅ Anti-divergence guard live: `.github/CODEOWNERS` + `.github/workflows/ios-branch-guard.yml` (fails any `beagle-ios/**` change pushed to `reconcile/unify-beagle`).

---

## Reconciliation recommendation

Mac was unreachable, but the canonical branch `integration/ios-physiome-merge` is mirrored locally on t560, giving direct ground-truth comparison. Findings below.

**RECONCILIATION RECOMMENDATION — iOS (SpaceWeather/Aurora)**

(a) **Source of truth:** `integration/ios-physiome-merge` is canonical for iOS. It carries `SpaceWeatherStore.swift` + `AuroraPresence.swift`, builds/installs, and holds 26 of its 33 commits touching `beagle-ios/`. `reconcile/unify-beagle` is ahead only on non-iOS work (17 commits, ZERO touch `beagle-ios/`) — so it is truth for platform/backend, never for iOS.

(b) **t560's parallel `SpaceWeather.swift`:** it is UNTRACKED (`??`) working-tree cruft — never committed on any branch (reconcile's committed tree has no SpaceWeather file at all). Delete it (and the matching uncommitted iOS edits in BeagleClient/ConversationStore/etc.). Do NOT merge it back; its `SpaceWeatherStore/SpaceWeatherSnapshot/SkyBand` are superseded by canonical's `SpaceWeatherStore`+`AuroraPresence`. To re-sync t560, check out `integration/ios-physiome-merge` for the iOS tree rather than reconciling file-by-file.

(c) **Drift risk: HIGH** — two machines, two branches, an orphan untracked file already proves it. Guardrail (one line): `beagle-ios/**` is owned exclusively by `integration/ios-physiome-merge`; no other branch edits iOS — enforce via CODEOWNERS + a CI check that fails any non-physiome branch touching `beagle-ios/`.

**Key paths:** stale orphan `/home/devsounio/beagle/beagle-ios/BeagleSuite/Sources/BeagleCore/SpaceWeather.swift` (untracked); canonical `/home/devsounio/beagle/beagle-ios/BeagleSuite/Sources/BeagleCore/SpaceWeatherStore.swift` and `.../BeagleCockpit/Companion/AuroraPresence.swift` (on `integration/ios-physiome-merge`). Merge-base `9dd1db55`.

---

## r770 runbook

# r770 Recovery Runbook — Free Disk, Then Move Cockpit Home

**Context:** r770's root SSH is key-blocked from our env. Run Part 1 from the **Proxmox console** (or root SSH if you have a working session). Part 2 (`kubectl`) can run from any machine with cluster admin context. Reachable at `10.100.100.1`.

> Do Part 1 first. Do **not** start Part 2 until `df -h /` on r770 shows healthy free space.

---

### Part 1 — Free r770's disk (node-level, on r770)

The kubelet can't `mkdir` pod dirs even though k8s reports `DiskPressure=False`. `kubectl`-level pod deletion did **not** free the underlying filesystem — the space is held by containerd image/snapshot layers, orphaned kubelet dirs, and journald logs. These must be reclaimed at the node level.

#### 1.1 Confirm the problem and find big consumers

```bash
# Overall root fs usage (kubelet + containerd usually live on /)
df -h /
df -h /var/lib/kubelet /var/lib/containerd

# inode exhaustion can also cause "can't mkdir" with space free
df -ih /

# Top-level breakdown of the two suspects (depth 1, sorted)
du -xh -d1 /var/lib/containerd 2>/dev/null | sort -rh | head -20
du -xh -d1 /var/lib/kubelet    2>/dev/null | sort -rh | head -20

# Biggest single directories anywhere under the two trees
du -xh /var/lib/containerd /var/lib/kubelet 2>/dev/null | sort -rh | head -30

# Journald footprint
journalctl --disk-usage
```

> Note `-x` (stay on one filesystem) so you measure the actual full fs and don't wander into mounts.

#### 1.2 Reclaim containerd image space (usually the biggest win)

```bash
# What images exist and their sizes
crictl images

# Prune all images NOT referenced by a running container
crictl rmi --prune

# Re-check
crictl images
df -h /var/lib/containerd
```

If `crictl` isn't on PATH, it's typically at `/usr/local/bin/crictl` or `/usr/bin/crictl`. If it errors on the endpoint, prefix with:
`crictl --runtime-endpoint unix:///run/containerd/containerd.sock ...`

#### 1.3 Vacuum journald logs

```bash
journalctl --vacuum-size=200M
journalctl --disk-usage   # confirm it dropped to ~200M
```

#### 1.4 Optional — clean stopped containers and dangling pod dirs

```bash
# Remove exited/dead containers (frees their writable layers)
crictl ps -a --state Exited -q | xargs -r crictl rm
crictl ps -a --state Unknown -q | xargs -r crictl rm

# Orphaned emptyDir / pod volume dirs left behind after pod deletion
du -xh -d1 /var/lib/kubelet/pods 2>/dev/null | sort -rh | head -20
```

> Do **not** manually `rm -rf` under `/var/lib/kubelet/pods/<uid>` for pods the kubelet still tracks — let the kubelet GC them. Only consider manual removal for UIDs that no longer correspond to any pod (cross-check with `crictl pods`), and only if space is still critical.

#### 1.5 If still full — restart kubelet so it re-runs GC

```bash
systemctl restart kubelet
journalctl -u kubelet -n 50 --no-pager   # watch for "mkdir" / image GC errors clearing
```

#### 1.6 Confirm space recovered

```bash
df -h /
df -ih /                      # inodes too
crictl images | wc -l         # fewer images
```

**Gate for Part 2:** root fs should have comfortable headroom (target well under ~80% used, and several GB free) before scheduling the cockpit back. Note the free figure from `df -h /` and proceed.

---

### Part 2 — Move project-cockpit back to r770

The `project-cockpit` Deployment (namespace `beagle`) was temporarily live-patched to run on **t560** while r770 was full:

- `nodeSelector: sounio.dev/runtime-role=infra-control` (t560)
- added a control-plane toleration
- seccomp/AppArmor set to `Unconfined`
- its Ceph-RBD **RWO** `VolumeAttachment` was force-deleted to detach from r770

We now revert the scheduling so it lands on **r770** with the RBD volume reattached.

> Deployment strategy is **Recreate** → the old pod is killed before the new one starts → **brief downtime** is expected. The RWO PVC requires the old pod to be fully gone before r770 can attach the volume.
>
> Confirm Part 1 left r770 with free space **before** running these steps.

#### 2.1 Capture current state (rollback safety)

```bash
kubectl -n beagle get deploy project-cockpit -o yaml > /tmp/project-cockpit.preretarget.$(date +%s).yaml

kubectl -n beagle get deploy project-cockpit \
  -o jsonpath='{.spec.template.spec.nodeSelector}{"\n"}{.spec.template.spec.tolerations}{"\n"}'
```

#### 2.2 Revert nodeSelector back to r770

This replaces the whole `nodeSelector` map (removes the `sounio.dev/runtime-role=infra-control` entry and pins to r770 by hostname):

```bash
kubectl -n beagle patch deploy project-cockpit --type=merge -p \
'{"spec":{"template":{"spec":{"nodeSelector":{"kubernetes.io/hostname":"r770-proxmox"}}}}}'
```

> Confirm `r770-proxmox` is the exact node name: `kubectl get nodes` — adjust if it differs.

#### 2.3 Drop the control-plane toleration

A strategic-merge patch will **not** remove a list element, so clear tolerations explicitly. If the cockpit needs no special tolerations on r770 (a worker), set it to empty:

```bash
kubectl -n beagle patch deploy project-cockpit --type=json -p \
'[{"op":"remove","path":"/spec/template/spec/tolerations"}]'
```

If that path errors (tolerations already absent) or you want to keep other tolerations, inspect first:

```bash
kubectl -n beagle get deploy project-cockpit \
  -o jsonpath='{range .spec.template.spec.tolerations[*]}{.key}{" "}{.operator}{" "}{.effect}{"\n"}{end}'
```

…then remove only the control-plane entry by its index, e.g.:
`[{"op":"remove","path":"/spec/template/spec/tolerations/<index>"}]`

> The seccomp/AppArmor `Unconfined` setting can be left as-is — it's harmless on r770 and not blocking. Only revert it if your security baseline requires the default profile; if so, edit `securityContext` in the same Deployment.

#### 2.4 Trigger the Recreate rollout

The patches above already roll the Deployment. To force a clean restart (and ensure the t560 pod is terminated so the RWO volume can detach):

```bash
kubectl -n beagle rollout restart deploy project-cockpit
kubectl -n beagle rollout status  deploy project-cockpit --timeout=180s
```

#### 2.5 Verify pod is on r770 with the volume attached

```bash
# Pod should be Running on r770
kubectl -n beagle get pods -l app=project-cockpit -o wide
# (adjust label selector if the deployment uses a different label;
#  derive it from: kubectl -n beagle get deploy project-cockpit -o jsonpath='{.spec.selector.matchLabels}')

# No leftover pod on t560
kubectl -n beagle get pods -o wide | grep -i cockpit

# Volume reattached to r770 (a fresh VolumeAttachment bound to the r770 node)
kubectl get volumeattachment | grep -i r770

# PVC is Bound and mount succeeded (no FailedAttachVolume / Multi-Attach events)
kubectl -n beagle describe pod -l app=project-cockpit | sed -n '/Events:/,$p'
```

**Success criteria:**
- Pod `project-cockpit-*` is `Running` and `READY 1/1` on node **r770-proxmox**.
- No cockpit pod remains on t560.
- A `VolumeAttachment` for the cockpit PVC is bound to r770; pod `Events` show no `Multi-Attach` or `FailedAttachVolume`.

#### 2.6 If the volume won't attach (stuck Multi-Attach / old VA lingering)

The RWO volume can't bind to r770 while any attachment/pod on t560 still references it.

```bash
# Ensure no cockpit pod is left anywhere
kubectl -n beagle get pods -o wide | grep -i cockpit

# Find a VolumeAttachment still bound to t560 for this PV
kubectl get volumeattachment -o wide | grep -i cockpit   # or match by PV name from the PVC

# Identify the PV behind the cockpit PVC
kubectl -n beagle get pvc | grep -i cockpit
```

If a stale VolumeAttachment to t560 persists after the t560 pod is gone, force-delete **only** that attachment (same remedy used to move it originally):

```bash
kubectl delete volumeattachment <stale-va-name>
```

Then re-run `kubectl -n beagle rollout restart deploy project-cockpit` and repeat the 2.5 verification.

#### Rollback

If anything goes wrong, re-apply the saved spec:

```bash
kubectl -n beagle apply -f /tmp/project-cockpit.preretarget.<timestamp>.yaml
```

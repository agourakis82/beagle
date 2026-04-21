# Sounio Workspace Habitat (vNext)

This directory is the node-agnostic workspace design intended to replace the
current node-pinned `Deployment`.

Key changes:
- `StatefulSet` instead of `Deployment`
- stable identity via a headless service
- `ReadWriteOncePod` instead of `ReadWriteOnce`
- cluster-correct `Immediate` storage binding for the current Ceph CSI setup
- worker placement instead of hard pinning to `t560-proxmox`

Why this is shipped as a parallel vNext:
- the current workspace is live and backed by a migrated persistent home/repo
- changing the controller and PVC semantics in-place is a cutover, not a
  patch-level edit
- these manifests are meant for a deliberate migration window

Preflight checklist:
- keep the current workspace running until the habitat pod is `Ready`
- install and validate the Tailscale Operator CRDs before applying the
  Tailscale exposure manifests
- confirm the new `ceph-rbd-ssd-rwop` StorageClass exists before creating the
  habitat PVC
- seed the current `/workspace` data into the new PVC before the first cutover
- do not delete or rebind the old workspace PVC until the habitat pod has been
  verified interactively

Storage note:
- the first draft used `WaitForFirstConsumer`, which is a good default in many
  clusters, but this cluster's Ceph CSI reports `topologyKeys: null` on every
  `CSINode`
- that makes `WaitForFirstConsumer` fail during provisioning here
- the corrected habitat default is therefore `ReadWriteOncePod` plus
  `Immediate`, which still preserves single-writer semantics while matching the
  actual CSI behavior of this cluster

Current placement note:
- the habitat is presently steered toward the validated worker pair:
  - `r740-proxmox`
  - `r770-proxmox`
- it still prefers `r740-proxmox` first
- this is still intentional operationally, but no longer because of
  `localhost/...` image refs
- the live habitat now pulls from the lab push registry, so the worker pair is
  a preference/failover lane rather than a node-local image requirement

Current preload path:
- use [preload-active-habitat-images.sh](preload-active-habitat-images.sh) to
  push the habitat's current `localhost/...` images onto the target worker
- for more generic cases, use
  [../workspace-platform/scripts/preload-node-local-images.sh](/home/devsounio/beagle/k8s/workspace-platform/scripts/preload-node-local-images.sh)
- this replaces the old manual `loader pod + kubectl cp + chroot ctr import`
  sequence with one scriptable workflow
- the new boring path is now:
  - publish the workspace images to `192.168.3.207:5003`
  - let containerd on the validated workers pull from the lab registry
  - keep affinity as worker preference, not a hard image-local requirement

Safe cutover order:
1. Install the Tailscale Operator and create the OAuth secret it expects.
2. Apply the habitat `StorageClass`, `Service`s, and `StatefulSet`.
3. Seed the new PVC from the existing workspace data.
4. Wait for `sounio-workspace-habitat-0` to become `Ready`.
5. Switch the tailnet exposure and any internal references from
   `sounio-workspace` to `sounio-workspace-habitat`.
6. Verify shell access, Git auth, and `/workspace` contents in the habitat pod.
7. Retire the old `Deployment` only after the new pod passes validation.

Rollback rule:
- if the habitat pod fails validation, move the tailnet exposure back to the
  old workspace service first, then scale the habitat to zero and investigate
  before deleting any persisted data.

Supporting files:
- [CUTOVER.md](CUTOVER.md)
- [seed-workspace-data-job.yaml](seed-workspace-data-job.yaml)
- [preflight.sh](preflight.sh)
- [cutover.sh](cutover.sh)

Current hardening focus:
- the shared bootstrap now treats an existing Git checkout on the PVC as the
  source of truth on restart and only attempts `fetch/checkout/pull` when
  `BEAGLE_WORKSPACE_ALLOW_GIT_SYNC_ON_BOOT=true` is set explicitly
- the IDE bootstrap now recreates the persistent-home shell skeleton before
  linking `/home/openvscode-server`, so restarts do not depend on the SSH
  sidecar racing first
- context/bootstrap files are written atomically to avoid partial JSON/env
  state during crash-loop or node restart
- the SSH sidecar waits for projected `authorized_keys`, publishes a real
  listening-port startup signal, and no longer recursively `chown`s the entire
  persistent home on every restart
- the habitat and legacy templates now use `startupProbe` plus explicit SSH
  liveness so a slow warm start is tolerated while a dead sidecar still gets
  restarted
- the IDE image now includes the Chrome runtime dependencies needed by
  `agent-browser`, so browser automation can run from inside the persistent
  habitat and reopen the cockpit after reconnects

## VSIX note

Because the habitat IDE lane already runs `openvscode-server`, this surface is
the natural place to support `VSIX` in the platform.

The intended model is:

- sovereign cockpit for project continuity
- `openvscode-server` for extension hosting
- persistent habitat home for extension durability

Reference:

- [SOVEREIGN_VSIX_ARCHITECTURE.md](/home/devsounio/beagle/k8s/hpc-sota/SOVEREIGN_VSIX_ARCHITECTURE.md)
- [SOVEREIGN_VSIX_EXTENSION_MATRIX.md](/home/devsounio/beagle/k8s/hpc-sota/SOVEREIGN_VSIX_EXTENSION_MATRIX.md)

Current `sounio` substrate truth:

- required:
  - `eamodio.gitlens`
  - `GitHub.vscode-pull-request-github`
  - `redhat.vscode-yaml`
  - `ms-python.python`
  - `ms-toolsai.jupyter`
  - `rust-lang.rust-analyzer`
  - `llvm-vs-code-extensions.vscode-clangd`
- recommended:
  - `EditorConfig.EditorConfig`
  - `tamasfe.even-better-toml`
  - `ms-vscode.makefile-tools`
  - `yzhang.markdown-all-in-one`
  - `ms-vscode.cpptools`
  - `ocamllabs.ocaml-platform`
  - `leanprover.lean4`

This is deliberate. The sovereign cockpit should report the IDE lane as it
actually behaves in the live habitat, not as an aspirational pack definition.

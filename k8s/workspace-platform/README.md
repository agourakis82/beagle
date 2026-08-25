# Workspace Platform

This directory turns the `sounio-workspace-habitat` pattern into a reusable
multi-project platform.

The model is:
- one persistent workspace habitat per active project
- one PVC per project
- one stable in-cluster service per project
- optional tailnet exposure per project
- shared CPU/GPU runner pools for heavy compute

Machine-level posture policy:

- [/home/devsounio/projects/PROJECT_POSTURE_POLICY.md](/home/devsounio/projects/PROJECT_POSTURE_POLICY.md)

Mission-control rule:

- this platform is the habitat layer for sovereign project surfaces
- it is not the place to redefine machine-level project authority
- it must preserve the distinction between:
  - project posture
  - cluster truth
  - research operations
  - workspace habitat continuity

That means we do **not** need 21 hand-maintained snowflakes for 21 GitHub
projects. We need one good habitat template and a small renderer.

## What lives here

- `templates/project-workspace.yaml.tmpl`
  - parameterized habitat template
- `scripts/render-project-workspace.sh`
  - renders a concrete manifest from environment variables
- `examples/project.env.example`
  - minimal input contract for a new project workspace
- `sounio-obligation-guardian.yaml`
  - Pod-external guardian for Sounio's durable-obligation control service
- `sounio-fleet-guardian.yaml`
  - start-only desired-lane recovery using bounded fleet authority

## Sounio control-plane continuity

`sounio-obligation-guardian.yaml` is deliberately separate from the legacy
`sounio-loomd` ensure CronJob. The legacy daemon publishes exact lane state for
the cockpit and still owns supervised Codex processes. The obligation guardian
owns only the durable-work control service introduced by the shared Sounio
runtime.

The guardian runs outside the workspace Pod and calls
`obligation-supervisor-ensure` through `pods/exec` every five seconds. The inner
Sounio command owns locking, PID/start-tick validation, executable custody,
bundle upgrade, and duplicate suppression. The outer Deployment owns Pod-loss
recovery and readiness. Neither layer creates or inspects a tmux session.

`sounio-fleet-guardian.yaml` extends that boundary to the lane catalog. It runs
one recovery cycle every five seconds against the persistent four-slot catalog
and the existing Fable-1 recovery budget. The runtime may restore an enabled
missing Fable generation, but recovery mode holds all newly planned stop actions
and all unbudgeted starts. This is intentional during migration: legacy active
lanes remain visible without giving the unattended Deployment authority to stop
them. The additive `sounio-lanes-ensure` CronJob remains the wider fleet fallback
until those lanes have individual persistent-catalog receipts.

Validate and apply only after the referenced Sounio runtime capability is live:

```bash
kubectl apply --dry-run=server \
  -f k8s/workspace-platform/sounio-obligation-guardian.yaml
kubectl apply -f k8s/workspace-platform/sounio-obligation-guardian.yaml
kubectl -n beagle rollout status deployment/sounio-obligation-guardian

kubectl apply --dry-run=server \
  -f k8s/workspace-platform/sounio-fleet-guardian.yaml
kubectl apply -f k8s/workspace-platform/sounio-fleet-guardian.yaml
kubectl -n beagle rollout status deployment/sounio-fleet-guardian
```

## Quick start

```bash
cp /home/devsounio/beagle/k8s/workspace-platform/examples/project.env.example /tmp/myproj.env
$EDITOR /tmp/myproj.env
/home/devsounio/beagle/k8s/workspace-platform/scripts/render-project-workspace.sh --validate-live /tmp/myproj.env > /tmp/myproj-workspace.yaml
```

Then inspect and apply:

```bash
kubectl apply --dry-run=server -f /tmp/myproj-workspace.yaml
kubectl apply -f /tmp/myproj-workspace.yaml
```

The renderer now also supports:
- `PROJECT_MODE=always-on|warm|cold`
- optional private repo bootstrap via `PROJECT_REPO_SECRET_NAME`
- optional repo bootstrap mode via `PROJECT_REPO_SEED_MODE=init|runtime`
- optional `REPO_SEED_IMAGE` override for the repo bootstrap init container
- optional strict node pinning via `WORKSPACE_NODE_SELECTOR`
- optional extra tolerations via `WORKSPACE_EXTRA_TOLERATIONS`
- rendering the target `Namespace`
- live API validation with `--validate-live`

For repeated onboarding, scaffold a catalog entry instead of hand-writing it:

```bash
/home/devsounio/beagle/k8s/workspace-platform/scripts/scaffold-project-env.sh \
  warm \
  my-project \
  https://github.com/example/example.git
```

`scaffold-project-env.sh` now prefers
`/home/devsounio/beagle/k8s/workspace-platform/image-defaults.env` when that
file exists, so new catalog entries can inherit registry-backed image refs
without hand-editing every project file.

The scaffolder now also seeds a first-class `VSIX` contract:

- `PROJECT_VSIX_PACK`
- `PROJECT_VSIX_PACK_VERSION`
- `PROJECT_VSIX_REQUIRED_EXTENSIONS`
- `PROJECT_VSIX_RECOMMENDED_EXTENSIONS`
- `PROJECT_VSIX_EXPERIMENTAL_EXTENSIONS`

The canonical pack definitions live in:

- `/home/devsounio/beagle/k8s/workspace-platform/vsix-packs`

To render one pack into env lines directly:

```bash
/home/devsounio/beagle/k8s/workspace-platform/scripts/render-vsix-pack-env.sh \
  /home/devsounio/beagle/k8s/workspace-platform/vsix-packs/sounio.project-vsix-pack.json
```

This is the bridge between the sovereign cockpit model and the `openvscode-server`
IDE lane:

- the cockpit stays the continuity layer
- the habitat IDE lane becomes the extension host
- the workspace catalog can now declare pack intent explicitly

For habitats that still reference node-local images such as `localhost/...`,
preload those images onto the target worker before moving the workspace:

```bash
/home/devsounio/beagle/k8s/workspace-platform/scripts/preload-node-local-images.sh \
  r740-proxmox \
  localhost/project-cockpit:20260406-8 \
  localhost/sounio-workspace-ide:0406231500 \
  localhost/beagle-workspace-ssh:b216
```

That keeps image movement explicit and avoids ad hoc one-off loader pods.

If you want to reduce dependence on `localhost/...` without mutating the live
manifests blindly, publish the current node-local images to a pullable registry
and write a defaults file for future scaffolds:

```bash
/home/devsounio/beagle/k8s/workspace-platform/scripts/publish-node-local-images.sh \
  --registry-host ttl.sh \
  --prefix sounio-lab \
  --ttl 24h \
  --out /tmp/workspace-platform-image-defaults.env
```

Then install the generated defaults file:

```bash
install -m 600 /tmp/workspace-platform-image-defaults.env \
  /home/devsounio/beagle/k8s/workspace-platform/image-defaults.env
```

Notes:
- `ttl.sh` is a transition tool, not the forever registry
- the current stable lab registry path is:
  - push from management: `192.168.3.207:5003`
  - pull from nodes: `10.100.100.3:5003`
- the current boring production path is still:
  - warm `r740-proxmox` and `r770-proxmox`
  - keep active habitats and the cockpit constrained to that validated worker pair
- the generated defaults file only affects future scaffolds; it does not
  rewrite existing live manifests by itself

When the lab push registry is available, prefer:

```bash
/home/devsounio/beagle/k8s/workspace-platform/scripts/publish-node-local-images.sh \
  --registry-host 192.168.3.207:5003 \
  --prefix sounio-lab \
  --ttl stable \
  --plain-http \
  --out /tmp/workspace-platform-image-defaults.env
```

For many projects, use the catalog layer:

```bash
/home/devsounio/beagle/k8s/workspace-platform/scripts/render-project-catalog.sh \
  /home/devsounio/beagle/k8s/workspace-platform/catalog \
  /tmp/workspace-catalog
```

To validate a whole catalog against the live cluster in one pass:

```bash
/home/devsounio/beagle/k8s/workspace-platform/scripts/validate-project-catalog.sh \
  /home/devsounio/beagle/k8s/workspace-platform/catalog
```

The catalog tree now also includes one `.env.example` per mode:
- `catalog/always-on/project.env.example`
- `catalog/warm/project.env.example`
- `catalog/cold/project.env.example`

The live catalog now also includes real project definitions you can render or
apply immediately:
- `catalog/always-on/sounio.env`
- `catalog/warm/beagle.env`
- `catalog/warm/sounio-examples.env`
- `catalog/warm/hyperbolic-semantic-networks.env`
- `catalog/warm/darwin-pbpk.env`
- `catalog/cold/sounio-benchmarks.env`
- `catalog/cold/sounio-llm-training.env`

And validate the whole catalog live before applying anything:

```bash
/home/devsounio/beagle/k8s/workspace-platform/scripts/validate-project-catalog.sh \
  /home/devsounio/beagle/k8s/workspace-platform/catalog
```

To validate every `.env` in the catalog against the live cluster:

```bash
/home/devsounio/beagle/k8s/workspace-platform/scripts/validate-project-catalog.sh \
  /home/devsounio/beagle/k8s/workspace-platform/catalog
```

## Current safe operating assumptions

Today the template is operationally safe under these assumptions:

- `PROJECT_NAMESPACE=beagle`, unless you mirror the shared platform resources
  into another namespace
- `sounio-workspace-config` exists in the target namespace
- optional secrets are present if you want:
  - shared Beagle API auth via `beagle-core-secrets`
  - SSH authorized keys via `sounio-workspace-ssh-authorized-keys`
- `PROJECT_WORKSTREAM_ID` is a real workstream identifier for the project

The renderer now validates the namespace/configmap live when you pass
`--validate-live`.

For external projects that are not yet registered as first-class Beagle
workstreams, the workspace bootstrap now degrades gracefully to
`BEAGLE_WORKSPACE_CONTEXT_MODE=local-only` instead of crash-looping. That
means the repo, SSH, IDE, and persistent habitat still come up, while the
`.beagle/context/*` files are written with a degraded but explicit local-only
contract.

The catalog now includes a real `always-on` example for `sounio`:
- `/home/devsounio/beagle/k8s/workspace-platform/catalog/always-on/sounio.env`

The workspace renderer now defaults the repo-seed init container to the same
proven image family as `IDE_IMAGE`. This avoids coupling first boot to a
Docker Hub `alpine/git` pull when the common layer already has a validated
workspace image path.

For private repositories, create a secret in the target namespace with one or
more of these keys:
- `git-credentials`
- `.netrc`
- `known_hosts`

## What the renderer now protects you from

- wrong script path in docs
- missing `PROJECT_WORKSTREAM_ID`
- invalid DNS-style values for slug/namespace/workspace ID
- accidentally inheriting `/workspace/sounio` paths from the shared
  `sounio-workspace-config`
- silently targeting a namespace that does not contain the shared bootstrap
  configmap

## Design intent

- always-on projects get a live `StatefulSet` with `replicas: 1`
- warm/cold projects keep the PVC and render with `replicas: 0`
- heavy CPU/GPU work stays in the shared runner pools

Important separation:

- workspace posture is not the same thing as a research job
- a large project should get one sovereign surface
- not every sovereign surface should be `always-on`
- one mission-control root may coordinate many sovereign surfaces in parallel
  without collapsing their identities

The workspace stays "the house".
The compute pools stay "the muscles".

Current project posture examples on this platform:

- `Sounio`
  - current sovereign surface: `always-on`
- `Hyperbolic Semantic Networks`
  - current sovereign surface: `warm`

The next planned human surface on top of this catalog is the project cockpit
model:

- [SOUNIO_PROJECT_COCKPIT_BLUEPRINT.md](/home/devsounio/beagle/k8s/hpc-sota/SOUNIO_PROJECT_COCKPIT_BLUEPRINT.md)

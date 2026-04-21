# Workspace Catalog

This directory is the operational layer on top of the workspace template.

The onboarding policy that should govern new entries here lives in:

- [PROJECT_ONBOARDING_BLUEPRINT.md](/home/devsounio/beagle/k8s/hpc-sota/PROJECT_ONBOARDING_BLUEPRINT.md)

Instead of hand-rendering one project at a time forever, we keep one `.env`
file per project here and render them as a batch.

Catalog mission-control rule:

- each entry here represents one sovereign project surface
- the catalog is allowed to coordinate many sovereign surfaces in parallel
- but it must not imply that every surface is always-on
- posture in the catalog must stay aligned with the machine-level authority and
  posture policy under `/home/devsounio`

Suggested structure:

- `always-on/`
  - projects that should stay live with `replicas: 1`
- `warm/`
  - projects that keep PVCs but normally render with `replicas: 0`
- `cold/`
  - archive-style workspaces that are defined but usually not running

Current posture examples:

- `always-on/`
  - `sounio`
- `warm/`
  - `hyperbolic-semantic-networks`

Each file is a normal input file for:
- `../scripts/render-project-workspace.sh`

There is now one starter file per mode:
- `always-on/project.env.example`
- `warm/project.env.example`
- `cold/project.env.example`

Render the whole catalog into a directory:

```bash
/home/devsounio/beagle/k8s/workspace-platform/scripts/render-project-catalog.sh \
  /home/devsounio/beagle/k8s/workspace-platform/catalog \
  /tmp/workspace-catalog
```

Then dry-run or apply:

```bash
kubectl apply --dry-run=server -f /tmp/workspace-catalog
kubectl apply -f /tmp/workspace-catalog
```

Or validate the whole catalog against the live cluster in one step:

```bash
/home/devsounio/beagle/k8s/workspace-platform/scripts/validate-project-catalog.sh \
  /home/devsounio/beagle/k8s/workspace-platform/catalog
```

This keeps 21+ projects in one predictable place instead of turning the cluster
into a manual zoo.

What the catalog must not do:

- redefine project authority
- collapse research operations into posture
- confuse a sovereign surface with a permanently live habitat

The same catalog is also intended to drive project-shaped web surfaces later.
To export it into machine-readable JSON for the cockpit layer:

```bash
/home/devsounio/beagle/k8s/workspace-platform/scripts/export-project-catalog-json.sh \
  /home/devsounio/beagle/k8s/workspace-platform/catalog \
  /tmp/project-catalog.json
```

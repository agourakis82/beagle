# Project Onboarding Blueprint

This is the canonical way to bring a new project into the Darwin/Sounio lab
without turning the cluster into a manual zoo.

Use it together with:

1. [AGENT_BOOTSTRAP.md](/home/devsounio/beagle/k8s/hpc-sota/AGENT_BOOTSTRAP.md)
2. [STACK_SEMAPHORE.md](/home/devsounio/beagle/k8s/hpc-sota/STACK_SEMAPHORE.md)
3. [workspace-platform/catalog/README.md](/home/devsounio/beagle/k8s/workspace-platform/catalog/README.md)
4. [TAILNET_DIRECT_CLUSTER_ACCESS.md](/home/devsounio/beagle/k8s/hpc-sota/TAILNET_DIRECT_CLUSTER_ACCESS.md) if the project needs a trusted personal-machine control surface

## Core rule

Every project must enter through the common layer first.

That means:

- lane choice before manifests
- workspace-platform catalog before hand-written snowflakes
- docs before promotion
- canary before claim
- rollback before cutover

If a project cannot explain its lane, storage semantics, observability, and
rollback story, it is not ready for onboarding.

## The three first questions

Before writing YAML, answer these:

1. Is this project primarily `Slurm` or `Kubernetes`?
2. Does it need an always-on workspace, a warm standby workspace, or only a cold/archive definition?
3. What is the smallest proof that tells us the project is really alive?

If those answers are fuzzy, stop there and refine them first.

## Recommended project classes

### `always-on`

Use for:

- active development loops
- projects with frequent browser or SSH workspace access
- surfaces that humans will keep touching

Contract:

- `replicas: 1`
- explicit browser + SSH story
- project-specific README
- smoke command and rollback note

### `warm`

Use for:

- projects with durable PVCs
- projects that should resume quickly but do not need a live pod all day

Contract:

- `replicas: 0`
- PVC and repo state preserved
- clear promotion path to `always-on`

### `cold`

Use for:

- archive-style or occasional projects
- projects that should remain reproducible but not consume steady resources

Contract:

- definition exists in the catalog
- no expectation of always-live surfaces
- explicit reactivation path

## Phase 0: Admission

Required before a project enters the cluster:

- choose lane:
  - `Slurm`
  - `Kubernetes`
  - or explicitly hybrid
- choose workspace mode:
  - `always-on`
  - `warm`
  - `cold`
- choose storage semantics:
  - workspace
  - dataset
  - checkpoint
  - scratch
- choose the smallest canary
- define rollback target

Admission is blocked if:

- the project wants "both lanes" but has no clear primary lane
- the project wants a custom workspace shape that bypasses `workspace-platform`
- the project cannot name a smallest proof

## Phase 1: Project record

Every project should have a record in the workspace catalog:

- `workspace-platform/catalog/always-on/*.env`
- `workspace-platform/catalog/warm/*.env`
- `workspace-platform/catalog/cold/*.env`

Naming guidance:

- `PROJECT_SLUG`: DNS-1123, short, stable
- `PROJECT_NAMESPACE`: prefer `beagle` unless there is a clear isolation reason
- `PROJECT_WORKSTREAM_ID`: stable human identifier
- `WORKSPACE_ID`: match the project surface humans will use
- `SESSION_ID`: stable session family, not a random one-off

Prefer continuity over cleverness.

Examples already in the catalog are better templates than fresh invention.

## Phase 2: Workspace shape

Default workspace path:

- use `workspace-platform`
- render from catalog
- validate against the live cluster before apply

Canonical commands:

```bash
/home/devsounio/beagle/k8s/workspace-platform/scripts/render-project-catalog.sh \
  /home/devsounio/beagle/k8s/workspace-platform/catalog \
  /tmp/workspace-catalog

/home/devsounio/beagle/k8s/workspace-platform/scripts/validate-project-catalog.sh \
  /home/devsounio/beagle/k8s/workspace-platform/catalog
```

Avoid:

- hand-maintained one-off workspace manifests as the long-term source of truth
- project-specific SSH bootstrap drift
- ad hoc branch/bootstrap defaults that silently point to `main`

## Phase 3: Docs minimum

Before promotion, each project should have at least:

- a project README that says:
  - lane
  - smallest canary
  - storage semantics
  - rollback note
- an agent front door:
  - `AGENTS.md` or `CLAUDE.md`
- if it has a remote workspace:
  - a workspace operations note similar in spirit to [WORKSPACE_K8S.md](/home/devsounio/projects/sounio/WORKSPACE_K8S.md)

If a project needs cluster-specific behavior that is non-obvious, document it
before people depend on it.

## Phase 4: Common-layer checks

Before promotion, run:

```bash
cd /home/devsounio
./bootstrap-dev-plane.sh

cd /home/devsounio/beagle/k8s/hpc-sota
./ops/hpc-bootstrap.sh
./ops/hpc-route-doctor.sh
./ops/slurmdbd-backend-doctor.sh
./ops/workspace-platform-doctor.sh
```

If any of those are already yellow for common-layer reasons, fix that first.

Do not onboard a new project onto an already drifting common layer.

## Phase 5: Project canary

The project must prove itself with the smallest meaningful run.

That proof should be:

- cheap
- scriptable
- repeatable
- attached to a real artifact or metric

Examples:

- a Slurm submit script that lands in the correct partition/QoS and completes
- a Kubernetes canary `JobSet`
- a browser + SSH workspace reachability check plus a repo-specific smoke command

## Phase 6: Promotion

Promotion means the project can be named in the lab as a real lane or surface.

Promotion checklist:

- catalog entry exists
- catalog validates
- docs minimum exists
- smallest canary is green
- rollback path is written down
- common-layer doctors are green enough

## Green / Yellow / Red

### Green

A project is green when:

- lane is clear
- workspace mode is clear
- catalog entry validates
- smallest canary has passed recently
- rollback exists and is tested or obviously viable

### Yellow

A project is yellow when:

- the project itself works, but it rides on a common layer that is still noisy
- the canary is green but observability is still thin
- the workspace exists but promotion/cutover is still carrying transitional rules

### Red

A project is red when:

- it bypasses the common layer
- it has no canary
- it has no rollback
- it depends on undocumented operator memory

## Handoff packet

A new project should leave behind a small, boring handoff packet:

- source-of-truth repo path or repo URL
- active branch
- lane
- workspace mode
- smallest canary command
- last known good evidence
- rollback note
- yellow-zone caveats

If that packet cannot fit in a few bullets, the onboarding is not mature enough yet.

## Anti-patterns

Avoid these unless there is a very explicit reason:

- cloning every project as an always-on workspace
- inventing bespoke SSH/bootstrap behavior per project
- exposing project surfaces on Tailnet before the project itself is stable
- treating ad hoc manual kubectl edits as the source of truth
- onboarding multiple new projects at once while the common layer is still shifting

## Strategy recommendation

For this lab, the healthy pattern is:

1. keep hardening the common layer until it feels boring
2. onboard one project at a time through the catalog and doctor path
3. promote only after canary + rollback + docs are real

That is how we preserve momentum without creating a fragile museum of special cases.

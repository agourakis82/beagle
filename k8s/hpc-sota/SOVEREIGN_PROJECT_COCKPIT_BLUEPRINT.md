# Sovereign Project Cockpit Blueprint

This document describes the next level above the `Sounio` pilot:

- a sovereign project cockpit
- multi-project by construction
- honest about server-side memory
- light enough to stay lower-friction than VS Code

Use it together with:

1. [SOUNIO_PROJECT_COCKPIT_BLUEPRINT.md](/home/devsounio/beagle/k8s/hpc-sota/SOUNIO_PROJECT_COCKPIT_BLUEPRINT.md)
2. [PROJECT_ONBOARDING_BLUEPRINT.md](/home/devsounio/beagle/k8s/hpc-sota/PROJECT_ONBOARDING_BLUEPRINT.md)
3. [workspace-platform/README.md](/home/devsounio/beagle/k8s/workspace-platform/README.md)
4. [catalog/README.md](/home/devsounio/beagle/k8s/workspace-platform/catalog/README.md)
5. [SOVEREIGN_VSIX_ARCHITECTURE.md](/home/devsounio/beagle/k8s/hpc-sota/SOVEREIGN_VSIX_ARCHITECTURE.md)
6. [SOVEREIGN_VSIX_EXTENSION_MATRIX.md](/home/devsounio/beagle/k8s/hpc-sota/SOVEREIGN_VSIX_EXTENSION_MATRIX.md)
7. [SOVEREIGN_SUPERCOMPUTING_PLAYGROUND_BLUEPRINT.md](/home/devsounio/beagle/k8s/hpc-sota/SOVEREIGN_SUPERCOMPUTING_PLAYGROUND_BLUEPRINT.md)

## Why this exists

`Sounio` proved that a project-shaped surface is better than re-deriving a
generic IDE session every time.

But the lab is already bigger than one project.

That means the cockpit must evolve from:

- one nice project page

into:

- a sovereign operating surface for multiple heavyweight projects

without losing the properties that made the `Sounio` pilot valuable:

- browser is disposable
- habitat is authoritative
- `tmux` is durable
- memory is server-side
- GitHub publication is explicit
- cluster mutations are narrow and labeled

## Core thesis

The cockpit is not a prettier editor.

It is also no longer just a web dashboard.

It is a sovereign continuity layer across:

- projects
- machines
- models
- terminals
- publication states
- cluster surfaces
- datasets
- visual scenes
- runtime shells

The minimum bar is not "works like VS Code."

The minimum bar is:

- lower friction than VS Code
- more honest about persistence than VS Code
- more project-aware than VS Code
- more truthful about runtime and visualization state than notebook sprawl

## Playground direction

The cockpit should now be designed as the control shell of a larger sovereign
supercomputing playground.

That means the architecture should be compatible with:

- `Web`
- `Windows native`
- `macOS native`
- `iOS native`

and should treat the following as first-class future lanes, not bolt-ons:

- OME-Zarr datasets
- WebGPU visualization
- job provenance
- runtime capability surfaces

The first concrete proof path for this direction should live at:

- `/projects/sounio/viewer`

as a full-page sibling surface to the project cockpit, not as a tiny widget
inside the existing memory lane.

## SOTA / SOTT framing

The cockpit should aim for a level of novelty and seriousness comparable to the
projects it serves.

For the lab, that means:

- `SOTA` in practical continuity
- `SOTT` in truthful operational semantics

In practice:

- memory should survive browser death
- review state should survive machine changes
- project state should survive model switching
- the system should reveal what is publishable versus what is only local memory
- the UI should reveal whether each claim is:
  - `observed`
  - `remembered`
  - `declared`

## What must be sovereign

Every project cockpit should treat the following as first-class memory:

- the project habitat
- the canonical `tmux` family
- local memory context such as `.beagle/`
- CLI memory such as:
  - `~/.claude`
  - `~/.codex`
- publication state:
  - branch
  - PR
  - review
  - merge readiness
- cluster surface state:
  - browser path
  - SSH path
  - doctors
  - repair lanes

## The five sovereign lanes

Each heavyweight project should expose the same mental model:

1. `Project lane`
   - what this project is
   - where it lives
   - what branch contract is active

2. `Session lane`
   - who is here
   - what session is current
   - what was the last re-entry

3. `Memory lane`
   - fast resume
   - deep memory
   - sovereign resume packet
   - continuity timeline

4. `Publication lane`
   - branch status
   - publishable dirt
   - PR continuity
   - review ledger
   - merge readiness

5. `Cluster lane`
   - surface health
   - pod health
   - doctors
   - controlled repairs

These lanes should be project-invariant even if the internals vary by project.

## Multi-project contract

The cockpit must scale from one project to many without inventing snowflakes.

### Registry contract

Each project should be described by the workspace catalog, not by hard-coded UI
assumptions.

Minimum registry fields:

- `projectSlug`
- `mode`
- `namespace`
- `repoUrl`
- `workspaceRoot`
- `workspace public/browser route`
- `sshHost`
- `tmuxSession`
- `preferredPrBase`
- `doctorCommand`
- `browserAutomationUrl`
- `browserAutomationPublicUrl`

Additive playground fields should be expected as first-class catalog data:

- `playgroundClass`
- `runtimeCapabilities`
- `datasetCatalog`
- `viewerDefaults`

### Project classes

The cockpit should respect project class:

- `always-on`
- `warm`
- `cold`

And the UI should tell the truth when a route is intentionally cold.

### Heavyweight project expectation

For heavyweight projects, the cockpit should assume:

- a durable habitat
- a non-trivial review/publication story
- model-assisted planning
- cluster-facing operations

## Continuity model

The system should preserve and render at least four layers of time:

1. `Fast resume`
   - instant re-entry
   - enough to know where to attach

2. `Deep memory`
   - richer packet from the habitat
   - okay to hydrate more slowly

3. `Continuity timeline`
   - ordered events
   - grouped by phase

4. `Publication checkpoint`
   - social state of the work
   - commit/push/PR/review/merge

## Executive phase model

Every project should be reducible to the same executive phase frame:

- `Work`
- `Publish`
- `Review`
- `Merge`

Each phase should expose a simple state:

- `active`
- `blocked`
- `ready`

This is the smallest truthful dashboard for heavyweight work.

## Truth surfaces

SOTA continuity without SOTT semantics is still too weak for heavyweight
projects.

The cockpit should therefore expose not only state, but also epistemic source:

- `observed`
  - live habitat or lane telemetry
- `remembered`
  - server-side continuity packet or cached project memory
- `declared`
  - policy, catalog, or project contract fallback

That distinction should progressively apply across:

- IDE
- Publication
- Review
- Cluster

The multi-project route `/projects` should show a compact executive truth matrix
per card, while project-detail lanes should show truth source and truth mode
inline inside each lane.

Each project card should also carry a small `Mission control` surface with:

- next safe move
- current PR anchor
- publication stage
- truth summary across IDE / publish / review / cluster

## Model sovereignty

The cockpit should not assume one model owns the project.

It should remember:

- last AI lane used
- recent Claude memory
- recent Codex memory
- browser automation activity

And it should let that survive machine switching without pretending the browser
was the real source of memory.

## IDE lane and VSIX

The cockpit should not become a generic VS Code clone, but heavyweight
projects do deserve a first-class IDE lane with selective `VSIX` support.

The right split is:

- sovereign cockpit for continuity
- `openvscode-server` habitat lane for extension hosting

That means the platform can support `VSIX` seriously without making the browser
IDE the new source of truth.

The IDE lane should also distinguish truth classes explicitly:

- `observed` when the habitat reports live substrate state
- `remembered` when the cockpit is serving cached sovereign memory
- `declared` when the UI is falling back to project policy before live memory arrives

## Browser truthfulness

The system should not pretend all routes are equal.

It should encode:

- human route
- automation route
- known route pathologies

If the hostname is good for humans but blocked for automation, say that
explicitly and route around it.

## Publication truthfulness

The cockpit should distinguish:

- local memory
- publishable repo changes
- social publication state

That means:

- `.beagle/` is not automatically publication dirt
- a draft PR is not the same as merge readiness
- review state is its own preserved object

## Minimal next architecture

### Near-term

- keep one deployable app
- keep `Sounio` as the pilot route
- generalize the memory/publication/session model across projects

### Mid-term

- project index route:
  - `/projects`
- project chooser with mode, health, and continuity state
- shared sovereign ledger schema across projects

### Longer-term

- one cockpit serving many projects
- per-project continuity packets
- consistent publication and review state machines
- optional project-specific plugin panes where justified

## Guardrails

- do not regress to browser-owned state
- do not make route truth implicit
- do not let per-project UI drift outrun the catalog
- do not hide review/publication state in unstructured text
- do not expand to many projects before the shared sovereign model is explicit

## Immediate implication

`Sounio` should remain the pilot, but the cockpit code and docs should now be
written as if:

- `Sounio` is project one
- not the only project that matters

That is the minimum serious direction for the lab.

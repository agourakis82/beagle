# Sounio Project Cockpit Blueprint

This document describes the canonical direction for a low-friction project
surface that is lighter than VS Code, more project-shaped than a generic IDE,
and honest about what must persist on the server side.

Use it together with:

1. [PROJECT_ONBOARDING_BLUEPRINT.md](/home/devsounio/beagle/k8s/hpc-sota/PROJECT_ONBOARDING_BLUEPRINT.md)
2. [workspace-platform/README.md](/home/devsounio/beagle/k8s/workspace-platform/README.md)
3. [catalog/README.md](/home/devsounio/beagle/k8s/workspace-platform/catalog/README.md)
4. [WORKSPACE_K8S.md](/home/devsounio/projects/sounio/WORKSPACE_K8S.md)
5. [SOVEREIGN_PROJECT_COCKPIT_BLUEPRINT.md](/home/devsounio/beagle/k8s/hpc-sota/SOVEREIGN_PROJECT_COCKPIT_BLUEPRINT.md)

## Why this exists

The cluster already knows how to keep a project habitat alive.

The friction is in the human surface:

- reconnecting VS Code
- remembering the right shell path
- remembering the right `tmux` session
- hopping between browser, SSH, Grafana, GitHub, and doctors
- re-deriving project state instead of attaching to it

The Project Cockpit should turn that into one project-shaped page.

`Sounio` is the pilot, but it should no longer be treated as the ceiling for
the cockpit design.

## Core thesis

The browser is not the persistence surface.

The persistence surface is:

- the remote workspace
- the project repo
- the project docs
- the project `tmux` session family

The cockpit only attaches, renders, and orchestrates.

That means a page can close, the terminal can survive, and another machine can
reattach later without pretending the browser was the source of truth.

Auth should stay equally honest:

- access belongs to the outer tailnet or web surface
- the cockpit itself should add lightweight viewer identity, presence, and
  session memory on top of that

## Target user story

For `Sounio`:

1. open `/projects/sounio`
2. see the project status immediately
3. the terminal lane attaches to `tmux sounio-dev`
4. chat/planning is available in the same surface
5. git status and commit flow are visible
6. cluster doctors and logs are one click away
7. close the page
8. reopen from another machine and land back in the same project session

## Scope

### In scope for the cockpit

- project registry and routing
- terminal attach/reattach
- planning/checklist lane
- lightweight file/diff awareness
- commit/push/PR lane
- cluster mini-IDE lane
- project-specific docs and doctors

### Out of scope for the first cut

- replacing every VS Code feature
- full generic code intelligence
- arbitrary shell multiplexing with no project model
- editing every Kubernetes manifest from the browser
- pretending GitHub and cluster mutations are risk-free UI clicks

## Canonical model

### Project registry

The source of truth for which projects exist should come from the workspace
catalog:

- [catalog/always-on](/home/devsounio/beagle/k8s/workspace-platform/catalog/always-on)
- [catalog/warm](/home/devsounio/beagle/k8s/workspace-platform/catalog/warm)
- [catalog/cold](/home/devsounio/beagle/k8s/workspace-platform/catalog/cold)

That means the cockpit does not become a second manual inventory.

### Project route

One project, one route:

- `/projects/sounio`
- later `/projects/pbpk`
- later `/projects/beagle`

### Persistent session

Each project gets a canonical session family:

- `sounio-dev`

The terminal lane must attach to that session first and only create it when it
does not exist.

### Workspace mode awareness

The cockpit should display the mode clearly:

- `always-on`
- `warm`
- `cold`

That helps avoid mistaken expectations such as trying to attach to a workspace
that is intentionally scaled to zero.

## Architecture

### 1. Registry layer

Input:

- workspace catalog `.env` files

Output:

- machine-readable project JSON

The registry should provide:

- project slug
- namespace
- mode
- repo URL
- branch
- workspace/browser URL
- SSH host
- canonical tmux session
- doctor commands
- optional GitHub metadata
- optional public workspace URL

### 2. Web frontend

Recommended stack:

- React
- Vite
- Monaco or a lightweight diff/editor lane later
- `xterm.js` when we wire the terminal for real

Main panels:

- Project lane
- Session lane
- Terminal lane
- Git/GitHub lane
- Cluster/Ops lane
- Planning lane

### 3. Terminal bridge

The browser must not own the session.

Instead:

- a websocket bridge attaches to the remote project shell
- the remote shell attaches to `tmux sounio-dev`
- if the page dies, `tmux` lives on

The safest shape is:

- browser -> websocket terminal bridge -> remote shell -> `tmux`

### 4. Git/GitHub lane

For the MVP, keep it narrow:

- branch
- dirty/clean status
- live guardrails
- diff preview
- staged vs unstaged summary
- commit message
- push
- open PR URL

Later:

- review threads
- CI status
- draft PR creation

Mutation should stay explicit:

- preview first
- confirm second
- write the resulting commit, push, or PR metadata back into session memory

### 5. Cluster mini-IDE lane

This should prioritize reading and runbooks over mutation.

Good MVP operations:

- doctors
- pod status
- service status
- logs
- links to Grafana
- tailnet surface health / redundancy

Later:

- selected `kubectl exec`
- controlled rollout actions
- YAML inspection

### 6. Toolchain lane

The cockpit should make the project toolchain explicit instead of assuming the
user remembers what is installed in the habitat.

For `Sounio`, the first-class tools are:

- `Claude Code`
- `Codex`
- `Kimi CLI`
- `agent-browser`

The cockpit should surface their live versions from the habitat so the planning
lane reflects reality instead of static docs.

## Sounio pilot contract

The first pilot is `Sounio`.

Its canonical inputs are:

- catalog entry:
  - [sounio.env](/home/devsounio/beagle/k8s/workspace-platform/catalog/always-on/sounio.env)
- workspace browser:
  - `sounio-workspace`
- SSH host:
  - `sounio-workspace`
- canonical `tmux` session:
  - `sounio-dev`
- repo:
  - `https://github.com/Sounio-lang/sounio.git`

## MVP phases

### Phase 1: Sounio cockpit shell

Deliver:

- route `/projects/sounio`
- project metadata card
- session card
- doctors card
- links to workspace and Grafana
- planning/checklist lane
- terminal lane contract placeholder

Success:

- one page is enough to re-enter the project deliberately

### Phase 2: real terminal bridge

Deliver:

- attach/reattach to `tmux sounio-dev`
- browser reconnect does not kill the project session

Success:

- close browser, reopen elsewhere, same terminal context survives

### Phase 3: Git/GitHub lane

Deliver:

- branch/status/diff summary
- commit and push actions
- PR link

### Phase 4: cluster mini-IDE lane

Deliver:

- doctors
- selected pod/log views
- project health summary

### Phase 5: generalize from Sounio to the catalog

Deliver:

- project registry generated from catalog
- one route per project

## Guardrails

- do not build a second source of truth beside the workspace catalog
- do not make the browser the persistence layer
- do not hide mutation behind unlabeled buttons
- do not promise full IDE parity before terminal persistence is real
- do not onboard more project routes until the `Sounio` pilot feels boring

## Recommended first implementation

Build a web MVP that is honest:

- real route and project cards
- real data seeded from the catalog
- explicit terminal contract placeholder
- explicit next backend seam for `tmux` attach

That gives us a real project-shaped surface today without lying about what the
terminal layer can already do.

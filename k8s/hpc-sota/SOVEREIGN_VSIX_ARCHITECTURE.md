# Sovereign VSIX Architecture

This document explains how the lab should support `VSIX` without collapsing the
sovereign cockpit back into "just another browser IDE."

Use it together with:

1. [SOVEREIGN_PROJECT_COCKPIT_BLUEPRINT.md](/home/devsounio/beagle/k8s/hpc-sota/SOVEREIGN_PROJECT_COCKPIT_BLUEPRINT.md)
2. [SOUNIO_PROJECT_COCKPIT_BLUEPRINT.md](/home/devsounio/beagle/k8s/hpc-sota/SOUNIO_PROJECT_COCKPIT_BLUEPRINT.md)
3. [projects/sounio/WORKSPACE_K8S.md](/home/devsounio/projects/sounio/WORKSPACE_K8S.md)
4. [beagle/k8s/sounio-workspace-habitat/README.md](/home/devsounio/beagle/k8s/sounio-workspace-habitat/README.md)

## Thesis

The platform should support `VSIX`, but in the right layer.

The sovereign cockpit remains the continuity layer:

- project memory
- session memory
- publication and review state
- cluster truth

The IDE lane remains the extension host layer:

- `openvscode-server`
- workspace-local editor state
- selectively approved `VSIX`

That split matters.

If we blur them together, we get the worst parts of a browser IDE:

- heavy startup
- fuzzy persistence semantics
- hidden extension failure modes
- project continuity tied to UI state

If we keep them separate, we get the right shape:

- browser is disposable
- habitat is authoritative
- cockpit is sovereign
- IDE lane is modular

## What already exists

The stack already has a viable extension-host substrate:

- `workspace-ide` containers run `openvscode-server`
- `sounio-workspace` and the habitat surface already expose that browser IDE
- the persistent home under `/workspace/.home/openvscode-server` already gives
  us the right place to preserve extension state across restarts

In practice, this means the platform does **not** need to invent a fake VSIX
runtime from scratch.

It needs to:

1. standardize how `VSIX` is installed and persisted
2. define which extensions are first-class per project class
3. surface extension state truthfully in the sovereign cockpit

## The three-layer model

### 1. Sovereign cockpit

This remains responsible for:

- project mission control
- memory lane
- publication lane
- review ledger
- cluster lane
- runtime truth

It should **not** try to become a generic extension host.

### 2. IDE lane

This is the `openvscode-server` runtime inside the workspace habitat.

It is responsible for:

- installing approved `VSIX`
- preserving extension state in the persistent home
- exposing editor-native capabilities when a project actually benefits from them

### 3. Extension registry/policy

This is the missing layer we should add.

It should define:

- which extensions are approved
- which project classes get which default packs
- whether an extension is:
  - required
  - recommended
  - experimental
  - blocked

## The support contract

We should support `VSIX` in three modes.

### Mode A: Built-in platform pack

For extensions we trust and expect frequently:

- install in the IDE image
- or preseed during workspace bootstrap

Use this for:

- language tooling
- Git/GitHub
- notebooks
- core YAML/TOML/editor support

### Mode B: Project pack

For extensions specific to a project class:

- declared in project metadata
- materialized into the workspace during promotion/bootstrap

Use this for:

- Sounio-specific language support
- Beagle/platform ops packs
- PBPK/omics notebooks and data tooling

### Mode C: User-sidecar pack

For personal or experimental tools:

- installed into the persistent home
- isolated from the platform-approved baseline

This keeps experimentation possible without turning the platform into a drift
machine.

## The persistence model

`VSIX` support only feels real if it survives reconnection.

The authoritative state should live in:

- `/workspace/.home/openvscode-server`

This should preserve:

- installed extensions
- user settings
- workspace storage
- cached extension host state

The cockpit should not pretend this state is stateless.

It should render:

- IDE substrate:
  - `openvscode-server`
- extension pack state:
  - baseline pack active or not
- extension persistence:
  - durable in habitat home
- AI IDE agents:
  - `Codex` as `vsix-first`
  - `Claude Code` as `hybrid`

That split is intentional.

- `Codex` is the stronger candidate for editor-native installation in a
  compatible VSIX substrate.
- `Claude Code` should stay truthfully dual-homed:
  - sovereign in the terminal lane
  - optionally present in the IDE lane when the runtime proves out

Current truthfulness rule:

- `Codex` is modeled as `vsix-first`, but we should not claim IDE-native runtime
  verification until we have an official install artifact or extension identifier
  validated in `openvscode-server`
- `Claude Code` is modeled as `hybrid`, and should remain sovereign in the
  terminal lane even if an IDE-native surface becomes available later

## The policy model

Not every extension deserves first-class support.

We should classify extensions as:

### Required

These are part of the project contract.

Examples:

- Sounio language support when it exists
- GitHub Pull Requests
- EditorConfig

### Recommended

Helpful but not mandatory.

Examples:

- Markdown tooling
- YAML tooling
- Jupyter

### Experimental

Allowed but not guaranteed.

Examples:

- AI/chat helpers that overlap with sovereign cockpit lanes
- niche visualization tools

### Blocked

Do not bless these at platform level.

Examples:

- extensions that require Microsoft-only APIs not present in OpenVSCode
- opaque telemetry-heavy bundles
- extensions that duplicate sovereign platform capabilities while hiding state

## What the cockpit should surface

If VSIX becomes part of the platform, the cockpit should expose an `IDE lane`
card or `Extension lane` card with:

- IDE substrate:
  - `openvscode-server`
- extension host readiness
- baseline pack version
- project pack version
- install mode:
  - image
  - bootstrap
  - user-sidecar
- launch route:
  - human browser route
  - automation/browser-check route when relevant

That keeps the system truthful.

## The implementation path

### Phase 1: Standardize packs

Add a simple manifest format, for example:

- `project-vsix-pack.json`

Fields:

- `projectSlug`
- `packVersion`
- `required`
- `recommended`
- `experimental`

### Phase 2: Install packs during workspace bootstrap

Teach the workspace bootstrap to:

1. read the project pack
2. install missing extensions into the persistent home
3. record what was installed and when

### Phase 3: Surface it in the cockpit

Add to the project executive state:

- `ideKind`
- `extensionPackStatus`
- `requiredExtensionsReady`
- `experimentalExtensionsPresent`

### Phase 4: Support private/internal VSIX

For lab-native extensions:

- store packaged `VSIX` in the lab registry or artifact store
- install by explicit version
- avoid ad hoc manual installs on every habitat

## The boundary with AI tools

Do not let AI extensions re-own the project.

The sovereign truth stays here:

- `tmux`
- `.beagle/`
- `~/.claude`
- `~/.codex`
- cockpit memory lane
- publication/review ledger

An AI `VSIX` may be useful inside the IDE lane, but it should remain a
secondary surface, not the source of truth.

## Minimum viable platform stance

For now, the right stance is:

- yes, support `VSIX`
- no, do not rebuild VS Code inside the cockpit
- yes, use `openvscode-server` as the extension host
- yes, standardize project packs
- yes, expose extension readiness truthfully in the cockpit

That is the narrowest path that is still worthy of heavyweight projects.

# Sovereign VSIX Extension Matrix

This document proposes the first serious `VSIX` packs for the lab.

It is intentionally opinionated:

- the cockpit remains sovereign
- the IDE lane is modular
- extension sprawl should not become the new platform drift

Use it together with:

1. [SOVEREIGN_VSIX_ARCHITECTURE.md](/home/devsounio/beagle/k8s/hpc-sota/SOVEREIGN_VSIX_ARCHITECTURE.md)
2. [SOVEREIGN_PROJECT_COCKPIT_BLUEPRINT.md](/home/devsounio/beagle/k8s/hpc-sota/SOVEREIGN_PROJECT_COCKPIT_BLUEPRINT.md)
3. [projects/sounio/README.md](/home/devsounio/projects/sounio/README.md)

## Extension selection rules

We should prefer extensions that are:

- known to work in OpenVSCode-compatible runtimes
- useful for heavyweight project continuity
- honest about their role
- lightweight enough not to fight the sovereign cockpit

We should avoid extensions that:

- duplicate the cockpit's publication/review/cluster truth while hiding state
- assume Microsoft-only desktop APIs
- drag in too much runtime novelty for too little project value

## Pack classes

Every project can consume three packs:

1. `Core Sovereign Pack`
2. `Project Class Pack`
3. `Experimental User Pack`

## Core Sovereign Pack

This pack should be available to all heavyweight projects by default.

### Required

- `EditorConfig.EditorConfig`
- `eamodio.gitlens`
- `GitHub.vscode-pull-request-github`
- `redhat.vscode-yaml`
- `ms-python.python`
- `ms-toolsai.jupyter`

### Recommended

- `tamasfe.even-better-toml`
- `rust-lang.rust-analyzer`
- `ms-vscode.makefile-tools`
- `yzhang.markdown-all-in-one`

### Experimental

- AI/editor assistants that overlap with cockpit lanes

## Sounio pack

This is the first serious project-specific pack.

### Required

- `rust-lang.rust-analyzer`
- `llvm-vs-code-extensions.vscode-clangd`
- `ms-python.python`
- `redhat.vscode-yaml`

### Recommended

- `ms-vscode.cpptools`
- `GitHub.vscode-pull-request-github`
- `ocamllabs.ocaml-platform`
- `leanprover.lean4`

### Experimental

- a future internal `Sounio Language` VSIX
  - syntax
  - diagnostics
  - compiler hooks
  - language server integration

## Beagle / platform pack

### Required

- `rust-lang.rust-analyzer`
- `redhat.vscode-yaml`
- `ms-kubernetes-tools.vscode-kubernetes-tools`
- `GitHub.vscode-pull-request-github`
- `ms-python.python`

### Recommended

- `hashicorp.terraform`
- `ms-azuretools.vscode-docker`

### Experimental

- log viewers or infra dashboards inside the IDE lane

## PBPK / omics pack

### Required

- `ms-python.python`
- `ms-toolsai.jupyter`
- `redhat.vscode-yaml`

### Recommended

- `REditorSupport.r`
- CSV/table tooling extensions

### Experimental

- domain-specific notebook helpers
- bioinformatics viewers

## What not to bless yet

These categories should stay out of the default packs for now:

- full AI IDE shells that try to re-own project continuity
- extension bundles that assume desktop Electron APIs only
- very heavy cloud-account integrations with unclear persistence semantics

That does not mean "never."

It means:

- use them experimentally first
- do not make them part of the platform contract prematurely

## AI IDE agents

These should be modeled separately from ordinary extension packs.

Current truth:

- `Codex`
  - policy: `vsix-first`
  - status: `runtime-unverified` until an official install artifact or extension
    identifier is validated in `openvscode-server`
- `Claude Code`
  - policy: `hybrid`
  - status: terminal-lane sovereign first, IDE-native integration optional until
    runtime proof is boring

## First concrete platform target

If we want a believable first milestone, it should be:

### Core pack

- EditorConfig
- GitLens
- GitHub Pull Requests
- YAML
- Python
- Jupyter
- rust-analyzer

### Sounio pack

- Core pack
- clangd
- cpptools

This is enough to make the IDE lane materially better without making the
cockpit secondary.

## What the cockpit should show

For each project, eventually expose:

- `IDE substrate`
- `baseline pack`
- `project pack`
- `required ready`
- `recommended present`
- `experimental enabled`

That turns extension support into a truthful system property rather than a
manual habit.

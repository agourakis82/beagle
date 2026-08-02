# Sovereign Supercomputing Playground Blueprint

This document extends the sovereign cockpit from a project control surface into
a broader supercomputing playground.

Use it together with:

1. [SOVEREIGN_PROJECT_COCKPIT_BLUEPRINT.md](/home/devsounio/beagle/k8s/hpc-sota/SOVEREIGN_PROJECT_COCKPIT_BLUEPRINT.md)
2. [SOVEREIGN_VSIX_ARCHITECTURE.md](/home/devsounio/beagle/k8s/hpc-sota/SOVEREIGN_VSIX_ARCHITECTURE.md)
3. [SOVEREIGN_VSIX_EXTENSION_MATRIX.md](/home/devsounio/beagle/k8s/hpc-sota/SOVEREIGN_VSIX_EXTENSION_MATRIX.md)

## Core thesis

The platform should not stop at:

- terminal
- GitHub
- cluster repair
- IDE substrate

It should grow into a sovereign playground for heavyweight computational work
where:

- datasets are first-class
- visualization is first-class
- jobs are first-class
- provenance is first-class
- truth is first-class

The cockpit then becomes the project-facing shell of a broader environment for:

- language substrate work
- training
- benchmarking
- imaging
- simulation
- HPC orchestration

Two implementation choices now matter for the near-term roadmap:

- `SGLang + Dynamo` should be treated as the primary private inference fabric
  for open-model serving, distinct from Beagle routing itself
- `Sounio` should carry a contract pack for scientific scene acceptance,
  provenance gates, and publication gates, instead of being stretched into the
  full shell/runtime layer

## Target runtimes

The playground must be designed for multiple runtimes from the start:

1. `Web`
   - disposable browser shell
   - excellent for re-entry, review, dashboards, and shared views

2. `Windows native`
   - first-class workstation runtime
   - capable of larger local caches and richer graphics integration

3. `macOS native`
   - first-class workstation runtime
   - strong fit for local scientific and creative workflows

4. `iOS native`
   - first-class mobile runtime
   - touch-first review and exploratory visualization surface

5. `Apple Vision / visionOS`
   - first-class spatial control-room runtime
   - optimized for orchestration, scientific inspection, and multi-panel
     re-entry rather than keyboard-heavy coding

## Runtime readiness note

The Apple Vision lane is not just aspirational.

The project already has an active Apple Developer account available, so
`visionOS` can be treated as a concrete runtime planning target rather than a
purely speculative shell.

The important design rule is:

- one sovereign model
- multiple runtime shells

not:

- one web app stretched awkwardly across every platform

## Shared core versus runtime shells

### Shared sovereign core

The following should be runtime-independent:

- project identity
- session identity
- continuity packets
- truth surfaces
- mission control summaries
- publication state
- review state
- dataset provenance
- job provenance
- scene/view state

### Runtime-specific shells

Each runtime should provide a thin shell around the same sovereign core:

- `web shell`
- `desktop shell`
- `mobile shell`

Each shell may differ in:

- rendering backend details
- authentication affordances
- storage budget
- offline cache budget
- interaction model

but should not fork the underlying continuity or truth model.

## OME-Zarr as a first-class data substrate

The first serious data primitive should be `OME-Zarr`.

It is a strong fit because it supports:

- chunked access
- multiscale pyramids
- cloud or object-store friendly layouts
- scientific imaging and derived layers

The playground should treat OME-Zarr as a native dataset shape, not a plugin.

### OME-Zarr lane expectations

The dataset lane should know:

- dataset identity
- version or snapshot
- multiscale levels
- channels
- transforms
- labels or segmentation groups
- provenance to cluster jobs and model outputs

### OME-Zarr truth

The dataset lane should also be epistemically honest:

- `observed`
  - dataset metadata was read live
- `remembered`
  - metadata is cached from a previous successful read
- `declared`
  - only catalog or policy metadata is available

## WebGPU as a first-class rendering substrate

The primary interactive rendering substrate should be `WebGPU` where available.

That makes the playground capable of:

- real-time slice viewing
- multiscale navigation
- dense overlays
- channel mixing
- segmentation display
- inference heatmaps
- embeddings or attention overlays

### Rendering contract

The rendering system should separate:

- scene graph / view state
- dataset adapter
- runtime shell
- GPU backend

The browser should not own the scene truth.

Instead, the browser or native shell should render a scene that can be
remembered and rehydrated by the sovereign core.

## Job and provenance lane

The cockpit already has publication and cluster lanes.

The playground should add a stronger provenance story:

- which job produced this artifact
- which model version produced this layer
- which dataset version is being viewed
- which transform or preprocessing path was used

That provenance should survive re-entry just like publication and review state
already do.

## New sovereign lanes for the playground

The current cockpit lanes stay valid:

- Project
- Session
- Memory
- Publication
- Cluster

The playground should add at least:

6. `Dataset lane`
   - active dataset
   - active scene
   - data truth
   - provenance anchor

7. `Visualization lane`
   - active view
   - renderer truth
   - runtime capability
   - overlay state

8. `Job provenance lane`
   - active run
   - producing cluster job
   - artifact lineage

9. `Cognitive routing lane`
   - best agent now
   - why this lane is recommended
   - model/runtime budget
   - routing truth

10. `Knowledge graph lane`
   - primary anchors across project, branch, PR, dataset, artifact, and scene
   - GraphRAG++ substrate status
   - agent ledger / continuity hooks

## Runtime capability matrix

Every runtime should declare capabilities explicitly instead of pretending all
shells are equal.

The matrix should include at least:

- WebGPU available or not
- dataset cache budget
- offline capability
- IDE lane availability
- terminal bridge availability
- authentication mode
- browser automation support
- touch-first interaction support

The system should present those as truthful capabilities, not marketing copy.

## iOS-specific reality

iOS is important enough that it must be first-class from the beginning.

That means:

- touch-first interaction
- conservative memory strategy
- explicit streaming assumptions
- careful offline cache policy
- a native shell designed for scene review, annotation, and provenance

It should not be treated as a late responsive-web afterthought.

## SOTA / SOTT implications

For this playground, practical novelty comes from combining:

- HPC truth
- dataset truth
- visualization truth
- publication truth
- AI/IDE truth

in one sovereign surface.

The minimum serious bar is:

- better continuity than IDE-centric workflows
- better provenance than ad-hoc notebook workflows
- better runtime honesty than generic dashboards

## Near-term implementation direction

1. Extend the sovereign cockpit docs to treat the app as a playground shell.
2. Add dataset and visualization concepts to mission control language.
3. Define a runtime capability contract for:
   - web
   - windows/macOS native
   - iOS native
4. Design an `OME-Zarr + WebGPU` viewer MVP with:
   - dataset open
   - multiscale metadata read
   - scene memory
   - overlay placeholders
   - provenance hooks
5. Keep truth semantics explicit in every lane:
   - observed
   - remembered
   - declared

## Guardrails

- do not make visualization browser-owned
- do not hide provenance behind screenshots
- do not collapse native runtimes into "just a wrapper"
- do not add WebGPU without truth and provenance
- do not treat iOS as a secondary runtime

## Immediate implication

The platform should now be described not just as a project cockpit, but as a:

- sovereign supercomputing playground

where:

- the cockpit is the control shell
- the habitat is the authority
- OME-Zarr is a first-class data substrate
- WebGPU is a first-class visualization substrate
- web, desktop, and iOS are all real runtimes

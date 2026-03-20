# ADR-001 - Ecosystem Authority Map

## Status

Accepted.

## Context

The Darwin, Beagle, and Sounio portfolio accumulated multiple active repositories with real code, overlapping names, and uneven public authority signals.

Activity alone is not a sufficient indicator of sovereignty.

The codebase audit showed a clearer hierarchy:

- `sounio` is the only line with real language / compiler / stdlib authority
- `beagle` is the only line with real exocortical / platform / cockpit authority
- Darwin repositories carry domain engines, verticals, pipelines, and workspaces
- meta and editorial repositories carry theory, methods, and manuscripts
- historical language lines still exist as technical artifacts but must not keep implicit authority

Without an explicit authority map, the ecosystem invites duplicated ownership, misleading names, and convergence drift.

## Decision

The ecosystem authority map is frozen as follows.

### 1. Sounio is the star

`SOUNIO` is the technical center of gravity for:

- language design
- compiler and backend evolution
- standard library
- runtime substrate
- language tooling
- official bindings, grammar, examples, and benchmarks

Anything that changes language semantics or official language tooling must originate in `sounio` or in a clearly subordinate Sounio satellite repository.

### 2. Beagle is the exocortex

`BEAGLE` is the cognitive-operational center of gravity for:

- memory
- agents
- MCP
- cockpit and service plane
- workflow orchestration
- cluster and HPC integration
- coordination across Darwin lines

Anything that changes operational coordination, exocortical memory, agent behavior, internal gateway surfaces, or platform integration must originate in `beagle` or under explicit Beagle containment.

### 3. Darwin is a contained constellation

Darwin is not sovereign beside Beagle.

Darwin repositories are interpreted as one of:

- domain-engine
- vertical
- workspace/integration layer
- experimental scientific line

They may own domain logic, datasets, methods, or scientific execution surfaces, but they do not own ecosystem-level platform or language authority.

### 4. Meta/editorial is not runtime authority

Meta and editorial repositories may be high-value and active, but they are not treated as product or runtime sovereigns.

They own:

- theory
- methods
- papers
- preprints
- conceptual curation

### 5. Historical and subsumed lines must not compete implicitly

Historical or subsumed repositories may remain versioned and accessible, but they must not retain implicit authority once a successor line is frozen.

This applies immediately to:

- `medlang`
- `demetrios`, unless it is explicitly repositioned

## Canonical Layers

### Sovereign-core

- `sounio`
- `beagle`

### Domain-engine / contained-core

- `darwin-pbpk-platform`
- `DarwinScaffoldStudio.jl`
- `Darwin-stroke-lab`
- `darwin-heliobiology`
- `darwin-operator-genomics`
- `hyperbolic-semantic-networks`

### Workspace / integration

- `darwin-workspace`

### Verticals carried by Beagle

- `darwin-MFC`
- `Darwin-education`

### Sounio satellites

- `sounio-py`
- `sounio-benchmarks`
- `sounio-grammar`
- `sounio-llm-training`
- `sounio-examples`

### Meta / editorial

- `pcs-meta-repo`
- `entropic-symbolic-society`
- `fractal-entropy-project`
- `The-Fractal-Nature-of-an-Entropically-Driven-Society`
- `soc_fractal_ahsd`
- related theory / manuscript seeds

### Historical / subsumed / experimental-explicit

- `medlang`
- `demetrios`, until explicitly repositioned

## Consequences

### Immediate

- only `sounio` and `beagle` remain sovereign by default
- Darwin repositories are treated as contained lines unless explicitly promoted
- new language work defaults to `sounio`
- new platform, cockpit, memory, agent, or orchestration work defaults to `beagle`

### Governance

- names such as `core`, `cockpit`, `platform`, `compiler`, and `runtime` must not be used casually without matching authority
- conflicting public signals must be corrected when README, archive state, or repo naming disagree with actual authority

### Convergence

- Sounio becomes the default destination for future language convergence
- Beagle becomes the default destination for future platform and operational convergence
- Darwin lines remain specialized and contained unless they earn explicit sovereign promotion

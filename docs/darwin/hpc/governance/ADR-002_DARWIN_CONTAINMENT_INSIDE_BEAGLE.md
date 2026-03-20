# ADR-002 - Darwin Containment Inside Beagle

## Status

Accepted.

## Context

The Darwin portfolio includes multiple active scientific, product, and workflow repositories with real code and real domain value.

However, the codebase audit does not support treating Darwin as a sovereign platform beside Beagle.

Observed structure:

- `beagle` already owns the clearest monorepo platform shape
- several Darwin repositories are strong domain engines or verticals
- some Darwin-named repositories are only workspace, stub, or early incubator layers
- sovereignty drift appears when naming outruns actual architectural authority

The governance problem is not whether Darwin work is real.

The problem is whether Darwin work should keep pretending to be ecosystem-level platform authority when Beagle already fills that role.

## Decision

Darwin is formally contained inside Beagle at the platform layer.

### 1. Default containment rule

If a Darwin repository is active and technical, it must default to one of these roles:

- domain-engine
- vertical
- workspace/integration
- experimental line

It does not default to platform sovereignty.

### 2. Beagle owns exocortical integration

The following concerns belong to Beagle by default:

- internal cockpit surfaces
- memory and retrieval orchestration
- agent coordination
- MCP and service integration
- cluster control and HPC coordination
- cross-domain workflow composition

If a Darwin repository begins owning one of these without a clear exception, it is a containment violation and should be absorbed or re-scoped.

### 3. Darwin repositories may remain separate when they have real domain mass

A Darwin repository may remain active and separate when at least one of the following is true:

- it owns a specialized scientific engine
- it owns a domain-specific runtime or algorithmic surface
- it owns a vertical product with distinct constraints
- it needs an independent release cadence for domain reasons

This keeps specialized engines independent without implying platform sovereignty.

### 4. Workspace is not authority

`darwin-workspace` is explicitly treated as workspace/integration, not as owner of language, platform, or domain algorithms.

Workspace repositories may orchestrate, compose, and validate, but they do not outrank the engines they coordinate.

### 5. Stubs and ambiguous lines should not stay sovereign by accident

Repositories with thin runtime surfaces, placeholder structure, or duplicated platform naming should be resolved into one of:

- absorb into Beagle
- freeze as historical
- keep as contained incubator with explicit label

## Operational Rules

### New work routing

- new language work -> `sounio`
- new platform, cockpit, memory, agent, workflow, or service-plane work -> `beagle`
- new scientific engine or domain vertical -> Darwin-contained line under Beagle governance
- new theory or manuscript line -> meta/editorial layer

### Decision vocabulary

Every Darwin repository under review must be assigned one of:

- `keep contained`
- `absorb`
- `freeze`

Only `beagle` may hold the platform-level `keep sovereign` decision on the Darwin side of the ecosystem.

## Initial Decisions

### Keep contained

- `darwin-pbpk-platform`
- `DarwinScaffoldStudio.jl`
- `Darwin-stroke-lab`
- `darwin-heliobiology`
- `darwin-operator-genomics`
- `hyperbolic-semantic-networks`
- `darwin-MFC`
- `Darwin-education`
- `darwin-workspace`

### Absorb

- `darwin-cockpit`

### Freeze or absorb after review

- `darwin-core`

## Consequences

### Good

- Darwin remains active without creating platform duplication
- Beagle gains cleaner authority over orchestration and coordination
- domain engines keep their technical autonomy without inflating sovereignty

### Required follow-up

- update public repo descriptions and README language where sovereignty is overstated
- eliminate implicit platform claims from thin Darwin stubs
- maintain a living convergence worklist for contained lines

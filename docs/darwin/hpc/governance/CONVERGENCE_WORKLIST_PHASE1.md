# Convergence Worklist Phase 1

## Purpose

Turn the authority map into a short execution queue for the first four repositories whose ambiguity or visibility affects the whole ecosystem.

This phase is intentionally narrow.

It is not a full portfolio migration.

It is the first governance-to-execution bridge.

## Phase 1 Scope

Repositories in scope:

- `beagle`
- `sounio`
- `darwin-cockpit`
- `medlang`

Decision vocabulary remains:

- `keep sovereign`
- `keep contained`
- `absorb`
- `freeze`

## Global Rule

This phase should resolve public authority signals first.

It should not attempt broad code migration, runtime rewrites, or cross-repo restructuring beyond what is needed to make authority visible and unambiguous.

## 1. beagle

### Decision

`keep sovereign`

### Why this repo is in Phase 1

`beagle` is the exocortex and platform authority.

Its public identity must match its actual structural role, otherwise every contained Darwin line inherits ambiguity.

### Objective

Align Beagle's public and internal framing with its platform role.

### In Scope

- repo description
- README front-door positioning
- explicit statement that Beagle is the platform / cockpit / exocortex
- explicit statement that Darwin lines are carried or integrated, not sovereign beside it

### Out of Scope

- runtime refactors
- Darwin code migration
- Sounio integration redesign

### Tasks

1. audit current public repo description, tagline, and README front page
2. identify outdated language that still frames Beagle through `medlang` or another legacy identity
3. replace front-door messaging with platform / exocortex wording
4. add one short governance pointer from Beagle docs to the Darwin authority map

### Exit Criteria

- public repo description matches platform authority
- README opening matches exocortex/platform role
- Beagle no longer appears to inherit legacy language-line identity by accident

## 2. sounio

### Decision

`keep sovereign`

### Why this repo is in Phase 1

`sounio` is the language authority.

Without an explicit satellite policy, old and new language-adjacent repos can keep drifting into parallel sovereignty.

### Objective

Freeze Sounio as the only language authority and classify its satellites explicitly.

### In Scope

- official statement of language authority
- explicit classification of:
  - `sounio-py`
  - `sounio-benchmarks`
  - `sounio-grammar`
  - `sounio-llm-training`
  - `sounio-examples`
- clear wording that these are Sounio satellites, not peers

### Out of Scope

- deep compiler refactors
- bindings redesign
- benchmark redesign

### Tasks

1. add a short governance statement inside Sounio docs or README
2. classify official satellite repos and their function
3. state that language semantics, compiler, runtime, and stdlib authority live only in `sounio`
4. cross-check old references to `medlang` or `demetrios` in front-door docs

### Exit Criteria

- Sounio front-door docs declare language authority clearly
- satellite repos are listed as subordinate lines
- no peer-language ambiguity remains in the public framing

## 3. darwin-cockpit

### Decision

`absorb`

### Why this repo is in Phase 1

The name implies sovereignty and overlaps directly with Beagle's platform role.

Its structure does not currently justify independent cockpit authority.

### Objective

Stop `darwin-cockpit` from presenting itself as a sovereign cockpit line and define its absorption path into Beagle.

### In Scope

- repo posture
- naming and positioning cleanup
- absorption target definition
- migration note or freeze note

### Out of Scope

- full code migration into Beagle
- reimplementation of runtime surfaces

### Tasks

1. audit the actual runtime value still present in the repo
2. decide whether the repo becomes:
   - absorption stub with migration note
   - frozen shell pointing to Beagle
3. remove or soften any sovereign cockpit language
4. define the destination inside Beagle where cockpit responsibilities now belong

### Exit Criteria

- Darwin cockpit no longer presents as sovereign
- absorption target into Beagle is documented
- operators can tell immediately that cockpit authority lives in Beagle

## 4. medlang

### Decision

`freeze`

### Why this repo is in Phase 1

`medlang` is the clearest public-authority conflict.

The code still exists, but the public semantic authority should already belong to Sounio.

### Objective

Make MedLang unambiguously historical/subsumed and stop it from acting like a live competing language line.

### In Scope

- archive posture
- README and repo banner alignment
- migration pointer to Sounio
- freeze semantics

### Out of Scope

- code deletion
- repository destruction
- historical artifact cleanup beyond front-door clarity

### Tasks

1. verify whether archive status on GitHub matches README claims
2. if needed, align GitHub archive state with the documented subsumption
3. ensure the README points to Sounio as the active authority
4. add a clear historical / frozen statement if any ambiguity remains

### Exit Criteria

- MedLang no longer reads like a competing active language authority
- archive or freeze posture is visible without reading deep docs
- the path to Sounio is explicit

## Recommended Order

Execute in this order:

1. `beagle`
2. `sounio`
3. `medlang`
4. `darwin-cockpit`

## Why this order

- Beagle and Sounio set the two sovereign poles first
- MedLang then resolves the most direct language-authority conflict
- Darwin cockpit resolves the most direct platform-authority conflict

## Phase 1 Definition of Done

Phase 1 is complete when:

- Beagle visibly owns platform authority
- Sounio visibly owns language authority
- MedLang is visibly frozen/subsumed
- Darwin cockpit is visibly on an absorption path into Beagle
- the four repos no longer create first-glance authority confusion

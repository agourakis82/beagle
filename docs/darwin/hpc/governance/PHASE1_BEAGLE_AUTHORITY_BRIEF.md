# Phase 1 Brief - Beagle Authority Alignment

## Scope

This brief executes the first repository in `CONVERGENCE_WORKLIST_PHASE1.md`:

- `beagle`

Decision:

- `keep sovereign`

Authority owner:

- `beagle`

## Why This Brief Exists

The ecosystem authority map is already frozen, but `beagle` still presents two public authority mismatches:

1. the GitHub repository description is materially wrong for the current structure
2. the front-door README is directionally correct, but still frames Beagle too narrowly as a `Memory & MCP Layer`

That combination weakens the entire containment model because Darwin lines inherit ambiguity if Beagle does not present itself clearly as the exocortex and platform authority.

## Current State

### Public repo description

Live GitHub repo description observed during the portfolio audit:

> `Medlang is a new language for doctors, by a Doctor`

This is incompatible with the actual repository structure and with ADR-001.

### Current README front door

`README.md` currently opens with:

- `BEAGLE v0.3.0 - Memory & MCP Layer`
- `Exocórtex Científico Pessoal - Rust + Julia + Swift/Tauri`

This is close, but it still understates Beagle's role as:

- exocortex
- service/platform plane
- cockpit
- workflow orchestrator
- Darwin carrier

## Desired State

Beagle should present itself publicly as:

- the exocortical platform of the ecosystem
- the operational cockpit and coordination plane
- the system that carries Darwin scientific lines
- not a language line
- not a legacy MedLang descendant

## Exact Surfaces To Touch

### 1. GitHub repository description

This is not versioned in Git, but it is part of the authority surface.

Recommended replacement:

`Exocortical platform and cockpit for memory, agents, MCP, workflows, and Darwin scientific lines.`

### 2. `/home/devsounio/beagle/README.md`

This is the primary repo-native front door.

Required changes:

- widen the title from `Memory & MCP Layer` to platform / exocortex wording
- keep the v0.3.0 context, but stop making it the whole identity
- explicitly state that Beagle is the platform layer that carries Darwin lines
- add a pointer to the governance docs:
  - `ADR-001_ECOSYSTEM_AUTHORITY_MAP.md`
  - `ADR-002_DARWIN_CONTAINMENT_INSIDE_BEAGLE.md`

## Recommended README Delta

### Title

Current:

- `# BEAGLE v0.3.0 - Memory & MCP Layer`

Recommended:

- `# BEAGLE - Exocortical Platform and Operational Cockpit`

### Subtitle

Current:

- `Exocórtex Científico Pessoal - Rust + Julia + Swift/Tauri`

Recommended:

- `Exocortex for memory, agents, MCP, workflows, and Darwin scientific lines.`

### Opening paragraph

Recommended replacement direction:

`BEAGLE is the exocortical platform of the ecosystem. It provides memory, agents, MCP integration, workflow orchestration, and the operational cockpit that carries Darwin scientific and product lines.`

### Governance pointer

Add one short block near the top:

`Governance: language authority lives in Sounio; platform and operational authority live in Beagle; Darwin lines are carried inside the Beagle-centered platform.`

Then link to:

- `docs/darwin/hpc/governance/ADR-001_ECOSYSTEM_AUTHORITY_MAP.md`
- `docs/darwin/hpc/governance/ADR-002_DARWIN_CONTAINMENT_INSIDE_BEAGLE.md`

## Out of Scope

- runtime refactors
- Darwin code migration
- Sounio integration redesign
- detailed cluster topology updates

## Acceptance Criteria

This brief is complete when:

1. the public GitHub description no longer references MedLang
2. `README.md` clearly presents Beagle as the exocortex / platform / cockpit
3. `README.md` explicitly frames Darwin as carried inside Beagle
4. `README.md` links to the governance ADRs
5. a first-time reader can identify Beagle as platform authority in under one minute

## Follow-up After This Brief

Once this alignment is done:

1. execute the Sounio Phase 1 brief
2. resolve `medlang` archive / subsumption posture
3. define the absorption posture of `darwin-cockpit`

# B24.1 — Intent-to-Execution Planner / Experiment Workbench

`B24.1` adds the first bounded planner that converts an operator-visible intent
into a canonical execution plan inside the Beagle-owned workspace/session
envelope.

## Purpose

The goal of this phase is to stop treating retrieval, compiled context, and
subagent routing as disconnected surfaces. Beagle now resolves a single
operator-facing intent into:

- the right subagent
- the right retrieval lane
- the right compiler profile
- the right GraphRAG mode
- the right recipe or experiment target
- explicit expected outputs, success criteria, and stop conditions

## Scope

- keep planning bounded and operator-aware
- reuse the already-live retrieval, memory compiler, and GraphRAG layers
- preserve the Beagle-owned identity model
- do not auto-execute the plan

## Supported Task Families

- implementation
- analysis / experiment
- manuscript
- interactive editing support is present in policy but is not part of the
  canonical artifact set for this phase

## Runtime Surfaces

- `GET /api/darwin/workstreams/{workstream_id}/planner-policy`
- `POST /api/darwin/workstreams/{workstream_id}/intent-plan`
- `GET /api/darwin/workstreams/{workstream_id}/context-packet`
- `GET /api/darwin/programs/{program_id}/context-packet`
- `GET /api/darwin/workstreams/{workstream_id}/tool-dock/{tool_id}`
- `GET /api/darwin/workstreams/{workstream_id}/workspace-subagent-route`

## Planner Output

Each bounded plan records:

- one canonical intent envelope
- one execution plan
- selected subagent and role
- retrieval lane and dense/sparse backends
- compiler profile and selected memory tiers
- GraphRAG mode and temporal truth view
- recipe target and optional experiment target
- expected outputs
- success criteria
- stop conditions

## Canonical Outcome

The canonical `B24.1` artifact set preserves:

- one planner policy
- one canonical intent
- three resolved execution plans
- coherent identity across implementation / analysis / manuscript
- restart recovery proof
- cluster and Slurm health

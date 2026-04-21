# B15.2 - Premium Tool Dock MVP

## Current status

B15.2 is `GO`.

Canonical deliverables for this phase:

- `crates/beagle-darwin/src/workstream_cockpit.rs`
- `apps/beagle-monorepo/src/http_darwin_hpc.rs`
- `scripts/infrastructure/darwin-hpc/run_premium_tool_dock_mvp_smoke.sh`
- `scripts/infrastructure/darwin-hpc/validate_premium_tool_dock_mvp_smoke.sh`

Canonical smoke evidence lives under:

- `.artifacts/darwin-hpc/premium-tool-dock-mvp/bootstrap-before.json`
- `.artifacts/darwin-hpc/premium-tool-dock-mvp/seed-pilot.json`
- `.artifacts/darwin-hpc/premium-tool-dock-mvp/cockpit.json`
- `.artifacts/darwin-hpc/premium-tool-dock-mvp/cockpit.html`
- `.artifacts/darwin-hpc/premium-tool-dock-mvp/tool-cursor.json`
- `.artifacts/darwin-hpc/premium-tool-dock-mvp/tool-claude-code.json`
- `.artifacts/darwin-hpc/premium-tool-dock-mvp/tool-codex.json`
- `.artifacts/darwin-hpc/premium-tool-dock-mvp/bootstrap-after-restart.json`
- `.artifacts/darwin-hpc/premium-tool-dock-mvp/cockpit-after-restart.json`
- `.artifacts/darwin-hpc/premium-tool-dock-mvp/smoke.json`
- `.artifacts/darwin-hpc/premium-tool-dock-mvp/final-cluster-health.txt`

## Objective

Build the first concrete internal cockpit page for the canonical workstream,
with one Beagle-owned session envelope and one premium tool dock for:

1. `Open in Cursor`
2. `Open Claude Code`
3. `Open Codex`

The cockpit must keep Beagle as the source of truth for:

1. repo
2. branch
3. workspace/session identity
4. governance state
5. handoff
6. last result
7. canonical recipes
8. last successful task

## Architectural decision

- Beagle remains the system of truth; the premium tools are work surfaces, not
  competing state stores
- the tool dock emits Beagle-owned launch metadata from one shared session
  envelope
- the cockpit page is internal and protected by the existing API token gate
- the tool surfaces stay bounded in this MVP: they expose launch envelopes and
  shared context without introducing a new transport runtime for each tool
- lower layers, ingress, edge, HA, providers and the backplane remain out of
  scope

## Target surface

The MVP adds:

1. `GET /api/darwin/workstreams/{id}/cockpit`
2. `GET /api/darwin/workstreams/{id}/tool-dock/cursor`
3. `GET /api/darwin/workstreams/{id}/tool-dock/claude-code`
4. `GET /api/darwin/workstreams/{id}/tool-dock/codex`
5. `GET /darwin/workstreams/{id}/cockpit`

## Success condition

B15.2 closes when:

1. one internal cockpit exists for the canonical workstream
2. the three premium launch surfaces are generated from the same Beagle-owned
   session envelope
3. handoff, last result, recipes and last successful task are visible in one
   place
4. restart/recovery preserves the same workspace/session identity
5. cluster remains green
6. Slurm remains green

## Live result

The live drill passed on workspace `b152-tool-dock-0322063802` with session
`ws-20260322094128`.

The canonical proof captured:

1. `GET /api/darwin/workstreams/beagle-darwin-hpc-governance/cockpit`
   responded successfully and exposed one shared Beagle-owned envelope
2. `GET /darwin/workstreams/beagle-darwin-hpc-governance/cockpit` rendered the
   cockpit page successfully
3. the `cursor`, `claude-code`, and `codex` launch surfaces all carried the
   same workstream/workspace/session identity
4. the cockpit kept handoff, last result, recipes and last successful task
   visible and coherent in one place
5. restart/recovery preserved the same session identity
6. cluster remained green and `Slurmctld(primary)` stayed `UP`

Live seeded workflow facts:

1. seeded workflow profile: `cpu-batch-v1`
2. submitted job id: `56`
3. published result job id: `31`
4. recipe count exposed in the cockpit: `4`
5. `fallback_active=false` before and after restart

# B15.2 Premium Tool Dock MVP GO / NO-GO

## Current status

B15.2 is `GO`.

## GO criteria

B15.2 can move to `GO` only if the live smoke proves:

1. `GET /api/darwin/workstreams/beagle-darwin-hpc-governance/cockpit`
   resolves the canonical workstream through one internal cockpit surface
2. the cockpit envelope exposes the same:
   - repo
   - branch
   - workspace id
   - session id
   - governance state
   - handoff/result/recipe context
3. the three premium launch surfaces:
   - `cursor`
   - `claude-code`
   - `codex`
   are all generated from that same envelope
4. restart/recovery preserves the same `workspace_id` and `session_id`
5. cluster remains green
6. Slurm remains green

## NO-GO conditions

B15.2 remains `NO-GO` if any of the following happen:

1. the cockpit page or JSON surface diverges from the Beagle-owned session
   identity
2. any premium tool surface generates a different workspace/session identity
3. handoff, result or recipe panels disappear or become tool-specific state
4. restart changes the canonical session identity for the same workspace
5. cluster health regresses
6. Slurm health regresses

## Present decision

The live smoke and validator both passed.

Decision: `GO`.

Frozen live evidence:

1. workspace: `b152-tool-dock-0322063802`
2. session: `ws-20260322094128`
3. seeded profile: `cpu-batch-v1`
4. submitted job id: `56`
5. published result job id: `31`
6. restart preserved the same session identity
7. cluster health remained green and `Slurmctld(primary)` stayed `UP`

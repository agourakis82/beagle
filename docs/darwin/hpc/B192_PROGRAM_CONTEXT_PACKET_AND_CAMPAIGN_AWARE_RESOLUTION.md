# B19.2 — Program Context Packet & Campaign-Aware Resolution

Status: GO

## Objective

Create the first live Beagle-owned program/campaign context packet so the
runtime can resolve not only workstream state, but also the larger
program/campaign frame around that work.

## Canonical Shift

Before `B19.2`, the program/campaign layer existed only as a repo-native
contract.

After `B19.2`, Beagle also exposes that layer as a live internal packet that
can be consumed by:

- the cockpit
- premium tool lanes
- internal operator surfaces

## Internal Surfaces

- `GET /api/darwin/programs/{id}/context-packet`
- `GET /api/darwin/campaigns/{id}/context-packet`

## Packet Scope

The packet resolves, in one bounded Beagle-owned envelope:

- `program_id`
- `campaign_id`
- `workstream_ids`
- `active_workstream_id`
- `latest_results`
- `latest_memory_hits`
- `latest_physio`
- `experiment_flags`
- `recommended_next_recipe`
- `evidence_targets`
- `manuscript_targets`

## Included

- repo-native program/campaign resolution
- aggregation over existing workstream context packets
- premium tool dock wiring to the same program/campaign packet paths
- smoke + validator

## Excluded

- public UI
- ingress / edge / HA
- new provider work
- graph runtime expansion
- manuscript automation

## Canonical Target

- program: `beagle-physio-symbolic-exocortex`
- campaign: `expedition-002-hrv-aware`

## Expected Artifacts

- `.artifacts/darwin-hpc/program-context-packet/program-context-packet.json`
- `.artifacts/darwin-hpc/program-context-packet/campaign-context-packet.json`
- `.artifacts/darwin-hpc/program-context-packet/tool-cursor.json`
- `.artifacts/darwin-hpc/program-context-packet/tool-claude-code.json`
- `.artifacts/darwin-hpc/program-context-packet/tool-codex.json`
- `.artifacts/darwin-hpc/program-context-packet/program-context-packet-after-restart.json`

## Canonical Live Proof

- workspace: `b192-program-context-0323052816`
- session: `ws-20260323083143`
- program packet resolved:
  `beagle-physio-symbolic-exocortex -> expedition-002-hrv-aware -> beagle-darwin-hpc-governance`
- tool dock surfaces shared the same Beagle-owned packet paths for `Cursor`,
  `Claude Code`, and `Codex`
- restart preserved packet coherence with the same workspace/session identity
- cluster stayed green and `Slurmctld(primary)` remained `UP`

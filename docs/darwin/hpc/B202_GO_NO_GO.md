# B20.2 — GO / NO-GO

Status: GO

## GO Criteria

This phase is `GO` if:

- the canonical workspace habitat from `B20.1` remains green
- `GET /api/darwin/workstreams/{id}/cursor-remote-lane` resolves live
- the Cursor lane carries the same `workstream_id`, `workspace_id`, and `session_id` as the
  habitat/context packet
- `tool-dock/cursor` points to the same remote lane path
- the workspace context env contains the Cursor lane path
- restart preserves the same identity
- cluster stays green
- `Slurmctld(primary)` stays `UP`

## Decision

`GO`.

What is already true:

- the Cursor lane is now a first-class Beagle runtime object
- the lane is derived from the same Beagle-owned habitat and context packet
- the workspace and the lane stay coherent before/after restart
- the tool dock keeps Cursor on the same canonical workspace/session envelope
- the live smoke and validator pass on top of the green cluster workspace habitat

What was previously blocked is now closed by `B20.2a`:

- direct Cursor remote attach is now proven through the same Beagle-owned workspace via the
  bounded native attach path
- `B20.2` therefore remains the canonical lane-metadata phase, while `B20.2a` closes the native
  premium attach proof

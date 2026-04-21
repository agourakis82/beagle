# B22.4 — Retrieval-Aware Tool Context

## Objective

Promote the already-active hybrid retrieval spine into Beagle's daily work surfaces so retrieval
materially shapes:

- workstream context packets
- program/campaign context packets
- tool dock launch metadata
- role-aware subagent routing
- cross-subagent handoff propagation

## Canonical Scope

- Keep `Qdrant` as the canonical store direction.
- Keep `voyage-4-large` as the promoted dense backend.
- Keep `local-lexical` as the sparse path.
- Keep reranking disabled in this phase.
- Do not reopen `B20.x` or `B21.x`.

## What Changed

The runtime now derives an explicit retrieval summary from the bounded hybrid query already used to
hydrate the workstream context packet. That retrieval summary is propagated into:

- `WorkstreamContextPacket.retrieval_context`
- `ProgramContextPacket.retrieval_context`
- premium tool launch metadata in the tool dock
- retrieval-aware subagent routing when no stronger explicit selector is present
- subagent handoff propagation metadata

The routing policy remains bounded:

- `preferred_subagent` still wins
- `work_mode` still wins
- retrieval guidance only influences selection when the requested tool is compatible with the
  suggested subagent

## Canonical Proof

The live smoke for this phase produces artifacts in:

`beagle/.artifacts/darwin-hpc/retrieval-aware-tool-context/`

Key proof points:

- retrieval hits are present in `context-packet` and `workspace-launch-resume`
- `program context` preserves retrieval guidance
- `tool-dock/claude-code` carries retrieval-aware recommendation metadata
- `workspace-subagent-route?tool_id=claude-code` can resolve via `selection_source=retrieval-context`
- `workspace-subagent-handoff` propagates retrieval-aware context
- restart preserves identity and retrieval-aware state

## GO Definition

`B22.4 = GO` if:

- retrieval materially appears in launch/resume context
- retrieval influences at least one routing or handoff path
- the same Beagle-owned identity is preserved
- restart remains coherent
- cluster stays green
- `Slurmctld(primary)` stays up

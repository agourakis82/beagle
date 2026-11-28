# BEAGLE Restore Backlog

Generated: 2026-05-16 16:40:30

## P0: Stop Further Drift

1. Declare `BEAGLE_NORTH_STAR.md` and `docs/BEAGLE_v0_1_CORE.md` the restoration constitution.
2. Freeze Workbench/Warp/Project Cockpit, Sounio workspace, and exotic cognitive modules until each has a tested path into the core scientific loop.
3. Rewrite completion-claim docs that say `100%`, `production ready`, or `operational` without current verification.

## P1: Recover the Core Scientific Loop

1. Revalidate `apps/beagle-monorepo` pipeline: question -> Darwin -> Observer -> HERMES -> artifact -> feedback.
2. Revalidate `crates/beagle-darwin` and `crates/beagle-darwin-core` against GraphRAG/Self-RAG docs.
3. Revalidate `crates/beagle-memory` and `beagle-mcp-server` as the conversation memory/control plane.
4. Revalidate `crates/beagle-triad`, `crates/beagle-hermes`, and `crates/beagle-feedback` with one end-to-end draft review.

## P2: Preserve Useful Extensions

1. Keep Darwin HPC/Julia/PBPK/KEC only where it produces scientific artifacts or improves retrieval.
2. Keep iOS/watch surfaces only for capture, physio, memory, and core-server operation.
3. Keep observability only for the core loop, not vanity dashboards.

## P3: Quarantine or Delete

1. Quarantine modules classified as `scope-drift`, `stub`, or `documentation-fiction` in `BEAGLE_LINE_MAP.csv`.
2. Delete only after dependency checks prove no core path imports them.
3. Move infra-specific Sounio/NetBox/OrangeFS material to a separate operations repo if still needed.

## Acceptance Gates

- `make rescue-check` passes.
- One pipeline run creates a real draft artifact and feedback record.
- One memory query retrieves a prior thought/conversation.
- One Triad review produces a critique tied to evidence.
- No doc may claim production/completion without command evidence and date.

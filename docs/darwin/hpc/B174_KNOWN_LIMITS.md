# B17.4 — Known Limits

Status: GO

## Current Limits

- This phase validates the first live `Expedition 002` batch, not a full statistical study.
- Human ratings are not yet meaningfully populated in the first live batch; the baseline analysis is therefore run-report-first and physiologically anchored rather than human-judgment-heavy.
- The experiment runner currently executes outside the cluster pod and then syncs canonical experiment tags back into Beagle data. This keeps the live core path canonical without rebuilding the runtime image just for experiment binaries.
- Strong compile proof for this phase remains the Rust `1.89` container path when the host toolchain is below the repo lockfile MSRV.
- The current cluster still runs without configured Qdrant/Neo4j, so the live experiment baseline is grounded in the canonical pipeline/observer path rather than a full retrieval-heavy memory substrate.

## Out of Scope

- Apple / Vision client surfaces
- clinical analytics
- LoRA / training loop
- public UI
- large-scale notebook/statistical pipeline

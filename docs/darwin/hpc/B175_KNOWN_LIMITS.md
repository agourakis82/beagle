# B17.5 — Known Limits

Status: STAGED / READY FOR HUMAN EVAL

## Current Limits

- The current canonical readiness batch is `b175-exp002-human-eval-0322153547`, and it intentionally records `ratings_applied = 0`.
- The canonical protocol, blinded packet, persistence path, and analysis path are repo-native and ready, but the phase does not honestly become `GO` until a real human fills the packet.
- The current blinded packet uses deterministic opaque ordering derived from run ids rather than a separate randomization service. This is sufficient for bounded internal evaluation, but not a full blinded study platform.
- The current analysis aggregates one canonical human judgment per run cleanly, but it is not yet a multi-rater adjudication system.
- The packet is markdown-first. PDF paths remain available in the audit key, but the evaluator-facing packet is intentionally compact.
- Strong compile proof for this phase remains the Rust `1.89` container path when the host toolchain is below the repo lockfile MSRV.

## Out of Scope

- public evaluation UI
- multi-rater arbitration
- large-scale statistics / notebooks
- paper writing
- Expedition 003 as the main line

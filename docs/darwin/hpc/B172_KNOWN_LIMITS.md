# B17.2 — Known Limits

- This phase is bounded physiological snapshot ingestion and latest-state retrieval only.
- It does not build the Apple app, public UI, or broad clinical analytics.
- Historical physio replay remains out of scope; this phase freezes the latest canonical snapshot path.
- Memory uses the canonical latest snapshot path, but does not yet expose full physiological history.
- Experiment attachment remains bounded and indirect; this phase stabilizes the physiological contract first.
- Strong compile proof for this phase continues to come from the containerized core-server build and the live smoke; the broader `beagle-observer` test suite still has a pre-existing unrelated compile issue in `hrv_realtime.rs`.

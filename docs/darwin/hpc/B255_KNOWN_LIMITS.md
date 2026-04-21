# B25.5 — Known Limits

- Git metadata is best-effort. The run capsule records branch/commit/patch ref only when the
  Beagle runtime can observe a local git checkout at runtime.
- Image metadata is best-effort. If the active runtime does not expose an image reference/digest,
  the capsule keeps those fields explicit but empty rather than guessing.
- The replay request is a bounded contract, not a free-form re-execution engine. Replays still
  depend on the existing workbench reservation and scheduler flow.
- The run diff explains code/config/environment/result changes from the captured capsule facts.
  It does not attempt to infer semantic causality beyond the recorded runtime evidence.

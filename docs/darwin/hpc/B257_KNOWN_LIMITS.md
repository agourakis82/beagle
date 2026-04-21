# B25.7 — Known Limits

- Replay/fork execution is still bounded to the latest replay request. This phase does not add
  arbitrary historical run selection or a free-form lineage editor.
- The replay/fork receipt preserves source lineage explicitly, but the underlying run capsule
  parentage still follows the latest canonical capsule at execution time.
- Code provenance remains best-effort when the runtime cannot observe a local checkout directly;
  operators can still supply bounded provenance capture input on the replay/fork request.
- Replay/fork execution reuses the existing compute profile from the replay request. This phase
  does not add profile-mutation or policy-bypass semantics.

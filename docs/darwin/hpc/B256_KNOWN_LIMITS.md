# B25.6 — Known Limits

- Git-aware provenance is strongest when the runtime can see the workspace checkout directly.
  When it cannot, B25.6 relies on a bounded workspace-provided attestation instead of guessing.
- `patch_ref` is a hash of the local diff payload, not a full patch archive store.
- Lockfile fingerprints are best-effort across a bounded list of canonical lockfile names; files
  outside that list are not fingerprinted in this phase.
- The run diff explains code/config/environment/result drift from captured facts. It does not
  infer semantic causality beyond the recorded provenance envelope.

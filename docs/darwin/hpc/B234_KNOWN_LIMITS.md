# B23.4 Known Limits

- contradiction detection is intentionally bounded in this phase
  - the pilot marks explicit state flips on the same temporal subject
  - it does not attempt open-ended logical inconsistency resolution
- temporal grouping is derived from canonical Beagle refs already present in
  memory payloads
  - mainly `claim_refs`, `result_refs`, and bounded procedural signatures
- context packets only carry bounded temporal summaries
  - full temporal tracks remain queryable through the temporal memory runtime
- editorial/scientific readiness limits are unchanged
  - `claim-linked-human-eval-pending` remains explicit where it already applies

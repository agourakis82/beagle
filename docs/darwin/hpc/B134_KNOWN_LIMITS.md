# B13.4 Known Limits

## Current limits

- the drill proves fallback discipline for one promoted scope, not for all work
  at once
- the drill records fallback semantics inside the Beagle workspace plane; it is
  not a general workstation management system
- the drill proves fallback entry and return discipline, not heavy VM-side work
  during fallback
- the VM still exists as fallback support; this phase only proves that it stays
  fallback-only instead of drifting back to primary
- the drill uses one bounded operator path and one short fallback window
- no new providers, ingress, HA or topology are added here

## Interpretation

B13.4 is about behavior and discipline: keeping fallback explicit and bounded
after default-dev-plane promotion. It is not a platform expansion phase.

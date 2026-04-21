# B13.6 Known Limits

## Current limits

- the phase validates repeated real use inside the already-promoted scope; it
  does not promote all possible work globally
- the proof is based on one canonical workspace line at a time
- restart/recovery is proven once at the end of the three-loop sequence
- fallback is only validated if it actually occurs during the sustained drill;
  this phase does not force a fallback event
- no provider expansion, ingress, edge, HA, topology or lower-layer reopening
  is introduced here

## Interpretation

B13.6 is a sustained-use validation phase for the current default dev plane,
not a new infrastructure phase and not a global migration of all work at once.

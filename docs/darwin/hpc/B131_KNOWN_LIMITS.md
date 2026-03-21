# B13.1 Known Limits

## Current limits

- the pilot proves Beagle as the canonical session/handoff/workflow plane, not
  Beagle as a full in-cluster IDE
- the editable checkout still lives in the canonical working tree on the active
  branch
- the cutover is proven for one repo, one branch and one development loop at a
  time
- the VM can still exist as fallback support; the phase only removes its role
  as the mandatory center for this pilot
- the phase reuses the existing bridge, control surface, workspace plane and
  result plane exactly as they already exist

## Interpretation

B13.1 is about proving that real development continuity can live on the Beagle
workspace plane. It is not a public UI phase, an ingress phase, or a
multi-workspace IDE phase.

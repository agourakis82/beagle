# B12.8 Known Limits

## Current limits

- the advanced operator workflow is still single-profile and single-workspace
  at a time
- `gpu-single-v1` is the chosen advanced path; this phase does not broaden
  consumers, providers or admission
- operator context remains metadata-first; the Beagle pod is not a full IDE or
  live git checkout
- result resolution still reuses the current published object-plane results
  rather than materializing a new GPU publication path in this phase
- the pilot proves GPU execution on `r740-proxmox`, but it does not change the
  existing cluster topology or move GPU infrastructure into Kubernetes

## Interpretation

This phase is about proving one advanced but still bounded operator workflow on
top of the current Beagle stack, not about broadening topology, providers,
consumer scope or self-service.

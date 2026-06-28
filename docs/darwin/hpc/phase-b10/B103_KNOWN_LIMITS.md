# B10.3 Known Limits

## Current Limits

- the first canonical retention run is dry-run only
- no delete markers or lifecycle rules are pushed into RGW in this phase
- cleanup still depends on future enforcement work after policy approval
- object classes are profile-driven, not tenant-driven
- the current object set has no delete-eligible candidates yet under the frozen
  policy windows

## Interpretation

B10.3 proves lifecycle policy discovery and evaluation first. It does not yet
promote destructive cleanup as part of the canonical path.

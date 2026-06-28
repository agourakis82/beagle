# B11.1 Known Limits

## Current Limits

- job resolution still starts from `job_id`, with live Slurm lookup attempted
  first and published-manifest fallback second
- object retrieval still depends on platform-owned host-side credentials on
  `t560-proxmox`
- fallback to host-side retrieval remains available for bounded recovery
- no object index or query catalog exists yet
- object-backed retrieval is only canonical for bundles that were already
  published into the result plane

## Interpretation

B11.1 moves artifact truth into the object plane for gateway retrieval and keeps
historical jobs readable after live Slurm queryability ages out, but it does not
yet add a separate result index or independent query model.

# OrangeFS First Rollout Plan

This is the first serious OrangeFS rollout for the current cluster shape.

## Design principles

- do not break current Kubernetes production paths
- do not move workspaces first
- start with the AI/HPC data plane
- keep local NVMe as the near-GPU hot tier
- validate the client path on current nodes before widening scope

## Phase A: single-node proof

Start on `t560` with a single-node OrangeFS proof to validate:

- service startup
- configuration format
- mount behavior
- Linux client path on the current kernel

This is development proof only, not the final shape.

## Phase B: first server pair

Bring up:

- `t560`
- `5860`

as the first OrangeFS server pair.

Goals:

- validate distributed data placement
- validate multi-server behavior
- validate client access from `r740` and `r770`

## Phase C: client proof

Validate clients on:

- `r740`
- `r770`

Then extend to:

- `DL380`

when it arrives.

## Phase D: first data-plane mountpoints

Use OrangeFS only for:

- datasets
- checkpoints
- scratch

Keep outside OrangeFS:

- live workspaces
- Grafana / Prometheus state
- Kubernetes platform state

## Exit criteria

- OrangeFS servers are stable on `t560` and `5860`
- clients on `r740` and `r770` mount cleanly
- benchmark numbers are repeatable
- training/checkpoint canaries succeed
- Kubernetes production path remains intact

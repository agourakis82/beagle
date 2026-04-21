# B13.5 GO / NO-GO

## Current status

B13.5 is currently `GO`.

Current evidence:

1. live workspace policy exposes
   `promotion_scope=beagle-darwin-hpc-general-noninfra`
2. the live policy kept `beagle-cluster` as default and VM as `fallback-only`
3. one real `deepseek` bridge request completed through the expanded scope
4. one real `cpu-short-v1` workflow completed through the expanded scope as job
   `47`
5. fallback start and return remained explicit, bounded and recorded
6. the same session `ws-20260321162052` survived deploy, return and restart
7. cluster remained green
8. Slurm remained green

## GO if

1. the live workspace policy exposes the expanded scope explicitly
2. `beagle-cluster` remains the default plane before and after the drill
3. VM remains `fallback-only`
4. one real workflow completes through the expanded scope
5. fallback entry and return remain explicit, bounded and recorded
6. restart/recovery preserve the same session and handoff continuity
7. cluster remains green
8. Slurm remains green

## GO-WITH-BLOCKER if

1. scope expansion semantics and placement are correct
2. but one bounded build, deploy or runtime issue blocks the live smoke
3. and the underlying Beagle backplane remains healthy

## NO-GO if

1. the phase reopens ingress, edge, HA, topology or provider expansion
2. VM regains primary status for the promoted scope
3. fallback stops being explicit and bounded
4. the expanded scope is not actually visible in live workspace state

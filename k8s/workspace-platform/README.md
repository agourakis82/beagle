# Sounio Workspace Control Plane

This directory retains the Beagle-side resources that keep the Sounio lane
fleet recoverable when the workspace Pod or its presentation layer disappears.

## Resources

- `sounio-fleet-guardian.yaml` runs outside the workspace Pod and reconciles
  the durable Sounio fleet catalog every five seconds.
- `lanes-ensure-cronjob.yaml` remains the additive fallback for lanes that have
  not yet migrated to the durable fleet runtime.
- `workspace-agent-build-job.yaml`, `templates/`, and `catalog/` hold the
  existing workspace image and habitat inputs.

The guardian currently owns recovery for `fable-1`, `cursor-1`, and
`grok-cli2`. The legacy CronJob excludes those slots, so two recovery systems
cannot start the same lane.

## Recovery authority

The guardian has start-only authority. It first observes the catalog without
authority, then runs one bounded recovery cycle using private per-slot budget
and latch directories. A deterministic start failure writes a persistent
`<slot>.halted.json` latch for that slot while reconciliation continues for the
others. Clearing a latch requires the exact slot and desired catalog through
`sounio-fleet recovery-latch-clear`.

The Deployment depends on cluster-owned resources that are deliberately not
duplicated here:

- the `sounio-workspace-governance` service account
- the `sounio-workspace-control-0` Pod and `workspace-ssh` container
- the shared runtime under
  `/workspace/sounio/.git/sounio-coord-runtime/current`
- the durable fleet catalog and recovery directories on the workspace volume

The manifests were exercised against those live resources before publication.

## Apply

Validate the runtime capabilities before deploying the guardian:

```bash
kubectl apply --dry-run=server \
  -f k8s/workspace-platform/sounio-fleet-guardian.yaml
kubectl apply -f k8s/workspace-platform/sounio-fleet-guardian.yaml
kubectl -n beagle rollout status deployment/sounio-fleet-guardian
```

Install the legacy fallback only while unmigrated lanes remain:

```bash
kubectl apply --dry-run=server \
  -f k8s/workspace-platform/lanes-ensure-cronjob.yaml
kubectl apply -f k8s/workspace-platform/lanes-ensure-cronjob.yaml
```

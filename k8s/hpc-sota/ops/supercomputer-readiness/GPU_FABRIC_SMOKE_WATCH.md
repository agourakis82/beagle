# GPU Fabric Smoke Watch

This runbook covers the guarded watcher for the dedicated `10.210` GPU fabric.

The watcher exists because the Slurm lane may legitimately hold all GPUs while
the network fabric is otherwise ready. It avoids manual polling and does not
fight the scheduler.

## Modes

Safe observation mode:

```bash
/home/devsounio/beagle/k8s/hpc-sota/ops/supercomputer-readiness/gpu-fabric-smoke-watch.sh \
  --watch --interval 60
```

Operator test-window mode:

```bash
/home/devsounio/beagle/k8s/hpc-sota/ops/supercomputer-readiness/gpu-fabric-smoke-watch.sh \
  --run-on-ready --interval 60 --transport ib
```

`--watch` never creates smoke jobs. `--run-on-ready` creates exactly one smoke
job after `gpu-fabric-gate.sh phase3-ib-ready` passes.

## Systemd

Install the units without enabling the timer:

```bash
/home/devsounio/beagle/k8s/hpc-sota/ops/supercomputer-readiness/install-gpu-fabric-smoke-watch-timer.sh
```

Enable the safe watch timer only when you want periodic readiness evidence:

```bash
sudo systemctl enable --now darwin-gpu-fabric-smoke-watch.timer
```

Run the one-shot smoke watcher manually during an explicit test window:

```bash
sudo systemctl start darwin-gpu-fabric-smoke-run-on-ready.service
```

## Logs

Watcher logs are written under:

```text
/home/devsounio/beagle/k8s/hpc-sota/ops/supercomputer-readiness/artifacts/gpu-fabric-smoke-watch/
```

Systemd logs:

```bash
journalctl -u darwin-gpu-fabric-smoke-watch.service
journalctl -u darwin-gpu-fabric-smoke-run-on-ready.service
```

## Safety Rules

- Do not set `DARWIN_GPU_FABRIC_ALLOW_BUSY=1` for this watcher.
- Do not enable the run-on-ready service as a timer.
- Do not cancel Slurm jobs from this path.
- Treat a failed readiness attempt as evidence, not as a reason to bypass the
  GPU lease gate.

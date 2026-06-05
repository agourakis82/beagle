# OrangeFS Multi-TiB Change Plan

This is the live-change plan for promoting OrangeFS from the repaired
sub-terabyte export to a real multi-terabyte shared filesystem.

Current live truth:

- exported capacity: about `0.91 TiB`
- active filesystem: `orangefs_lab_2n`
- active servers:
  - `server01` on `t560-proxmox`
  - `server02` on `5860-proxmox`
- current limiting backend:
  - `5860:/srv/orangefs-server02-store`

Primary growth candidate:

- `t560-proxmox:/mnt/datasets`
- observed capacity: about `2.44 TiB` free
- reason: largest currently observed candidate and does not steal near-GPU
  local tiers from `r740` or `r770`

## Hard Rules

- Do not mutate live OrangeFS without an explicit maintenance window.
- Do not use the 5860 thin pool as the growth target.
- Do not count local disks as OrangeFS capacity until they are exported by a
  live OrangeFS server and visible from clients.
- Do not move workspace roots, Prometheus, Grafana, or Kubernetes platform
  state onto OrangeFS.
- Run the maintenance snapshot immediately before changes.

## Required Preflight

```bash
/home/devsounio/beagle/k8s/hpc-sota/ops/supercomputer-readiness/orangefs-maintenance-snapshot.sh
/home/devsounio/beagle/k8s/hpc-sota/ops/supercomputer-readiness/orangefs-growth-gate.sh preflight
```

Expected pre-change state:

- current export is below `2 TiB`
- `t560:/mnt/datasets` has at least `1.25 TiB` available
- current configs and systemd units are captured under
  `ops/supercomputer-readiness/artifacts/orangefs-maintenance-*`

## Proposed First Growth Shape

Keep the current 2-server shape, but move `server01` data/meta/log from
`/zfast/orangefs-lab/two-node/server01` to a dedicated path under
`/mnt/datasets/orangefs-lab/server01`.

This is less invasive than adding `server03` immediately because the current
filesystem has handle ranges and service assumptions around two servers. It
also moves the larger side of the two-server export to the largest stable local
pool currently available.

Target paths:

```text
t560:/mnt/datasets/orangefs-lab/two-node/server01/data
t560:/mnt/datasets/orangefs-lab/two-node/server01/meta
t560:/mnt/datasets/orangefs-lab/two-node/server01/log
t560:/mnt/datasets/orangefs-lab/two-node/etc/orangefs_lab_2n.conf
```

Keep server02 unchanged during the first promotion:

```text
5860:/srv/orangefs-server02-store/data
5860:/srv/orangefs-server02-store/meta
5860:/srv/orangefs-server02-store/log
```

The `server02` backing store stays unchanged, but `server02` still receives the
same generated `orangefs_lab_2n.conf` at its existing config path:

```text
5860:/var/lib/orangefs-lab/two-node/etc/orangefs_lab_2n.conf
```

That keeps both OrangeFS servers on the same filesystem map while only moving
`server01` data, metadata, and log paths.

## Prepared Executor

The guarded executor is:

```bash
/home/devsounio/beagle/k8s/hpc-sota/ops/supercomputer-readiness/orangefs-multitb-maintenance-executor.sh \
  --dry-run \
  --snapshot-dir /home/devsounio/beagle/k8s/hpc-sota/ops/supercomputer-readiness/artifacts/orangefs-maintenance-20260525T180911Z
```

It defaults to dry-run and prints the full maintenance sequence. Live execution
requires both `--apply` and `ORANGEFS_MULTITB_CONFIRM=APPLY`.

Before printing or applying the sequence, the executor runs strict checks:

- snapshot age must be under `SNAPSHOT_MAX_AGE_HOURS`, default `6`
- `t560:/mnt/datasets` must exist and have at least
  `MIN_TARGET_AVAIL_TIB`, default `1.25`
- current `server01` data/meta/log source directories must exist
- target `server01` data/meta/log paths must not already be mountpoints
- OrangeFS server/client systemd units must be known on the relevant hosts
- generated config must reference the expected target paths

Every executor run also creates an audit artifact under:

```text
/home/devsounio/beagle/k8s/hpc-sota/ops/supercomputer-readiness/artifacts/orangefs-multitb-runs/
```

Each run directory contains `report.env`, target artifact hashes, and captured
preflight/postflight outputs where applicable. The executor uses an exclusive
lock at `/tmp/darwin-orangefs-multitb-maintenance.lock`; concurrent apply,
dry-run, or rollback attempts fail closed with `result=lock_busy`.

Before opening the real window, generate a read-only go/no-go packet:

```bash
/home/devsounio/beagle/k8s/hpc-sota/ops/supercomputer-readiness/orangefs-multitb-gonogo.sh \
  --snapshot-dir /home/devsounio/beagle/k8s/hpc-sota/ops/supercomputer-readiness/artifacts/orangefs-maintenance-20260525T180911Z
```

The packet captures growth preflight, executor dry-run, capacity doctor, SOTA
doctor, apply command, rollback command, and a `GO_FOR_EXPLICIT_MAINTENANCE_WINDOW_ONLY`
or `NO_GO` decision. By default the script exits non-zero for `NO_GO`, so it can
be used in automation; pass `--always-zero` for report-only runs.

Rollback is also built into the same executor and defaults to dry-run:

```bash
/home/devsounio/beagle/k8s/hpc-sota/ops/supercomputer-readiness/orangefs-multitb-maintenance-executor.sh \
  --rollback \
  --snapshot-dir /home/devsounio/beagle/k8s/hpc-sota/ops/supercomputer-readiness/artifacts/orangefs-maintenance-20260525T180911Z
```

Live rollback requires `ORANGEFS_MULTITB_CONFIRM=ROLLBACK`. It restores the
snapshot config and systemd units for both OrangeFS servers, restarts server
and client services, and reruns capacity/readiness doctors.

## Rollback

Rollback must restore the previous snapshot:

- original `orangefs_lab_2n.conf`
- original `orangefs-server01.service`
- original `orangefs-server02.service`
- original server data/meta paths

The snapshot created by `orangefs-maintenance-snapshot.sh` is the rollback
evidence bundle. Do not start the window without it.

## Exit Criteria

The change is not successful until all are true:

- OrangeFS remounts on clients
- `df -hT /var/lib/orangefs-lab/client-runtime/mnt` reports at least `2 TiB`
- training canary can write dataset/checkpoint artifacts
- text integrity probe passes
- `sota-readiness-doctor.sh` reports no OrangeFS capacity warning

## Explicit Non-Goal

This plan does not yet promote `r740`, `r770`, or DL380 as OrangeFS servers.
Those are later topology decisions. The first goal is to make the existing
shared filesystem honestly multi-terabyte with the least topology churn.

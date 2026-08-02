# SlurmDBD Migration Blueprint

This is the safe migration plan for evolving `slurmdbd` beyond the current
externalized K8s MariaDB backend without touching the live backend prematurely.

Use this together with:

1. [SLURMDBD_EVOLUTION.md](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/SLURMDBD_EVOLUTION.md)
2. [README.md](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/README.md)
3. [values/slurm-pilot-values.external-db.example.yaml](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/values/slurm-pilot-values.external-db.example.yaml)
4. [scripts/19-export-slurmdbd-snapshot.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/19-export-slurmdbd-snapshot.sh)
5. [scripts/25-preflight-external-slurmdbd-db.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/25-preflight-external-slurmdbd-db.sh)
6. [scripts/26-preflight-cockpit-vm-db.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/26-preflight-cockpit-vm-db.sh)

## Current truth

Today the live path is:

- `slurmdbd` in Kubernetes
- current `StorageHost=10.100.100.2`
- host-local MariaDB on `t560` remains the rollback target
- host-local MariaDB on `t560` is also the active backend today
- backup/restore is the guard-rail
- failover is not implemented yet

That is why the current state is **yellow, not red**.

The current migration candidate is:

- `slurm-pilot-mariadb-ext`

Current honest status:

- the externalized K8s candidate remains resumable, but it is not the source of
  truth today
- the alias and host-visible DNS path for that candidate are solved
- Ceph RBD attach churn was real, but it is not the active blocker anymore
- the deeper blocker uncovered during that line of work was AppArmor, not
  seccomp:
  - containers under the default `cri-containerd.apparmor.d` profile could not
    create AF_UNIX sockets
  - common failure signature:
    - `Can't start server : UNIX Socket : Permission denied`
- the candidate path therefore remains useful as a migration target, not as the
  active backend description

## Path comparison

### Externalized K8s backend now

- not live today
- operationally simple for Helm-managed cutover and rollback once resumed
- still tied to the `t560` failure domain because its current pod plan lives
  there

### Dedicated VM next

- best path if we want a true host-separation win
- should keep the same narrow DNS contract pattern:
  - `slurmdbd-mariadb-ext.darwin.lan`
- should be provisioned as a dedicated DB host on the control-plane network
- should not share responsibilities with the existing `cockpit` VM long-term

For now, treat the candidate endpoint shape as:

- service ClusterIP `10.96.196.141`
- stable alias `slurmdbd-mariadb-ext.darwin.lan`

## Desired cutover shape

The next database endpoint should be:

- a stable DNS name or stable IP
- durable storage
- backup and restore tested before cutover
- reachable from:
  - `t560`
  - the `slurm-pilot-accounting` pod
  - the `slurm-pilot-login` pod

Good candidates:

- dedicated VM on the control-plane network
- dedicated Kubernetes MariaDB with explicit storage and ops model
- external managed MariaDB if it fits the lab

Interim but less ideal candidate:

- the existing `cockpit` VM on `10.100.100.166`
  - technically capable
  - operationally noisy because it already carries observability workloads
  - acceptable as a stopgap, not the clean long-term home
  - current stopgap prep status:
    - MariaDB is installed and listening on `10.100.100.166:3306`
    - `slurm_acct_db` exists
    - `slurm@'%'` is provisioned with the cluster password
    - the VM now carries a persistent return route for pod CIDR `10.0.0.0/16`
      via `10.100.100.2`
    - matching Helm overlay:
      - [values/slurm-pilot-values.cockpit-vm-db.yaml](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/values/slurm-pilot-values.cockpit-vm-db.yaml)

## Safe migration phases

### Phase A: preflight only

Do not touch the live backend yet.

Run:

```bash
cd /home/devsounio/beagle/k8s/hpc-sota/slurm-pilot
EXTERNAL_DB_HOST=your-db-host \
EXTERNAL_DB_PORT=3306 \
bash scripts/25-preflight-external-slurmdbd-db.sh
```

This should prove:

- fresh logical dump exists
- fresh migration-grade snapshot exists
- current `sacctmgr` / `sacct` reads are healthy
- the target host resolves
- the target host is reachable from the Slurm login pod
- the `mariadb-password` secret still exists

Known-good example today:

```bash
cd /home/devsounio/beagle/k8s/hpc-sota/slurm-pilot
EXTERNAL_DB_HOST=10.100.100.166 \
bash scripts/25-preflight-external-slurmdbd-db.sh
```

Convenience wrapper for the same stopgap target:

```bash
cd /home/devsounio/beagle/k8s/hpc-sota/slurm-pilot
bash scripts/26-preflight-cockpit-vm-db.sh
```

### Phase B: seed the target backend

Create or prepare the external MariaDB backend.

Then:

1. take a fresh snapshot
2. restore it into the target backend
3. validate schema and row counts

At this phase, the live `slurmdbd` path remains on `10.100.100.2`.

### Phase C: dry-run cutover manifest

Prepare an overlay equivalent to:

- [values/slurm-pilot-values.external-db.example.yaml](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/values/slurm-pilot-values.external-db.example.yaml)

But with the real host and secret references.

Validate that:

- DNS is stable
- credentials are in Kubernetes
- rollback overlay back to `10.100.100.2` is ready

### Phase D: controlled cutover window

During the maintenance window:

1. take a fresh snapshot with:
   - [scripts/19-export-slurmdbd-snapshot.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/19-export-slurmdbd-snapshot.sh)
2. restore the snapshot into the target backend
3. `helm upgrade` the Slurm pilot with the external DB overlay
   - for the prepared cockpit stopgap, use:
     - `EXTERNAL_DB_VALUES_FILE=/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/values/slurm-pilot-values.cockpit-vm-db.yaml`
4. validate:
   - `sacctmgr list cluster`
   - `sacct`
   - one real batch job

### Phase E: rollback window

Keep the old backend effectively read-only and rollback-ready until confidence
is high.

Rollback means:

- restore the known-good overlay pointing back to `10.100.100.2`
- re-run the accounting read checks
- keep the target backend for forensic comparison, not immediate deletion

## Hard rules

1. Do not tie this database migration to OrangeFS work.
2. Do not cut over without a fresh logical snapshot.
3. Do not delete the host-local backend on the same day as first cutover.
4. Do not accept “pod is Running” as sufficient proof.
5. Do not call the migration done until `sacctmgr`, `sacct`, and a real batch
   job all pass.

## Exit criteria for real cutover work

The migration can be treated as ready to schedule only when:

- preflight passes cleanly
- the target backend has been seeded successfully
- credentials and overlay are prepared
- rollback overlay is prepared
- the maintenance window is explicitly chosen

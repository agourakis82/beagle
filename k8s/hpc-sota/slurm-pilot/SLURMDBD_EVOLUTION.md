# SLURMDBD Backend Evolution

## Current state

The Slurm pilot is already operational with:

- `slurmdbd` live in Kubernetes
- host-local MariaDB on `t560` currently back in production at `10.100.100.2`
- externalized K8s MariaDB candidate still defined at `slurmdbd-mariadb-ext.darwin.lan`
- daily logical backups
- versioned tuning in the repo

That is strong enough for a serious pilot, but it is still not a true
multi-host accounting design because the live MariaDB pod currently runs on
`t560-proxmox`.

## Why evolve it

The next failure domain to reduce is not Slurm itself. It is the MariaDB
backend that stores accounting state.

Today:

- loss of `t560` still hurts because the current live MariaDB backend is again
  the host-local service on `t560-proxmox`
- the externalized K8s backend remains coupled to `t560` anyway because its pod
  is node-pinned there today
- backups exist, but failover is still manual

The control plane is therefore functional, but not yet resilient.

## Target path

### Phase 1: current pilot

- `slurmdbd` in Kubernetes
- live MariaDB currently back on `10.100.100.2`
- host-local MariaDB on `t560` is both the live backend and rollback anchor
- daily dumps to `/var/backups/slurm-pilot-mariadb/`

Use this while:

- validating policy
- proving workloads
- keeping operational complexity low

### Phase 2: dedicated resilient backend

Move MariaDB off the current K8s-on-`t560` service and onto a dedicated backend
with a stable service endpoint and a real host-failure boundary.

Good options:

- dedicated VM or container on the control-plane network
- dedicated Kubernetes MariaDB with persistent storage and explicit ops model
- external managed MariaDB if that fits the lab

### Current candidate vs dedicated VM

- Current live path:
  - `10.100.100.2`
  - operationally simple and already verified from the `slurmdbd` pod
  - still fully tied to the `t560` failure domain
- Dedicated VM path:
  - best next step if the goal is to reduce `t560` coupling for real
  - should live on the control-plane network with a narrow role
  - should not reuse the existing `cockpit` VM as the final long-term home

Requirements:

- stable IP or DNS name
- durable storage
- backup and restore tested
- maintenance window documented

### Phase 3: higher-availability database tier

Only after the pilot earns it, move to:

- replicated MariaDB/Galera
- or another resilient MariaDB topology with a stable writer endpoint

This is the point where:

- failover becomes the priority
- not just backup

## Migration checklist

1. Take fresh logical dump from the current backend
   - use [19-export-slurmdbd-snapshot.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/19-export-slurmdbd-snapshot.sh)
2. Restore into the new MariaDB backend
3. Validate schema and row counts
4. Update:
   - `slurm-pilot/values/slurm-pilot-values.yaml`
   - keep the base file on the current live backend
   - use an explicit overlay for the migration target
5. `helm upgrade` the Slurm pilot
6. Validate:
   - `sacctmgr list cluster`
   - `sacct`
   - one real batch job
7. Keep old backend read-only until confidence is high

## Important rule

Do not tie `slurmdbd` resilience to OrangeFS.

OrangeFS is the shared data plane for workloads.
MariaDB is the accounting state plane.

They should stay separate so failures are easier to reason about.

## Repo helpers already in place

- [19-export-slurmdbd-snapshot.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/19-export-slurmdbd-snapshot.sh)
  - creates a logical snapshot
  - captures table row counts
  - writes metadata and checksum files
- [25-preflight-external-slurmdbd-db.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/25-preflight-external-slurmdbd-db.sh)
  - validates the live path, snapshot inventory, secret inventory, and target reachability before a real cutover window
- [26-preflight-cockpit-vm-db.sh](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/26-preflight-cockpit-vm-db.sh)
  - convenience wrapper for the prepared `10.100.100.166` stopgap target
- [values/slurm-pilot-values.external-db.example.yaml](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/values/slurm-pilot-values.external-db.example.yaml)
  - shows the minimal Helm override for moving `slurmdbd` to a stable external database endpoint
- [SLURMDBD_MIGRATION_BLUEPRINT.md](/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/SLURMDBD_MIGRATION_BLUEPRINT.md)
  - describes the safe migration phases, rollback posture, and exit criteria

## Most recent snapshot

The current pilot has a fresh migration-grade snapshot at:

- `/var/backups/slurm-pilot-mariadb/snapshots/20260405-113416/`

## Current candidate assessment

The natural next backend candidate is:

- `slurm-pilot-mariadb-ext`

Important reality check from the latest validation:

- the service already owns a stable ClusterIP:
  - `10.96.196.141`
- the reserved host-visible alias for the next preflight round is:
  - `slurmdbd-mariadb-ext.darwin.lan`
- the service DNS name:
  - `slurm-pilot-mariadb-ext.slurm-pilot.svc.cluster.local`
  works from pods, but is not the right final endpoint for host-side preflight on `t560`
- host-side reachability should therefore use either:
  - the stable ClusterIP directly
  - or a host-visible alias that resolves to it
- the candidate service still owns the right stable endpoint shape
- but the current pod is no longer live because:
  - `slurm-pilot-mariadb-ext-0` is `Pending`
  - it is pinned to `t560-proxmox`
  - `t560` is currently tainted with `node.kubernetes.io/disk-pressure`

This means:

- the candidate remains real
- the endpoint shape is understood
- but the candidate is not the live source of truth right now
- the live source of truth is again the host-local MariaDB on `10.100.100.2`
- the externalized K8s candidate should be treated as paused until its
  scheduling and failure-domain story improve

## Root cause that blocked the candidate before recovery

After clearing the Ceph RBD attachment churn and restoring the alias path, the deeper blocker turned out to be runtime policy, not DNS or PVCs:

- MariaDB pods inside Kubernetes were failing before opening `:3306`
- this was not limited to the persisted PVC path

Validation that failed with the same signature:

- `slurm-pilot-mariadb-ext` on its real PVC
- `bitnami/mariadb:latest` in an ephemeral `emptyDir` smoke pod
- `mariadb:11.4` in ephemeral `emptyDir` smoke pods on both:
  - `t560-proxmox`
  - `5860-proxmox`

Common failure signature:

- `Can't start server : UNIX Socket : Permission denied`

Deep-dive result:

- default container seccomp was **not** the blocker
- AppArmor was the blocker:
  - containers under the default `cri-containerd.apparmor.d` profile could not create AF_UNIX sockets
  - a minimal probe pod succeeded as soon as AppArmor was set to `Unconfined`
- the candidate now runs with:
  - `appArmorProfile.type: Unconfined`
  - `seccompProfile.type: RuntimeDefault`
- readiness/liveness/startup probes also had to stop relying on local socket defaults and instead use:
  - `mariadb-admin ping -h 127.0.0.1`

Operational reading now:

- DNS, CoreDNS, and host-visible aliasing are no longer the blocker
- PVC attachment churn was real, but is no longer the main blocker
- the AppArmor runtime restriction is understood and worked around explicitly for the migration candidate
- the next migration step is no longer "debug why MariaDB will not start"; it became "execute a cautious cutover window"
- that cutover now passes:
  - `sacctmgr`
  - `sacct`
  - smoke batch job `29`

## External non-Kubernetes fallback assessment

If we decide not to cut over to a K8s MariaDB candidate yet, the best outside-the-cluster fallback is still a dedicated host on the control-plane network.

Current honest read:

- the existing `cockpit` VM (`10.100.100.166`) is technically capable as an interim MariaDB host
- but it already carries observability duties and is not a boring dedicated database surface
- the cleaner long-term external target remains:
  - a dedicated VM or container on the control-plane network
  - with explicit backup/restore and a narrow operational role

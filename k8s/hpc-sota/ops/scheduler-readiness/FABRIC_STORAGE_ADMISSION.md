# Fabric/Storage Admission Reconciler

`fabric-storage-admission-reconcile.sh` is the operator-side bridge for
`AdmissionCheck/fabric-storage-readiness`.

It is intentionally not a Kubernetes Deployment yet. The current readiness
inputs are host-local:

- GPU fabric host checks through SSH and `gpu-fabric-gate.sh`
- OrangeFS mount state at `/var/lib/orangefs-lab/client-runtime/mnt`
- cross-lane GPU ownership from `ops/gpu-lease`

Running this in-cluster would require a purpose-built image, RBAC, and a clean
API for host fabric and GPU lease truth. Until that exists, run it from the ops
host.

## Current Safe Loop

Dry-run first:

```bash
/home/devsounio/beagle/k8s/hpc-sota/ops/scheduler-readiness/fabric-storage-admission-reconcile.sh --dry-run
```

Apply once:

```bash
/home/devsounio/beagle/k8s/hpc-sota/ops/scheduler-readiness/fabric-storage-admission-reconcile.sh
```

Watch Kueue state:

```bash
kubectl get workloads.kueue.x-k8s.io -A
/home/devsounio/beagle/k8s/hpc-sota/ops/scheduler-readiness/kueue-topology-doctor.sh
```

## Host Timer

Install the systemd service/timer files without enabling the loop:

```bash
/home/devsounio/beagle/k8s/hpc-sota/ops/scheduler-readiness/install-fabric-storage-admission-timer.sh
```

Run one reconciliation through systemd:

```bash
/home/devsounio/beagle/k8s/hpc-sota/ops/scheduler-readiness/install-fabric-storage-admission-timer.sh --run-once
```

Enable the 1-minute reconciler loop only after the ClusterQueue attachment
decision is made:

```bash
/home/devsounio/beagle/k8s/hpc-sota/ops/scheduler-readiness/install-fabric-storage-admission-timer.sh --enable
```

## Gate Semantics

The reconciler patches only workloads that already list
`fabric-storage-readiness` in `status.admissionChecks`.

It marks the check `Ready` only when:

- Kubernetes-side GPU fabric preflight passes
- host-to-host `10.210` fabric preflight passes
- OrangeFS is mounted as `pvfs2`
- `gpu-lease` reports no active Slurm, Kubernetes, or host GPU owner

If any gate is unavailable, it sets:

- `state: Retry`
- `requeueAfterSeconds: 60`

This prevents Kueue from admitting Kubernetes GPU work over an active Slurm or
serving owner.

## ClusterQueue Attachment

Do not attach this check to the live ClusterQueue until the reconciler is being
run by an operator loop or timer.

The staged attachment manifest is:

```bash
/home/devsounio/beagle/k8s/hpc-sota/kueue/clusterqueue.with-admissioncheck.example.yaml
```

It scopes the AdmissionCheck to GPU ResourceFlavors only:

- `gpu-any`
- `gpu-l4`
- `gpu-rtx-a5000`
- `gpu-rtx-4000-ada`

CPU-only Kueue work should not wait on the GPU fabric/storage gate.

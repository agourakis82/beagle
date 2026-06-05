# Kubernetes DRA Canary Lane

This directory stages the Kubernetes-native Dynamic Resource Allocation path for
Darwin/Sounio GPU work.

The current production GPU paths remain:

- Slurm `gpu-orangefs` for batch GPU jobs
- Kubernetes NVIDIA device plugin for serving or explicit K8s GPU workloads
- `gpu-lease` as the cross-lane ownership truth

DRA is not production-authoritative yet because the cluster has no live
`ResourceSlice` objects from a DRA driver.

## Files

- `deviceclasses.example.yaml`
  - seed `DeviceClass/sounio-gpu`
  - maps the future class to `nvidia.com/gpu`
- `resourceclaimtemplates.example.yaml`
  - namespace-local canary claim template in `beagle`
  - requests exactly one `sounio-gpu`
- `pod-dra-gpu-canary.example.yaml`
  - minimal pod shape that consumes the claim template
  - intentionally not applied while Slurm owns the GPUs

## Validation

Schema validation:

```bash
kubectl apply --dry-run=server -f /home/devsounio/beagle/k8s/hpc-sota/dra/deviceclasses.example.yaml
kubectl apply --dry-run=server -f /home/devsounio/beagle/k8s/hpc-sota/dra/resourceclaimtemplates.example.yaml
kubectl apply --dry-run=server -f /home/devsounio/beagle/k8s/hpc-sota/dra/pod-dra-gpu-canary.example.yaml
```

Doctor:

```bash
/home/devsounio/beagle/k8s/hpc-sota/ops/scheduler-readiness/dra-canary-doctor.sh
```

## Promotion Rule

Do not treat DRA as live until all are true:

- DRA API resources exist
- `DeviceClass/sounio-gpu` exists or the example validates
- a real DRA driver publishes `ResourceSlice` objects
- a canary pod can allocate a `ResourceClaim` and start
- `gpu-lease` knows how to report DRA/Kubernetes ownership

Until then, this is a canary lane, not the active GPU authority.

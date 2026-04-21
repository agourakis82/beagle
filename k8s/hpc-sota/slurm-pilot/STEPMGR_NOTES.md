# Slurm `enable_stepmgr` / `sbcast` Notes

Current live behavior on the Slurm Pilot lane:

- the patched operator image has been promoted successfully
- live controller runtime now resolves `SlurmctldParameters` to
  `enable_configless` only
- duplicate `SlurmctldParameters` lines may still appear in the rendered file,
  but they no longer re-enable `enable_stepmgr`
- standalone `sbcast` smoke now succeeds on the healthy `gpuorangefs` lane
  after the operator fix
- canonical proof:
  - `job 155`
  - `job 182`
  - stdout contains `hello-from-sbcast`
  - stderr shows `/usr/bin/sbcast` on the allocated worker

Implication:

- changing only `Controller.spec.extraConf` was not sufficient to disable
  `stepmgr`
- the durable fix required a patched Slurm operator/runtime path that respects
  the `enableStepmgr` value before appending `extraConf`
- `PAYLOAD_TRANSFER_MODE=sbcast` is now a viable lane, but it should still be
  treated as newer than the long-proven `embedded` path until it has more
  production mileage
  - `worker_local + fetch` is currently the cleanest end-to-end proof path for
    ABIDE campaign runs using `sbcast`
  - after persistence hardening, `sbcast + orangefs` has been validated on
    both admitted workers:
    - `job 186` on `gpuorangefs-r770-proxmox`
    - `job 183` on `gpuorangefs-r740-proxmox`

What was verified:

- the Helm chart `ghcr.io/slinkyproject/charts/slurm:1.1.0-rc1` does not expose
  a first-class `stepmgr` toggle in its values
- the chart template `templates/controller/controller-cr.yaml` only appends
  `spec.extraConf`
- therefore the previous
  `SlurmctldParameters=enable_configless,enable_stepmgr` line was not coming
  from our `extraConfMap`; it was rendered deeper in the operator/runtime path

What changed in source of truth:

1. expose `enable_stepmgr` as an explicit chart/operator value
2. ensure the base rendered controller config respects that value before
   `extraConf` is appended
3. stop relying on a second conflicting `SlurmctldParameters` line through
   `extraConf`
4. keep `stepmgr` as an explicit rollout choice rather than a hidden global
   default

Current source-of-truth implementation:

- patch file:
  - `/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/patches/slurm-operator-v1.1.0-rc1-stepmgr-toggle.patch`
- workload patch file:
  - `/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/patches/slurm-operator-v1.1.0-rc1-strategic-merge-workloads.patch`
- controller default patch file:
  - `/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/patches/slurm-operator-v1.1.0-rc1-controller-default-initcontainers.patch`
- patched image build helper:
  - `/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/21-build-slurm-operator-stepmgr-image.sh`
- operator installer applies every local `slurm-operator-*.patch` automatically
  and defaults global `stepmgr` to off:
  - `/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/20-install-slurm-operator.sh`
- local values now set the default operator stance to `enableStepmgr: false`:
  - `/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/values/slurm-operator-values.yaml`
- promoted patched operator image:
  - `ttl.sh/sounio-slurm-operator-stepmgr-20260410003309:24h`

What was validated live:

- the operator was rebuilt and reinstalled with the patched image
- `scontrol show config` now reports:
  - `SlurmctldParameters = enable_configless`
- standalone `sbcast` smoke succeeded:
  - `/orangefs/training/sounio/slurm-smokes/sbcast-20260410T003858Z-155.out`
  - `/orangefs/training/sounio/slurm-smokes/sbcast-20260410T003858Z-155.err`
- ABIDE campaign smoke succeeded end-to-end with
  `PAYLOAD_TRANSFER_MODE=sbcast` on the `worker_local + fetch` lane
- the hardened `sbcast + orangefs` lane now also validates end-to-end on both
  admitted workers:
  - `job 186` on `r770`
  - `job 183` on `r740`

Additional runtime issue now addressed in source of truth:

- the operator previously used `client.MergeFrom` when patching live
  `StatefulSet` and `Deployment` objects
- on the Slurm control-plane workloads this could yield invalid patches for
  container/initContainer lists and leave stale tolerations behind
- the strategic-merge patch above switches those workload updates to
  `client.StrategicMergeFrom`
- the operator also did not default `Controller.spec.reconfigure.image` or
  `Controller.spec.logfile.image` during reconcile; if those fields were absent
  from the stored CR, later StatefulSet patches could still fail with
  `initContainers[].image: Required value`
- the controller-default patch above defaults those two image fields during
  reconcile and adds a unit test to lock the behavior
- live scheduling reconciliation still force-replaces workload tolerations via:
  - `/home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/31-reconcile-slurm-pilot-scheduling.sh`

Current recommended stance:

- keep `PAYLOAD_TRANSFER_MODE=embedded` as the conservative default
- allow `sbcast` as a supported alternative lane when you want to exercise the
  recovered path explicitly
- `sbcast + orangefs` is now a valid production lane on the admitted
  `gpuorangefs` workers, but `embedded` remains the lowest-surprise default

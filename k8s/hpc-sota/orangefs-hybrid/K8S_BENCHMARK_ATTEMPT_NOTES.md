# OrangeFS vs Ceph K8s Benchmark Attempt Notes

## Goal

Run a like-for-like benchmark on `r740` inside Kubernetes using:

- OrangeFS via `hostPath`
- Ceph RBD via `ceph-rbd-ssd-scratch`

## What was created

- [PVC benchmark claim](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/k8s/pvc-ceph-rbd-ssd-scratch-bench.yaml)
- [Benchmark pod](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/k8s/pod-orangefs-vs-ceph-r740-bench.yaml)

## What happened first

The first benchmark attempts failed on the OrangeFS side with:

```text
metric_set,path,value
Traceback (most recent call last):
  File "<stdin>", line 61, in <module>
  File "<stdin>", line 15, in run_seq
FileNotFoundError: [Errno 2] No such file or directory: '/orangefs/bench-k8s/seq-128m.bin'
```

This was not a Ceph provisioning failure. The Ceph PVC bound correctly.

This failure reproduced again even after live `systemd` rollout for:

- `orangefs-server01.service`
- `orangefs-server02.service`
- `orangefs-client-runtime.service` on `r740`
- `orangefs-client-runtime.service` on `r770`

That pointed to the still-fragile part of the current OrangeFS orchestration:

- the proof island works
- K8s canaries work
- but the host-mounted OrangeFS path is not yet stable enough for the heavier
  benchmark pod lifecycle and write pattern

## Meaning

## What closed it

The key finding was that OrangeFS behaved badly when the benchmark retried the
same file path under `bench-k8s/seq-128m.bin`.

Using:

- a unique run directory per execution
- a unique file name per execution

removed that failure mode and allowed the benchmark to complete successfully.

Final results are recorded in:

- [K8S_BENCHMARK_RESULTS.md](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/K8S_BENCHMARK_RESULTS.md)

## Meaning

The important blocker was not OrangeFS viability. It was the combination of:

- benchmark reuse of a problematic file path
- current OrangeFS semantics around that path in this proof shape

The service hardening work still mattered, but the decisive fix for the
benchmark was using unique paths per run.

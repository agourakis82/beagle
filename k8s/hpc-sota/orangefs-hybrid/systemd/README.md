# OrangeFS systemd draft

These unit files now back the live OrangeFS operating baseline.

Current status:

- `orangefs-server01.service` and `orangefs-server02.service` are live
- `orangefs-client-runtime.service` is live on the GPU clients
- `orangefs-client-runtime.service` is now also live on `t560`
- `orangefs-training-canary.timer` is installed on `t560`
- `orangefs-cuda-pilot.timer` is now installed on `t560`

Why this shape:

- the proof-window workflow is already trusted
- the current step is operationalizing the proven shape without changing the
  storage baseline
- the timers separate recurring validation from ad-hoc debugging

Files:

- [orangefs-server01.service](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/systemd/orangefs-server01.service)
- [orangefs-server02.service](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/systemd/orangefs-server02.service)
- [orangefs-client-runtime.service](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/systemd/orangefs-client-runtime.service)
- [orangefs-client-runtime.sh](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/systemd/orangefs-client-runtime.sh)
- [installer](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/install-systemd-runtime.sh)
- [orangefs-training-canary.service](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/systemd/orangefs-training-canary.service)
- [orangefs-training-canary.timer](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/systemd/orangefs-training-canary.timer)
- [orangefs-cuda-pilot.service](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/systemd/orangefs-cuda-pilot.service)
- [orangefs-cuda-pilot.timer](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/systemd/orangefs-cuda-pilot.timer)

Training canary timer status:

- installed on `t560`
- currently the recurring distributed validation path

CUDA pilot timer status:

- installed on `t560`
- intended as the next recurring single-node GPU workload on top of the Orange
  baseline

# OrangeFS systemd draft

These unit files now back the live OrangeFS operating baseline.

Current status:

- `orangefs-server01.service` and `orangefs-server02.service` are live
- `orangefs-client-runtime.service` is live on the GPU clients
- `orangefs-client-runtime.service` is now also live on `t560`
- `orangefs-training-canary.timer` is installed on `t560`
- `orangefs-cuda-pilot.timer` is now installed on `t560`
- as of `2026-04-24`, `5860` server02 no longer stores its live OrangeFS data
  on the small shared `/var/lib/orangefs-lab` thin LV
- the live server02 data and metadata path is now the dedicated thin volume
  mounted at `/srv/orangefs-server02-store`

Why this shape:

- the proof-window workflow is already trusted
- the current step is operationalizing the proven shape without changing the
  storage baseline
- `5860` had been overcommitting a `128G` OrangeFS LV with unrelated
  `service-fabric/registry-data`, which pinned the export at `100%` even
  though the visible training tree was much smaller
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

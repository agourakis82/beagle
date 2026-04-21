# OrangeFS K8s Canary Results

## Scope

This records the first successful Kubernetes canary that consumed OrangeFS from
the current Debian 13 + Proxmox kernel cluster without changing the live Beagle
or Sounio service path.

## Shape

- OrangeFS two-node proof island:
  - `t560` server01
  - `5860` server02
- persistent client mount on:
  - `r740`
- Kubernetes pod:
  - `orangefs-r740-canary`
  - namespace `beagle`
  - node `r740-proxmox`

## Pod result

Final pod state:

- `Completed`

Representative output:

```text
NAME                   READY   STATUS      RESTARTS   AGE   IP          NODE           NOMINATED NODE   READINESS GATES
orangefs-r740-canary   0/1     Completed   0          9s    10.0.3.65   r740-proxmox   <none>           <none>
```

Container logs:

```text
orangefs pod canary on orangefs-r740-canary
total 17
drwxrwxrwt 1 root root 4096 Apr  5 01:07 .
drwxr-xr-x 1 root root 4096 Apr  5 01:07 ..
drwxr-xr-x 1 root root 4096 Apr  5 01:07 checkpoints
drwxrwxrwx 1 root root 4096 Apr  5 01:06 lost+found
-rw-r--r-- 1 root root   44 Apr  5 01:06 orangefs-canary-2n.txt
total 9
drwxr-xr-x 1 root root 4096 Apr  5 01:07 .
drwxrwxrwt 1 root root 4096 Apr  5 01:07 ..
-rw-r--r-- 1 root root   44 Apr  5 01:07 k8s-orangefs-r740.txt
orangefs pod canary on orangefs-r740-canary
```

## Host-side evidence on r740

The file written by the pod remained visible on the host mount:

```text
total 9
drwxr-xr-x 1 root root 4096 Apr  4 22:07 .
drwxrwxrwt 1 root root 4096 Apr  4 22:07 ..
-rw-r--r-- 1 root root   44 Apr  4 22:07 k8s-orangefs-r740.txt
---
orangefs pod canary on orangefs-r740-canary
```

## Meaning

This is the first proof that OrangeFS has crossed into Kubernetes consumption in
the cluster:

- two-node OrangeFS namespace alive
- GPU-node host mount alive
- Kubernetes pod consumed the mounted namespace
- checkpoint-style write succeeded

The next step is no longer basic viability. The next step is operational
hardening and comparison against the old Ceph-backed shared path.


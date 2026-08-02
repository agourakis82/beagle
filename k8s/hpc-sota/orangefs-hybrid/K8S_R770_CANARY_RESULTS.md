# OrangeFS K8s Canary Results on r770

## Scope

This records the first successful Kubernetes canary that consumed OrangeFS from
the `r770` GPU node.

## Shape

- OrangeFS two-node proof island:
  - `t560` server01
  - `5860` server02
- persistent client mount on:
  - `r770`
- Kubernetes pod:
  - `orangefs-r770-canary`
  - namespace `beagle`
  - node `r770-proxmox`

## Pod result

Final pod state:

- `Completed`

Representative output:

```text
NAME                   READY   STATUS      RESTARTS   AGE   IP           NODE           NOMINATED NODE   READINESS GATES
orangefs-r770-canary   0/1     Completed   0          18s   10.0.1.200   r770-proxmox   <none>           <none>
```

Container logs:

```text
orangefs pod canary on orangefs-r770-canary
total 20
drwxrwxrwt 1 root root 4096 Apr  5 01:11 .
drwxr-xr-x 1 root root 4096 Apr  5 01:11 ..
drwxr-xr-x 1 root root 4096 Apr  5 01:10 bench-k8s
drwxr-xr-x 1 root root 4096 Apr  5 01:11 checkpoints
drwxrwxrwx 1 root root 4096 Apr  5 01:10 lost+found
total 9
drwxr-xr-x 1 root root 4096 Apr  5 01:11 .
drwxrwxrwt 1 root root 4096 Apr  5 01:11 ..
-rw-r--r-- 1 root root   44 Apr  5 01:11 k8s-orangefs-r770.txt
orangefs pod canary on orangefs-r770-canary
```

## Host-side evidence on r770

The file written by the pod remained visible on the host mount:

```text
total 9
drwxr-xr-x 1 root root 4096 Apr  4 22:11 .
drwxrwxrwt 1 root root 4096 Apr  4 22:11 ..
-rw-r--r-- 1 root root   44 Apr  4 22:11 k8s-orangefs-r770.txt
---
orangefs pod canary on orangefs-r770-canary
```


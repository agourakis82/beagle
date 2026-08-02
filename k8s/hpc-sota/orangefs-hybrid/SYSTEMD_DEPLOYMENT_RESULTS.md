# OrangeFS systemd deployment results

## Scope

This records the first live deployment of `systemd` units for the OrangeFS proof
island and GPU-node client mounts.

## Installed live

### Servers

- `t560`: `orangefs-server01.service`
- `5860`: `orangefs-server02.service`

### Clients

- `r740`: `orangefs-client-runtime.service`
- `r770`: `orangefs-client-runtime.service`

## Observed result

Both server units entered `active (running)`.

Representative state:

```text
● orangefs-server01.service - OrangeFS server01 proof island on t560
     Active: active (running)

● orangefs-server02.service - OrangeFS server02 proof island on 5860
     Active: active (running)
```

Both client units entered `active (exited)` successfully as intended for a
`Type=oneshot` + `RemainAfterExit=yes` service.

Representative state:

```text
● orangefs-client-runtime.service - OrangeFS client runtime mount
     Active: active (exited)
...
tcp://10.100.100.2:3334/orangefs_lab_2n on /var/lib/orangefs-lab/client-runtime/mnt type pvfs2
```

## Meaning

This was an important step forward:

- server liveness is no longer dependent only on the proof-window script
- GPU-node mounts are now managed by `systemd`
- the next blocker is the behavior of the OrangeFS host mount under heavier
  Kubernetes benchmark churn


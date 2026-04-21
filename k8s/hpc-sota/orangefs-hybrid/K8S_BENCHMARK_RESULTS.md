# OrangeFS vs Ceph K8s Benchmark Results

## Scope

This records the first successful like-for-like Kubernetes benchmark on `r740`
comparing:

- OrangeFS via `hostPath`
- Ceph RBD via `ceph-rbd-ssd-scratch`

## Setup

- node: `r740-proxmox`
- pod: `orangefs-vs-ceph-r740-bench`
- OrangeFS mount source on host:
  - `/var/lib/orangefs-lab/client-runtime/mnt`
- Ceph PVC:
  - `orangefs-ceph-scratch-bench`

The successful run used:

- unique run directory per execution
- unique file name per execution

This avoided the file-reuse behavior that had previously caused `FileNotFound`
on OrangeFS when the benchmark retried the same file path.

## Results

### First tuned round

The first live tuning round kept the same benchmark shape and applied a small,
safe config set:

- `TroveMaxConcurrentIO 32`
- `FlowBufferSizeBytes 1048576`
- `FlowBuffersPerFlow 16`
- `AttrCacheKeywords dh,md,de,st`
- `AttrCacheSize 4093`
- `AttrCacheMaxNumElems 32768`
- `DBMaxSize 1073741824`
- `TroveSyncMeta yes`
- `TroveSyncData no`

This round also fixed the service handoff so `systemd` owns the server
processes cleanly on `t560` and `5860`.

### Balanced profile

Baseline:

```text
metric_set,path,value
orangefs,seq_write_mb_s,590.73
orangefs,seq_read_mb_s,238.04
orangefs,sha256,254bcc3fc4f27172636df4bf32de9f107f620d559b20d760197e452b97453917
orangefs,create_ops_s,451.26
orangefs,stat_ops_s,15415.98
orangefs,remove_ops_s,1031.68
ceph,seq_write_mb_s,696.15
ceph,seq_read_mb_s,354.75
ceph,sha256,254bcc3fc4f27172636df4bf32de9f107f620d559b20d760197e452b97453917
ceph,create_ops_s,19496.06
ceph,stat_ops_s,123445.39
ceph,remove_ops_s,67809.75
```

Tuned:

```text
metric_set,path,value
orangefs,seq_write_mb_s,592.00
orangefs,seq_read_mb_s,237.57
orangefs,sha256,254bcc3fc4f27172636df4bf32de9f107f620d559b20d760197e452b97453917
orangefs,create_ops_s,469.10
orangefs,stat_ops_s,15744.86
orangefs,remove_ops_s,1054.96
ceph,seq_write_mb_s,730.49
ceph,seq_read_mb_s,353.54
ceph,sha256,254bcc3fc4f27172636df4bf32de9f107f620d559b20d760197e452b97453917
ceph,create_ops_s,19514.84
ceph,stat_ops_s,127184.91
ceph,remove_ops_s,69858.49
```

### Streaming profile

Baseline:

```text
metric_set,path,value
orangefs,seq_write_mb_s,685.03
orangefs,seq_read_mb_s,230.43
orangefs,sha256,49bc20df15e412a64472421e13fe86ff1c5165e18b2afccf160d4dc19fe68a14
orangefs,create_ops_s,469.03
orangefs,stat_ops_s,19309.13
orangefs,remove_ops_s,1082.35
ceph,seq_write_mb_s,1009.56
ceph,seq_read_mb_s,356.65
ceph,sha256,49bc20df15e412a64472421e13fe86ff1c5165e18b2afccf160d4dc19fe68a14
ceph,create_ops_s,22727.58
ceph,stat_ops_s,127644.06
ceph,remove_ops_s,72648.30
```

Tuned:

```text
metric_set,path,value
orangefs,seq_write_mb_s,647.32
orangefs,seq_read_mb_s,217.54
orangefs,sha256,49bc20df15e412a64472421e13fe86ff1c5165e18b2afccf160d4dc19fe68a14
orangefs,create_ops_s,446.47
orangefs,stat_ops_s,18319.49
orangefs,remove_ops_s,1103.90
ceph,seq_write_mb_s,1081.66
ceph,seq_read_mb_s,359.19
ceph,sha256,49bc20df15e412a64472421e13fe86ff1c5165e18b2afccf160d4dc19fe68a14
ceph,create_ops_s,22865.03
ceph,stat_ops_s,127401.74
ceph,remove_ops_s,72082.56
```

## Read

For this benchmark shape on the current cluster:

- Ceph beat OrangeFS on sequential write
- Ceph beat OrangeFS on sequential read
- Ceph beat OrangeFS decisively on metadata-heavy operations
- that remained true even in the more streaming-oriented profile

That does **not** invalidate OrangeFS as a direction. It means:

- the current two-node OrangeFS proof island is real
- Kubernetes consumption is real
- but neither the baseline nor the first tuned round outperform the existing
  Ceph path for this benchmark profile

## Meaning

This is the kind of result we want:

- honest
- reproducible
- useful for architecture decisions

The next step is tuning and topology work, not pretending the first OrangeFS
shape already wins.

## Current conclusion

Across both benchmark profiles recorded so far:

- OrangeFS is viable
- OrangeFS is consumable from Kubernetes
- the first tuned round improved OrangeFS only slightly in the balanced profile
- the first tuned round regressed OrangeFS in the streaming profile
- Ceph is still faster on this cluster for these tested profiles

That means the OrangeFS branch is still a serious research path, but not yet a
promotion candidate over the existing Ceph shared path.

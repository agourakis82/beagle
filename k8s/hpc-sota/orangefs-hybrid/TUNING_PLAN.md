# OrangeFS tuning plan

## Why this exists

The first current-OS OrangeFS proof is real, but the first Kubernetes benchmark
profiles still favored Ceph on this cluster.

That means the next OrangeFS round should be a tuning round, not a faith round.

## What the official docs point to

The OrangeFS configuration reference exposes several knobs that directly affect
the profile we are testing:

- `TroveMaxConcurrentIO`
- `TCPBufferSend`
- `TCPBufferReceive`
- `FlowBufferSizeBytes`
- `FlowBuffersPerFlow`
- `AttrCacheKeywords`
- `AttrCacheSize`
- `AttrCacheMaxNumElems`
- `DBCacheSizeBytes`
- `DBCacheType`
- `DBMaxSize`
- `TroveSyncMeta`
- `TroveSyncData`
- `TroveMethod`
- `DefaultNumDFiles`

Official references:

- OrangeFS configuration file:
  - https://docs.orangefs.com/configuration/admin_ofs_configuration_file/
- OrangeFS kernel client guidance:
  - https://docs.orangefs.com/nix-clients/linux-kernel-module/

Important official notes used here:

- the upstream kernel module is the recommended path
- Linux `5.2+` gained full read/write page-cache integration
- `TroveSyncData no` can greatly improve performance
- `TroveSyncMeta no` can greatly improve performance but carries metadata-loss
  risk on failure
- `AttrCache*` and `DBCache*` exist specifically to improve metadata behavior

## First safe tuning round

These are the first knobs worth testing without turning the proof island into a
reckless setup:

### Metadata-oriented

- increase `AttrCacheSize`
- increase `AttrCacheMaxNumElems`
- set a real `DBCacheSizeBytes`
- increase `DBMaxSize`

Reason:

- our current benchmark losses are especially severe on metadata-heavy paths

### Throughput-oriented

- increase `TroveMaxConcurrentIO`
- increase `FlowBufferSizeBytes`
- increase `FlowBuffersPerFlow`

Reason:

- our current streaming profile still lost on sequential throughput

### Risk-managed sync policy

- keep `TroveSyncMeta yes` for now
- test `TroveSyncData no`

Reason:

- this is the most obvious official performance lever
- it improves write performance with lower risk than disabling metadata sync

## Things not to do first

- do not disable `TroveSyncMeta` first
- do not change too many knobs at once
- do not claim victory from synthetic wins without rerunning the K8s profiles

## Next benchmark round

The next OrangeFS tuning round should be:

1. baseline current config
2. metadata-cache tuned config
3. metadata-cache + throughput tuned config
4. metadata-cache + throughput tuned config + `TroveSyncData no`

And each round should rerun:

- balanced K8s profile
- streaming K8s profile

## Round 1 status

Round 1 was applied live with this set:

- `TroveMaxConcurrentIO 32`
- `FlowBufferSizeBytes 1048576`
- `FlowBuffersPerFlow 16`
- `AttrCacheKeywords dh,md,de,st`
- `AttrCacheSize 4093`
- `AttrCacheMaxNumElems 32768`
- `DBMaxSize 1073741824`
- `TroveSyncMeta yes`
- `TroveSyncData no`

Result:

- balanced profile improved only slightly on OrangeFS
- streaming profile got worse on OrangeFS
- Ceph still won clearly in both profiles

That means the next OrangeFS round should either:

1. narrow down to one knob family at a time, or
2. stop tuning the proof island and treat OrangeFS as a research branch while
   Ceph remains the shared production winner

## Round 2 status

Round 2 intentionally narrowed down to one layout-oriented change:

- `DefaultNumDFiles 1`

and added temporary visibility on `server02` with:

- `EventLogging io,storage,distribution,server`

Reason:

- the checkpoint repro was failing with repeated `ENOENT`
- the failing handles were falling into the `server02` data-handle range
- the filesystem was still using the default `simple-stripe` distribution path
  without an explicit `DefaultNumDFiles`

Result:

- `r740` single-node checkpoint repro passed
- `r770` single-node checkpoint repro passed
- concurrent checkpoint repro on `r740 + r770` also passed

That makes Round 2 the first OrangeFS tuning round that clearly fixed a real
correctness problem, not just moved synthetic throughput numbers around.

The next OrangeFS step should therefore be:

1. rerun the larger multi-node benchmark under `DefaultNumDFiles 1`
2. distinguish runner/workload issues from filesystem issues
3. only then revisit the broader Ceph vs OrangeFS verdict

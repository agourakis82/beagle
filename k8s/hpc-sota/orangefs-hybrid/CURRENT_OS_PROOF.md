# OrangeFS Current-OS Proof

## t560 current-OS proof

Date:

- `2026-04-04`

Target:

- `t560-proxmox`
- `Debian 13`
- `6.17.13-2-pve`

## What was tested

- verify `modinfo orangefs`
- load the in-tree `orangefs` kernel module
- verify the module is present in `lsmod`
- unload the module again
- source-build OrangeFS user-space
- compile a dynamic `pvfs2-server`
- compile dynamic `pvfs2-client`, `pvfs2-client-core`, and `mount.pvfs2`
- run single-node `--mkfs`
- start the server in foreground under `timeout`
- mount the OrangeFS filesystem and perform canary I/O
- build a second-node `pvfs2-server` on `5860`
- start a two-node namespace across `t560 + 5860`
- mount the shared two-node namespace from `t560`
- perform read/write canary I/O on the shared namespace

## Result

The current Proxmox kernel already ships:

- `/lib/modules/6.17.13-2-pve/kernel/fs/orangefs/orangefs.ko`

The module:

- loaded successfully
- appeared in `lsmod`
- unloaded cleanly

The user-space/server path now also works on the current OS:

- dynamic `pvfs2-server` compiled successfully on `t560`
- binary shape:
  - ELF 64-bit
  - dynamically linked
  - links against `libcrypto.so.3`, `libz.so.1`, `libzstd.so.1`
- `pvfs2-server --help` returned clean usage output
- `pvfs2-server -f -a t560-proxmox ...` created the storage space successfully
- `pvfs2-server -d -a t560-proxmox ...` reached:
  - `PVFS2 Server ready.`
- the foreground proof exited only because it was intentionally stopped by `timeout` after 8 seconds

The client/mount path now also works on the current OS:

- dynamic `pvfs2-client` compiled successfully on `t560`
- dynamic `pvfs2-client-core` compiled successfully on `t560`
- the single-node mount proof used:
  - the in-tree `orangefs.ko`
  - `pvfs2-server`
  - `pvfs2-client`
  - `pvfs2-client-core`
  - a direct `mount(2)` call via Python `ctypes`
- successful mount output included:
  - `tcp://10.100.100.2:3334/orangefs_lab on /zfast/orangefs-lab/single-node-dyn/mnt type pvfs2`
- successful I/O proof included:
  - `orangefs-canary.txt`
  - `lost+found`

The two-node shared-namespace path now also works on the current OS:

- `5860` built a dynamic `pvfs2-server` successfully at:
  - `/var/lib/orangefs-lab/orangefs-build-serveronly-dyn/src/server/pvfs2-server`
- a shared config spanning:
  - `server01 tcp://10.100.100.2:3334`
  - `server02 tcp://10.100.100.3:3334`
  was generated and applied
- both proof servers initialized their isolated storage spaces successfully
- `t560` mounted the shared namespace successfully:
  - `tcp://10.100.100.2:3334/orangefs_lab_2n on /zfast/orangefs-lab/two-node/mnt type pvfs2`
- successful two-node I/O proof included:
  - `orangefs-canary-2n.txt`
  - `lost+found`

Proof script:

- [prove-t560-client-mount.sh](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/prove-t560-client-mount.sh)
- [prove-t560-5860-two-node.sh](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/prove-t560-5860-two-node.sh)
- [launch-t560-5860-two-node-from-workstation.sh](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/launch-t560-5860-two-node-from-workstation.sh)

## Meaning

It means:

- the current OS already contains the OrangeFS kernel client path
- the current `pve` kernel did not block the client-module proof
- the current `Debian 13 + 6.17.13-2-pve` stack did not block server build/start
- the current `Debian 13 + 6.17.13-2-pve` stack did not block client mount/use
- the current `Debian 13 + PVE kernel` baseline did not block a two-node shared namespace
- OrangeFS is immediately more plausible on the current OS than BeeGFS was

# OrangeFS Configure Notes

## First configure attempt on `t560`

Date:

- `2026-04-04`

Command shape:

- `--prefix=/zfast/orangefs-lab/install`
- `--with-db-backend=lmdb`
- `--enable-usrint`
- `--enable-usrint-kmount`

## What failed

The first configure attempt showed two concrete issues:

1. missing autotools helper macros:
   - `AX_OPENSSL`
   - `AX_GETGROUPLIST`
   - `AX_LDAP`
   - `AX_CHECK_NEEDS_LIBRT`
2. the `kmount` path requires a kernel build path or FUSE path to be enabled

## What this means

To continue on the current node we should:

1. install:
   - `autoconf-archive`
   - `liblmdb-dev`
2. rerun:
   - `autoreconf -fi`
   - `configure` with `--with-kernel=/usr/lib/modules/6.17.13-2-pve/build`

## Why this is still good news

This is a normal build-system/dependency issue.

It is much better than the BeeGFS result because:

- the blocker is not a kernel API incompatibility
- the current OS still looks viable for the OrangeFS path

## Second configure attempt on `t560`

After installing:

- `proxmox-headers-6.17.13-2-pve`
- `autoconf-archive`
- `liblmdb-dev`

and regenerating autotools with:

- `autoreconf -fi -I maint/config`

the next blocker was a stale kernel-version guard in OrangeFS itself.

### What failed

The stock `configure.ac` only recognizes:

- `2.6`
- `3.x`
- `4.x`

and aborts on current `6.17.x-pve` headers with:

- `The kernel source tree does not appear to be 2.6 or 3.X or 4.X`

### What we changed

We added a local moonshot helper:

- [patch-and-configure-t560-kernel6.sh](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/patch-and-configure-t560-kernel6.sh)

and a tracked patch file:

- [orangefs-kernel-5-6-configure.patch](/home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/patches/orangefs-kernel-5-6-configure.patch)

The helper does two things:

1. patches `configure.ac` to accept `5.x` and `6.x`
2. patches the generated `configure`, because `autoreconf` mangles the `[[56]]` class into `56`

### Result

The out-of-tree configure on `t560` now completes successfully and reports:

- `PVFS2 configured for the 2.6/3 kernel module      : yes`
- `PVFS2 server will be built                        : yes`
- `PVFS2 user interface libraries will be built      : yes`

This is the first real proof that OrangeFS can clear the current kernel/OS gate on the cluster.

### New build finding

The first out-of-tree `make` failed with a layout problem:

- missing include visibility for `pvfs2-config.h`
- `No rule to make target 'src/common/statecomp/statecomp.o'`

That points to an out-of-tree build quirk, not a kernel blocker.

### Current working theory

- current OS + kernel are viable for OrangeFS
- source build is viable
- kernel detection is now handled
- the next issue is build layout, likely requiring either:
  - an in-source build
  - or a small makefile/include-path adjustment

## Dynamic server-only build result on `t560`

We then switched from the static server path to a dynamic server-only path:

- `--disable-olib`
- `--disable-threaded`
- no `--enable-static-server`

That changed the story materially.

### What happened

1. the `configure` completed successfully
2. we bridged the out-of-tree build quirk by:
   - copying generated `statecomp` artifacts into the build tree
   - copying a small number of `SERVEROBJS` that had landed in the source tree
3. `make -j1 src/server/pvfs2-server V=1` completed successfully

### Why the dynamic path mattered

The static server path failed at the final link step because OpenSSL's static archive pulled in:

- `zlib`
- `zstd`

symbols that were not being linked in that mode.

The dynamic path avoids that trap and produces a usable binary on the current host.

### Binary proof

The resulting server binary is:

- dynamically linked
- executable on `t560`
- returns clean usage output from `--help`

### Operational proof

With a minimal single-node config:

- `pvfs2-server -f -a t560-proxmox ...` created storage successfully
- `pvfs2-server -d -a t560-proxmox ...` reached:
  - `PVFS2 Server ready.`

This is the first full proof that OrangeFS server user-space is viable on the current cluster OS.

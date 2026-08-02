# BeeGFS Client Canary Results

## r740 client canary

Date:

- `2026-04-04`

Target:

- `r740-proxmox`
- `Debian 13`
- `6.17.13-2-pve`

## What was tested

- add official BeeGFS `8.3` `trixie` repository
- install:
  - `beegfs-client`
  - `beegfs-tools`
- rebuild client module against the running `pve` kernel

## Result

The repository and Debian packaging path worked.

The client module build **failed** on the current Proxmox kernel.

## Important details

Observed compile failures included:

- `struct page has no member named index`
- `implicit declaration of function dev_get_flags`

This confirms:

- `Debian 13` itself is not the blocker
- the blocker is the current custom `6.17.x-pve` client-kernel API surface

## What we did after the test

- removed `beegfs-client`
- removed `beegfs-tools`
- removed BeeGFS apt repo file and key

The `r740` node was left clean after the canary.

## Decision impact

This means the BeeGFS-first moonshot is still strategically attractive, but the
current path is blocked on the client side unless one of the following changes:

1. a BeeGFS patch release adds support for the current `pve` kernel APIs
2. the client nodes use a supported distribution kernel instead of the current
   `pve` kernel
3. the new `DL380 G10` is provisioned on a BeeGFS-friendly client OS/kernel and
   becomes the first real BeeGFS client platform

## Honest takeaway

BeeGFS is still the most pragmatic open-source moonshot candidate.

But for this cluster as it stands today:

- `BeeGFS server daemons` look plausible
- `BeeGFS client modules` on `6.17.x-pve` are the real blocker

# OrangeFS Support Notes

## Official facts

From the Linux kernel documentation:

- OrangeFS is an LGPL userspace scale-out parallel storage system
- it is ideal for HPC, genomics, and bioinformatics
- the filesystem can distribute file data among multiple servers
- it supports simultaneous multi-client access

From the OrangeFS documentation:

- OrangeFS is intended for high-end computing systems
- server and client are user-level code
- the upstream Linux kernel module is the preferred Linux integration method
- as of Linux `5.13`, performance improved significantly with full page-cache
  integration

## Why this matters for the current cluster

Current nodes are:

- `Debian 13`
- `6.17.x-pve`

Compared with the BeeGFS canary result, OrangeFS is attractive because:

- the kernel already documents the OrangeFS filesystem client path
- the implementation leans heavily on user-space services
- the project explicitly calls out genomics and bioinformatics as target
  domains, which aligns extremely well with the omics side of the mission

## Current moonshot stance

If the requirement is:

- stay on the current OS for now
- keep moving toward AI/HPC
- avoid the BeeGFS client-module blocker we already hit on `pve 6.17`

then OrangeFS deserves serious evaluation as the leading current-OS parallel
filesystem candidate.

# DL380 Proxmox bootstrap

This lane installs the HPE ProLiant DL380 Gen10 as `dl380-proxmox`, the fifth
member candidate for Proxmox cluster `pve100g`.

## Proven hardware identity

- serial: `2M290403R2`
- iLO: `ILO2M290403R2` at `192.168.3.153`
- host management address: `192.168.3.155/24`
- management NIC MAC: `54:80:28:58:35:e2`
- system disk: Intel NVMe serial `CVPD7223008K800U`, bay 1
- preserved disk: Intel NVMe serial `CVPD7094009Q800U`, bay 2
- accelerator: Xilinx Alveo U250

## PXE reality

The DHCP/TFTP service on `r770-proxmox` (`192.168.3.228`) supplies
`grubx64.efi`, `/linux26`, and `/initrd.img`. DHCP currently sets the GRUB
prefix to `/EFI/proxmox`, but the usable menu is `/grub.cfg`.

The shared `/answer.toml` belongs to `p5860-proxmox` and must not be used for
this host. This directory contains the DL380-specific answer and first-boot
hook.

## Destructive boundary

The answer file formats only the NVMe whose serial is `CVPD7223008K800U`.
The second NVMe is intentionally excluded and must remain untouched until its
contents are inspected from the installed host.

## Boot command

Serve this directory from `t560-proxmox` on port `8088`, then enter at the
DL380 GRUB prompt:

```text
linux (tftp,192.168.3.228)/linux26 vga=791 video=vesafb:ywrap,mtrr ramdisk_size=16777216 rw quiet splash=silent proxmox-start-auto-installer fetch=http://192.168.3.169:8088/answer.toml
initrd (tftp,192.168.3.228)/initrd.img
boot
```

If the PXE GRUB image cannot load its TFTP module, rebuild the UEFI ISO from
the read-only NFS export `192.168.3.228:/srv/nfs/proxmox`, preserving ISO UUID
`2025-11-18-19-11-13-00`. Replace the exported `answer.toml`, add
`auto-installer-mode.toml`, and mount the resulting image through iLO virtual
media. The automated menu entry then boots without depending on PXE GRUB.

After installation, verify SSH, inspect both NVMe devices and the U250, then
join `pve100g`. Do not advertise the node to Kubernetes or Slurm until the
host-level accelerator and network checks are green.

## Proven bare-metal U250 path

The U250 runs directly on Proxmox VE 9; a VM is not required. The proven host
stack is XRT `2.23.0` from the upstream `2026.1` branch plus AMD's U250
`2024.1` deployment platform. DKMS was proven first on `6.17.2-1-pve` and then
on the current `7.0.14-8-pve` kernel. The newer kernel is required on this node
to avoid the Cilium BPF verifier failure seen with `6.17.2-1-pve`.

The persistent base is `xilinx_u250_gen3x16_base_4`, the SC firmware is
`4.6.21`, and the runtime partition is
`xilinx_u250_gen3x16_xdma_shell_4_1`. Because the 2RP runtime partition is
volatile, deploy and enable the checked-in loader after installing XRT and the
deployment packages:

```bash
install -m 0755 u250-load-xdma-shell /usr/local/sbin/u250-load-xdma-shell
install -m 0644 xrt-u250-shell.service /etc/systemd/system/xrt-u250-shell.service
systemctl daemon-reload
systemctl enable --now xrt-u250-shell.service
```

The acceptance test is:

```bash
/opt/xilinx/xrt/bin/xrt-smi --batch validate \
  --device 0000:d8:00.1 \
  --run all
```

Tests that apply to the U250 (auxiliary power, DMA, M2M, DDR bandwidth, PCIe,
SC version, and verify kernel) must pass. AIE, host-memory bandwidth, and P2P
can be skipped when those optional features are not present or enabled.

While `t560-proxmox` uses the management fallback instead of its fabric NIC,
apply `../../cilium/dl380-management-fallback.yaml`. It keeps native routing
for directly reachable workers and tells Cilium not to replace the persistent,
symmetric management routes for the T560 node and pod CIDR.

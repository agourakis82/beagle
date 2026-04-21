# 5860 Secure Boot: what it is and the exact fix

This is the blocker on `5860-proxmox` right now:

- `SecureBoot enabled`
- the Ada GPU is no longer bound to `vfio-pci`
- the NVIDIA modules exist on disk
- but the kernel refuses to load them because their signing keys are not yet
  enrolled in the machine's MOK database

In plain language:

- Secure Boot only lets trusted kernel modules load
- the host has NVIDIA/DKMS signing certificates on disk
- but the firmware does not trust those certificates yet

## What we already confirmed

On `5860-proxmox`:

- `/var/lib/shim-signed/mok/MOK.der`
  - subject: `CN=NVIDIA Module Signing`
  - enrolled: `no`
- `/var/lib/dkms/mok.pub`
  - subject: `CN=DKMS module signing key`
  - enrolled: `no`

That is why `modprobe nvidia` still fails under Secure Boot.

## The shortest honest fix

Enroll both keys, reboot once, approve them in the blue MOK screen, then
finish the normal NVIDIA/Kubernetes host bootstrap.

## Step 1: queue the keys for enrollment

Run on `5860-proxmox` as `root`:

```bash
mokutil --import /var/lib/shim-signed/mok/MOK.der /var/lib/dkms/mok.pub
```

Pick a **one-time enrollment password** when `mokutil` asks.

This is **not** your root password. It is only used on the next reboot in the
MOK manager screen.

## Step 2: reboot the host

```bash
systemctl reboot
```

This will interrupt the workloads on `5860-proxmox`, including the VM if it is
running there.

## Step 3: in the blue MOK manager screen

When the machine reboots, use the console to do this:

1. `Enroll MOK`
2. `Continue`
3. `Yes`
4. enter the one-time enrollment password
5. `Reboot`

## Step 4: validate after reboot

Run on `5860-proxmox`:

```bash
mokutil --test-key /var/lib/shim-signed/mok/MOK.der
mokutil --test-key /var/lib/dkms/mok.pub
modprobe nvidia
ls -l /dev/nvidia*
```

You want to see:

- both keys reported as enrolled
- `modprobe nvidia` returning success
- `/dev/nvidia0`, `/dev/nvidiactl`, `/dev/nvidia-uvm` appearing

## Step 5: then finish the host bootstrap

At that point the Secure Boot problem is gone, and the remaining work becomes
normal host plumbing:

- ensure `nvidia-smi` exists
- install/configure `nvidia-container-toolkit`
- configure `containerd`
- restart `containerd` and `kubelet`
- let the NVIDIA device plugin advertise `nvidia.com/gpu`

## Why this is the right fix

The blocker is no longer VFIO.

The blocker is no longer basic networking.

The blocker is specifically **firmware trust of the module signing keys**.

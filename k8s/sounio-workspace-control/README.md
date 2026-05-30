# Sounio Workspace Control

This is the single persistent Sounio human/agent control surface.

It replaces the temporary split where:

- HTTP pointed at `sounio-workspace-local`
- SSH/Zellij pointed at `sounio-zellij-recovery`

The control workspace mounts the retained habitat PVC:

```text
workspace-data-sounio-workspace-habitat-0
```

It intentionally requests no GPU. GPU execution belongs to Slurm/Foundry, not
to the always-on editor and agent surface.

## Shape

- workload: `StatefulSet/sounio-workspace-control`
- stable pod: `sounio-workspace-control-0`
- node: `t560-proxmox`
- service: `sounio-workspace-control`
- stable public/private entrypoints to patch here:
  - `Service/sounio-workspace`
  - `Service/sounio-workspace-tailnet-http`
  - `Service/sounio-workspace-tailnet-ssh`

## Migration

Use:

```bash
/home/devsounio/projects/sounio/sounio-maintain.sh promote-control-workspace
```

This releases the temporary recovery pod, starts the control workspace, points
the stable services at it, and resurrects the `sounio-dev` Zellij session.

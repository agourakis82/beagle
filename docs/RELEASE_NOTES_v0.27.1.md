# Release Notes — v0.27.1

## Fixes

- systemd: `scripts/systemd/beagle-core.service` and `scripts/systemd/beagle-mcp.service` now start reliably (avoid systemd environment expansion inside `bash -lc` by using `WorkingDirectory` + direct `ExecStart`).

## Upgrade

```bash
cd /root/beagle
sudo bash scripts/systemd/install-beagle-services.sh --user root --workspace /root/beagle
sudo systemctl daemon-reload
sudo systemctl restart beagle-core.service beagle-mcp.service
```


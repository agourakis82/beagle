# Release Notes — v0.27.2

## Added

- MCP: legacy SSE endpoints (`GET /sse`, `POST /message?sessionId=...`) for claude.ai connector compatibility.
- Ops: Cloudflare Tunnel runbook (`docs/MCP_EXTERNAL_ACCESS.md`) + reference unit file (`scripts/systemd/cloudflared-beagle.service`).

## Changed

- MCP: optional endpoint-level bearer auth for `/mcp`, `/sse`, and `/message` when `MCP_ENABLE_AUTH=true` (keeps `/health` public).
- SSE: emits one-time padding to reduce proxy/CDN buffering issues.

## Upgrade

```bash
cd /root/beagle

# Rebuild MCP server
cd beagle-mcp-server && npm install && npm run build

# Restart BEAGLE services
sudo systemctl restart beagle-core.service beagle-mcp.service

# (Optional) enable tunnel for remote MCP clients (claude.ai)
sudo cp scripts/systemd/cloudflared-beagle.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now cloudflared-beagle.service
```

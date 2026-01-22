# BEAGLE MCP External Access (claude.ai)

This runbook exposes the BEAGLE MCP HTTP server (`beagle-mcp.service`) to the public internet so it can be used as a **claude.ai** connector.

## Endpoints

| Path | Method | Purpose |
|------|--------|---------|
| `/health` | GET | Liveness check (no auth) |
| `/sse` | GET | Legacy SSE transport (recommended for claude.ai) |
| `/message?sessionId=...` | POST | Legacy SSE message channel |
| `/mcp` | POST | Streamable HTTP transport (MCP SDK modern default) |

## Authentication (recommended)

BEAGLE MCP supports a shared bearer token:

- Enable: `MCP_ENABLE_AUTH=true`
- Secret: `MCP_AUTH_TOKEN=<random>`
- Store on the host in `/etc/beagle-mcp.env` with mode `0600`
- `/health` stays public; `/mcp`, `/sse`, and `/message` require `Authorization: Bearer <token>`

Example:

```bash
sudo install -m 600 /dev/null /etc/beagle-mcp.env
sudo bash -lc 'cat >>/etc/beagle-mcp.env <<EOF
MCP_ENABLE_AUTH=true
MCP_AUTH_TOKEN=$(openssl rand -hex 32)
EOF'
sudo systemctl restart beagle-mcp.service
```

## Cloudflare Tunnel (quick URL)

Use `cloudflared` to expose `http://127.0.0.1:3000` over HTTPS. A reference systemd unit is in `scripts/systemd/cloudflared-beagle.service`.

Install/enable (quick tunnel):

```bash
sudo cp scripts/systemd/cloudflared-beagle.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now cloudflared-beagle.service
```

Get the current public URL (quick tunnels change on restart):

```bash
PUBLIC_URL="$(sudo journalctl -u cloudflared-beagle.service --no-pager -n 200 \
  | rg -o 'https://[a-z0-9-]+\\.trycloudflare\\.com' | tail -n 1)"
echo "$PUBLIC_URL"
```

## claude.ai setup

1. claude.ai → Settings → Connectors → Add custom MCP server
2. URL: `${PUBLIC_URL}/sse`
3. Auth: Bearer token from `/etc/beagle-mcp.env`

## Smoke tests

```bash
curl -fsS http://127.0.0.1:3000/health
curl -fsS "${PUBLIC_URL}/health"

set -a; source /etc/beagle-mcp.env; set +a
curl -sS --max-time 5 -H "Authorization: Bearer $MCP_AUTH_TOKEN" "${PUBLIC_URL}/sse" \
  -o /dev/null -w "code=%{http_code} bytes=%{size_download}\n" || true
```

## Troubleshooting

- MCP logs: `journalctl -u beagle-mcp.service -n 200 --no-pager`
- Tunnel logs: `journalctl -u cloudflared-beagle.service -n 200 --no-pager`
- If SSE appears “stuck”: ensure your proxy/CDN does not buffer SSE responses (BEAGLE emits padding to reduce buffering issues).

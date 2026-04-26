# Beagle MCP Public DNS

Minimal Terraform for the Claude-first MCP rollout.

This directory only manages:

- `mcp.agourakis.com` CNAME, proxied through Cloudflare

It deliberately avoids the broader `terraform/cloudflare.tf` zone configuration so the MCP connector can go public without touching `api`, `ws`, `tracing`, `metrics`, `dashboard`, root, or `www` routes.

## Inputs

- `cloudflare_api_token`: Cloudflare API token with DNS edit access.
- `cloudflare_zone_id`: zone ID for `agourakis.com`.
- `beagle_tunnel_cname`: target for the dedicated `beagle-production` tunnel, usually `<tunnel-id>.cfargotunnel.com`.

## Apply

```bash
terraform -chdir=terraform/mcp-public init
terraform -chdir=terraform/mcp-public plan \
  -var='cloudflare_zone_id=ZONE_ID' \
  -var='beagle_tunnel_cname=TUNNEL_ID.cfargotunnel.com'
terraform -chdir=terraform/mcp-public apply \
  -var='cloudflare_zone_id=ZONE_ID' \
  -var='beagle_tunnel_cname=TUNNEL_ID.cfargotunnel.com'
```

Pass `cloudflare_api_token` through `TF_VAR_cloudflare_api_token` or an ignored `.tfvars` file. Do not commit secrets.

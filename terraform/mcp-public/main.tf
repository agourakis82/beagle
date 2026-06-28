# Minimal Cloudflare DNS for the public Beagle MCP connector.
#
# This module intentionally manages only mcp.agourakis.com. Use it for the
# Claude-first rollout instead of the broad zone-level Terraform until the other
# public hostnames are revalidated.

terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token with DNS edit access for agourakis.com"
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID for agourakis.com"
  type        = string
}

variable "beagle_tunnel_cname" {
  description = "Cloudflare Tunnel CNAME target, usually <tunnel-id>.cfargotunnel.com"
  type        = string
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

resource "cloudflare_record" "mcp" {
  zone_id = var.cloudflare_zone_id
  name    = "mcp"
  value   = var.beagle_tunnel_cname
  type    = "CNAME"
  proxied = true
  ttl     = 1
}

output "mcp_hostname" {
  value = "mcp.agourakis.com"
}

output "mcp_tunnel_target" {
  value = var.beagle_tunnel_cname
}

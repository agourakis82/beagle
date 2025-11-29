# Terraform configuration for Cloudflare DNS and services
# Domain: agourakis.com

terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
}

# Variables
variable "cloudflare_api_token" {
  description = "Cloudflare API token"
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID for agourakis.com"
  type        = string
}

variable "cloudflare_account_id" {
  description = "Cloudflare Account ID"
  type        = string
}

variable "tunnel_secret" {
  description = "Cloudflare Tunnel secret"
  type        = string
  sensitive   = true
}

# Provider configuration
provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# Cloudflare Tunnel
resource "cloudflare_tunnel" "beagle_production" {
  account_id = var.cloudflare_account_id
  name       = "beagle-production"
  secret     = var.tunnel_secret
}

# DNS Records - Root domain
resource "cloudflare_record" "root" {
  zone_id = var.cloudflare_zone_id
  name    = "@"
  value   = cloudflare_tunnel.beagle_production.cname
  type    = "CNAME"
  proxied = true
  ttl     = 1  # Automatic
}

resource "cloudflare_record" "www" {
  zone_id = var.cloudflare_zone_id
  name    = "www"
  value   = cloudflare_tunnel.beagle_production.cname
  type    = "CNAME"
  proxied = true
  ttl     = 1
}

# API Services
resource "cloudflare_record" "api" {
  zone_id = var.cloudflare_zone_id
  name    = "api"
  value   = cloudflare_tunnel.beagle_production.cname
  type    = "CNAME"
  proxied = true
  ttl     = 1
}

resource "cloudflare_record" "ws" {
  zone_id = var.cloudflare_zone_id
  name    = "ws"
  value   = cloudflare_tunnel.beagle_production.cname
  type    = "CNAME"
  proxied = true
  ttl     = 1
}

resource "cloudflare_record" "grpc" {
  zone_id = var.cloudflare_zone_id
  name    = "grpc"
  value   = cloudflare_tunnel.beagle_production.cname
  type    = "CNAME"
  proxied = true
  ttl     = 1
}

# Observability
resource "cloudflare_record" "tracing" {
  zone_id = var.cloudflare_zone_id
  name    = "tracing"
  value   = cloudflare_tunnel.beagle_production.cname
  type    = "CNAME"
  proxied = true
  ttl     = 1
}

resource "cloudflare_record" "metrics" {
  zone_id = var.cloudflare_zone_id
  name    = "metrics"
  value   = cloudflare_tunnel.beagle_production.cname
  type    = "CNAME"
  proxied = true
  ttl     = 1
}

resource "cloudflare_record" "dashboard" {
  zone_id = var.cloudflare_zone_id
  name    = "dashboard"
  value   = cloudflare_tunnel.beagle_production.cname
  type    = "CNAME"
  proxied = true
  ttl     = 1
}

# Development environments
resource "cloudflare_record" "dev" {
  zone_id = var.cloudflare_zone_id
  name    = "dev"
  value   = cloudflare_tunnel.beagle_production.cname
  type    = "CNAME"
  proxied = true
  ttl     = 1
}

resource "cloudflare_record" "staging" {
  zone_id = var.cloudflare_zone_id
  name    = "staging"
  value   = cloudflare_tunnel.beagle_production.cname
  type    = "CNAME"
  proxied = true
  ttl     = 1
}

# Health and Status
resource "cloudflare_record" "health" {
  zone_id = var.cloudflare_zone_id
  name    = "health"
  value   = cloudflare_tunnel.beagle_production.cname
  type    = "CNAME"
  proxied = true
  ttl     = 1
}

resource "cloudflare_record" "status" {
  zone_id = var.cloudflare_zone_id
  name    = "status"
  value   = cloudflare_tunnel.beagle_production.cname
  type    = "CNAME"
  proxied = true
  ttl     = 1
}

# Documentation
resource "cloudflare_record" "docs" {
  zone_id = var.cloudflare_zone_id
  name    = "docs"
  value   = cloudflare_tunnel.beagle_production.cname
  type    = "CNAME"
  proxied = true
  ttl     = 1
}

# TXT Records
resource "cloudflare_record" "spf" {
  zone_id = var.cloudflare_zone_id
  name    = "@"
  type    = "TXT"
  value   = "v=spf1 include:_spf.google.com ~all"
  ttl     = 1
}

resource "cloudflare_record" "dmarc" {
  zone_id = var.cloudflare_zone_id
  name    = "_dmarc"
  type    = "TXT"
  value   = "v=DMARC1; p=quarantine; rua=mailto:dmarc@agourakis.com; ruf=mailto:dmarc-forensics@agourakis.com; fo=1"
  ttl     = 1
}

resource "cloudflare_record" "domain_verification" {
  zone_id = var.cloudflare_zone_id
  name    = "@"
  type    = "TXT"
  value   = "beagle-verification=2024-production-cluster"
  ttl     = 1
}

# Page Rules
resource "cloudflare_page_rule" "api_bypass_cache" {
  zone_id  = var.cloudflare_zone_id
  target   = "api.agourakis.com/*"
  priority = 1

  actions {
    cache_level = "bypass"
    security_level = "high"
    ssl = "strict"
  }
}

resource "cloudflare_page_rule" "ws_websocket" {
  zone_id  = var.cloudflare_zone_id
  target   = "ws.agourakis.com/*"
  priority = 2

  actions {
    cache_level = "bypass"
    security_level = "medium"
    ssl = "strict"
    # WebSocket support is automatic when proxied
  }
}

resource "cloudflare_page_rule" "static_cache" {
  zone_id  = var.cloudflare_zone_id
  target   = "agourakis.com/static/*"
  priority = 3

  actions {
    cache_level = "cache_everything"
    edge_cache_ttl = 2592000  # 30 days
    browser_cache_ttl = 86400  # 1 day
    ssl = "strict"
  }
}

# WAF Custom Rules
resource "cloudflare_ruleset" "waf_custom" {
  zone_id = var.cloudflare_zone_id
  name    = "BEAGLE WAF Custom Rules"
  kind    = "zone"
  phase   = "http_request_firewall_custom"

  rules {
    action = "block"
    expression = "(http.request.uri.path contains \"/api/\" and not http.request.headers[\"authorization\"][0] contains \"Bearer\")"
    description = "Block API requests without authentication"
  }

  rules {
    action = "challenge"
    expression = "(http.request.uri.path contains \"/api/\" and rate(5m) > 1000)"
    description = "Challenge high rate API requests"
  }

  rules {
    action = "block"
    expression = "(http.user_agent contains \"bot\" and not http.user_agent contains \"googlebot\")"
    description = "Block unwanted bots"
  }
}

# Rate Limiting Rules
resource "cloudflare_rate_limit" "api_limit" {
  zone_id = var.cloudflare_zone_id
  threshold = 1000
  period = 60  # 1 minute

  match {
    request {
      url_pattern = "api.agourakis.com/*"
    }
  }

  action {
    mode = "challenge"
    timeout = 600  # 10 minutes
  }

  correlate {
    by = "nat"
  }

  description = "Rate limit API to 1000 requests per minute"
  disabled = false
}

resource "cloudflare_rate_limit" "ws_connections" {
  zone_id = var.cloudflare_zone_id
  threshold = 100
  period = 60

  match {
    request {
      url_pattern = "ws.agourakis.com/*"
    }
  }

  action {
    mode = "challenge"
    timeout = 1800  # 30 minutes
  }

  correlate {
    by = "nat"
  }

  description = "Limit WebSocket connections to 100 per IP per minute"
  disabled = false
}

# Health Check
resource "cloudflare_healthcheck" "beagle_api" {
  zone_id = var.cloudflare_zone_id
  name = "BEAGLE API Health Check"
  description = "Monitor BEAGLE API availability"
  address = "api.agourakis.com"
  suspended = false
  check_regions = ["WNAM", "ENAM", "WEU", "EEU", "SEAS"]

  type = "HTTPS"
  port = 443
  method = "GET"
  path = "/health"
  expected_codes = "200"
  expected_body = "ok"

  interval = 60
  retries = 2
  timeout = 5

  header {
    header = "Host"
    values = ["api.agourakis.com"]
  }
}

# Load Balancer Pool
resource "cloudflare_load_balancer_pool" "beagle_origins" {
  account_id = var.cloudflare_account_id
  name = "beagle-production-pool"

  origins {
    name = "k8s-cluster-1"
    address = "cluster1.agourakis.com"
    enabled = true
    weight = 50
  }

  origins {
    name = "k8s-cluster-2"
    address = "cluster2.agourakis.com"
    enabled = true
    weight = 50
  }

  check_regions = ["WNAM", "ENAM", "WEU"]
  description = "BEAGLE production Kubernetes clusters"

  origin_steering {
    policy = "dynamic_latency"
  }

  minimum_origins = 1

  monitor = cloudflare_load_balancer_monitor.beagle_monitor.id
}

# Load Balancer Monitor
resource "cloudflare_load_balancer_monitor" "beagle_monitor" {
  account_id = var.cloudflare_account_id
  type = "https"
  expected_codes = "200"
  method = "GET"
  timeout = 5
  path = "/health"
  interval = 60
  retries = 2
  description = "BEAGLE health monitor"

  header {
    header = "Host"
    values = ["api.agourakis.com"]
  }
}

# Load Balancer
resource "cloudflare_load_balancer" "beagle_lb" {
  zone_id = var.cloudflare_zone_id
  name = "api.agourakis.com"
  fallback_pool_id = cloudflare_load_balancer_pool.beagle_origins.id
  default_pool_ids = [cloudflare_load_balancer_pool.beagle_origins.id]
  description = "BEAGLE API load balancer"
  ttl = 30
  steering_policy = "dynamic_latency"
  proxied = true
}

# SSL/TLS Settings
resource "cloudflare_zone_settings_override" "agourakis_settings" {
  zone_id = var.cloudflare_zone_id

  settings {
    # SSL/TLS
    ssl = "strict"
    min_tls_version = "1.2"
    tls_1_3 = "on"
    always_use_https = "on"
    automatic_https_rewrites = "on"

    # Security
    security_level = "medium"
    challenge_ttl = 1800
    browser_check = "on"

    # Performance
    brotli = "on"
    minify {
      css = "on"
      html = "on"
      js = "on"
    }
    rocket_loader = "off"  # Conflicts with WebSocket

    # Caching
    cache_level = "aggressive"
    browser_cache_ttl = 14400

    # Network
    http3 = "on"
    websockets = "on"
    opportunistic_encryption = "on"

    # Privacy
    privacy_pass = "on"
  }
}

# Firewall Rules
resource "cloudflare_filter" "block_countries" {
  zone_id = var.cloudflare_zone_id
  description = "Block high-risk countries"
  expression = "(ip.geoip.country in {\"CN\" \"RU\" \"KP\"})"
}

resource "cloudflare_firewall_rule" "block_countries_rule" {
  zone_id = var.cloudflare_zone_id
  description = "Block traffic from high-risk countries"
  filter_id = cloudflare_filter.block_countries.id
  action = "block"
  priority = 1
}

# Workers KV Namespace for edge caching
resource "cloudflare_workers_kv_namespace" "beagle_cache" {
  account_id = var.cloudflare_account_id
  title = "beagle_edge_cache"
}

# Output important values
output "tunnel_id" {
  value = cloudflare_tunnel.beagle_production.id
  description = "Cloudflare Tunnel ID"
}

output "tunnel_cname" {
  value = cloudflare_tunnel.beagle_production.cname
  description = "Cloudflare Tunnel CNAME"
}

output "kv_namespace_id" {
  value = cloudflare_workers_kv_namespace.beagle_cache.id
  description = "Workers KV Namespace ID for edge caching"
}

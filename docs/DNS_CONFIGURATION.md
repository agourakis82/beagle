# DNS Configuration for agourakis.com

## Domain Structure

### Primary Domain
- **agourakis.com** - Main BEAGLE platform
- **www.agourakis.com** - WWW redirect

### Subdomains

#### API Services
- **api.agourakis.com** - REST API endpoints
- **ws.agourakis.com** - WebSocket real-time connections
- **grpc.agourakis.com** - gRPC services (future)

#### Observability
- **tracing.agourakis.com** - Jaeger distributed tracing
- **metrics.agourakis.com** - Prometheus metrics
- **dashboard.agourakis.com** - Grafana dashboards
- **logs.agourakis.com** - Centralized logging (future)

#### Development
- **dev.agourakis.com** - Development environment
- **staging.agourakis.com** - Staging environment
- **health.agourakis.com** - Health check endpoints

#### Documentation
- **docs.agourakis.com** - API documentation
- **status.agourakis.com** - Status page

## Cloudflare DNS Records

### A Records
```
Type    Name                    Value           Proxy   TTL
A       agourakis.com          <Tunnel-IP>     Yes     Auto
A       www                    <Tunnel-IP>     Yes     Auto
```

### CNAME Records
```
Type    Name                    Value                   Proxy   TTL
CNAME   api                     <tunnel>.cfargotunnel.com   Yes     Auto
CNAME   ws                      <tunnel>.cfargotunnel.com   Yes     Auto
CNAME   tracing                 <tunnel>.cfargotunnel.com   Yes     Auto
CNAME   metrics                 <tunnel>.cfargotunnel.com   Yes     Auto
CNAME   dashboard               <tunnel>.cfargotunnel.com   Yes     Auto
CNAME   dev                     <tunnel>.cfargotunnel.com   Yes     Auto
CNAME   staging                 <tunnel>.cfargotunnel.com   Yes     Auto
CNAME   health                  <tunnel>.cfargotunnel.com   Yes     Auto
CNAME   docs                    <tunnel>.cfargotunnel.com   Yes     Auto
CNAME   status                  <tunnel>.cfargotunnel.com   Yes     Auto
```

### MX Records (Email)
```
Type    Name                    Value                   Priority    TTL
MX      agourakis.com          mail.agourakis.com      10          Auto
```

### TXT Records
```
Type    Name                    Value                                           TTL
TXT     agourakis.com          "v=spf1 include:_spf.google.com ~all"         Auto
TXT     _dmarc                  "v=DMARC1; p=quarantine; rua=mailto:..."      Auto
TXT     agourakis.com          "beagle-verification=..."                      Auto
```

## Cloudflare Settings

### SSL/TLS
- **Mode**: Full (strict)
- **Edge Certificates**: Enabled
- **Always Use HTTPS**: Yes
- **HSTS**: Enabled with includeSubDomains
- **Minimum TLS Version**: 1.2
- **TLS 1.3**: Enabled

### Security
- **WAF**: Enabled with custom rules
- **DDoS Protection**: Enabled
- **Rate Limiting**: 
  - API: 1000 req/min per IP
  - WebSocket: 100 connections per IP
- **Bot Fight Mode**: Enabled
- **Challenge Passage**: 30 minutes

### Performance
- **Caching Level**: Standard
- **Browser Cache TTL**: 4 hours
- **Auto Minify**: JS, CSS, HTML
- **Brotli**: Enabled
- **Rocket Loader**: Disabled (conflicts with WebSocket)
- **Argo Smart Routing**: Enabled
- **Tiered Cache**: Enabled

### Page Rules
1. **api.agourakis.com/***
   - Cache Level: Bypass
   - Security Level: High
   
2. **ws.agourakis.com/***
   - Cache Level: Bypass
   - WebSockets: Enabled
   
3. **agourakis.com/static/***
   - Cache Level: Cache Everything
   - Edge Cache TTL: 1 month
   - Browser Cache TTL: 1 month

### Workers (Edge Computing)
```javascript
// Example Worker for A/B testing
addEventListener('fetch', event => {
  event.respondWith(handleRequest(event.request))
})

async function handleRequest(request) {
  const url = new URL(request.url)
  
  // A/B test for API versions
  if (url.hostname === 'api.agourakis.com') {
    const cookie = request.headers.get('Cookie')
    const variant = cookie?.includes('variant=b') ? 'b' : 'a'
    
    if (variant === 'b') {
      // Route to v2 API
      url.hostname = 'api-v2.agourakis.com'
    }
  }
  
  return fetch(url, request)
}
```

### Load Balancing
- **Pool Name**: beagle-production
- **Origins**:
  - Origin 1: k8s-cluster-1.agourakis.com (weight: 50)
  - Origin 2: k8s-cluster-2.agourakis.com (weight: 50)
- **Health Checks**: Every 60 seconds
- **Steering Policy**: Dynamic

### Analytics & Monitoring
- **Web Analytics**: Enabled
- **Real User Monitoring (RUM)**: Enabled
- **Error Pages**: Custom 404, 500, 502 pages
- **Email Alerts**:
  - High error rate
  - DDoS attacks
  - SSL certificate issues
  - Origin unreachable

## Cloudflare Tunnel Setup

### Installation
```bash
# Download cloudflared
wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
sudo mv cloudflared-linux-amd64 /usr/local/bin/cloudflared
sudo chmod +x /usr/local/bin/cloudflared

# Login to Cloudflare
cloudflared tunnel login

# Create tunnel
cloudflared tunnel create beagle-production

# Create credentials secret
kubectl create secret generic cloudflared-credentials \
  --from-file=credentials.json=/home/user/.cloudflared/<tunnel-id>.json \
  -n cloudflare-system

# Route DNS
cloudflared tunnel route dns beagle-production api.agourakis.com
cloudflared tunnel route dns beagle-production ws.agourakis.com
cloudflared tunnel route dns beagle-production tracing.agourakis.com
# ... repeat for all subdomains
```

### Monitoring Tunnel Health
```bash
# Check tunnel status
cloudflared tunnel info beagle-production

# List active connections
cloudflared tunnel list

# View metrics
curl http://localhost:2000/metrics
```

## Security Headers (via Cloudflare Transform Rules)

```
X-Frame-Options: DENY
X-Content-Type-Options: nosniff
X-XSS-Protection: 1; mode=block
Referrer-Policy: strict-origin-when-cross-origin
Content-Security-Policy: default-src 'self'; script-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net; style-src 'self' 'unsafe-inline'
Permissions-Policy: geolocation=(), microphone=(), camera=()
```

## Backup DNS Providers

### Secondary DNS (for redundancy)
- **Provider**: AWS Route53
- **Sync**: Every 5 minutes via API
- **Failover**: Automatic with health checks

## Cost Optimization

### Cloudflare Plans
- **Current**: Pro ($20/month)
- **Recommended for Production**: Business ($200/month)
  - Advanced DDoS protection
  - 100% uptime SLA
  - Prioritized support
  - Custom SSL certificates

### Bandwidth Estimates
- API calls: ~10TB/month
- WebSocket: ~5TB/month  
- Static assets: ~2TB/month
- **Total**: ~17TB/month (covered under current plan)

## Maintenance Windows

- **DNS Updates**: Instant propagation via Cloudflare
- **Tunnel Restarts**: Zero downtime with multiple replicas
- **Certificate Renewal**: Automatic via Cloudflare

## Emergency Procedures

### Tunnel Down
```bash
# Restart tunnel pods
kubectl rollout restart deployment/cloudflared -n cloudflare-system

# Check logs
kubectl logs -n cloudflare-system -l app=cloudflared --tail=100
```

### DDoS Attack
1. Enable "Under Attack" mode in Cloudflare
2. Increase challenge difficulty
3. Add rate limiting rules
4. Block suspicious IPs/ASNs

### SSL Issues
1. Check certificate status in Cloudflare dashboard
2. Verify origin certificates are valid
3. Re-issue if needed via API
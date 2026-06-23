# Physiome Endpoint Exposure to iPhone

**Status:** Design for exposure (not deployed). Documents the exact Cloudflare routing and authentication configuration required to make the physiome ingest service accessible from the iOS Beagle suite.

**Service Details:**
- Internal: `physiome-ingest.beagle.svc.cluster.local:8080` (Express app on port 8090 internally)
- Namespace: `beagle`
- Auth: Bearer token from `physiome-secrets/PHYSIOME_INGEST_TOKEN` + `X-Beagle-Consumer: beagle-operator` header
- Endpoint path: `/api/physiome/ingest` (POST, typed batch of health_samples and weather_obs)

---

## Current Routing Architecture

### Cloudflare Tunnel (beagle-production)
- **Tunnel ID:** `e1145ee4` (example; actual stored in CF account)
- **Public host:** `beagle.chiuratto.ai` and `*.agourakis.com`
- **Mechanism:** CloudFlare Tunnel (formerly Argo) with cloudflared agent deployed in K8s `cloudflare-system` namespace
- **Config location:** `/home/devsounio/beagle/k8s/cloudflare-config.yaml` (ConfigMap `cloudflare-config`, key `config.yaml`)

### Current Hostname→Service Mapping (Cloudflared Ingress Rules)
The file `k8s/cloudflare-config.yaml` ConfigMap defines these active routes:

```yaml
ingress:
  - hostname: api.agourakis.com → http://beagle-server.beagle:8080
  - hostname: mcp.agourakis.com → http://beagle-mcp-server.beagle:3000
  - hostname: ws.agourakis.com → http://beagle-websocket.beagle:8081
  - hostname: tracing.agourakis.com → http://jaeger-query.jaeger:16686
  - hostname: metrics.agourakis.com → http://prometheus-server.monitoring:9090
  - hostname: dashboard.agourakis.com → http://grafana.monitoring:3000
  - hostname: agourakis.com → http://beagle-frontend.beagle:3000
  - hostname: www.agourakis.com → http://beagle-frontend.beagle:3000
  - hostname: health.agourakis.com → http://beagle-server.beagle:8080/health
  - service: http_status:404 (catch-all)
```

**Key observation:** Path-based routing (e.g., `/api/physiome/*`) **cannot** be done in cloudflared ingress rules; each rule is hostname-based. To expose physiome at a path under `api.agourakis.com`, we have two options.

---

## Two Approaches to Expose Physiome

### **Option A: Dedicated Hostname (Recommended for isolation)**

Create a separate hostname `physiome.agourakis.com` routed directly to physiome-ingest.

**Pros:**
- Clean separation; no cross-service coupling in beagle-server
- Physiome can evolve independently
- Easier to scale/debug independently

**Cons:**
- Requires separate DNS + CF tunnel rule
- Client must know two hostnames instead of one unified API endpoint

**Implementation steps** (see below under "Option A: Implementation").

---

### **Option B: Path-based Routing via API Gateway (Recommended for UX)**

Introduce a lightweight reverse proxy (e.g., Kong, Traefik in path-routing mode, or hand-rolled Axum forwarder) that:
- Listens on `api.agourakis.com` (routed from cloudflared)
- Routes `/api/physiome/*` → `physiome-ingest.beagle:8080`
- Routes `/api/*` (everything else) → `beagle-server.beagle:8080`

**Pros:**
- Single hostname for all API consumers
- Client sees unified API surface
- Can be iterated in the API gateway without touching cloudflared config

**Cons:**
- Adds a new service (gateway) to operate
- Adds one proxy hop (minor latency impact)
- Requires health checks for the gateway itself

**Implementation steps** (see below under "Option B: Implementation").

---

## Recommended Path Forward

**Use Option B** (API Gateway) because:
1. The iOS app expects `https://beagle.chiuratto.ai/api/physiome/ingest` (single hostname as mentioned in design spec).
2. Beagle is designed as a unified platform; fragmenting into multiple hostnames breaks that mental model.
3. A stateless reverse proxy is operationally simpler than managing multiple tunnel rules.

---

## Option A Implementation: Dedicated Hostname

### Step 1: Update Cloudflare Ingress Config

**File:** `/home/devsounio/beagle/k8s/cloudflare-config.yaml`

Add the following rule **before** the catch-all `http_status:404`:

```yaml
# Physiome Endpoint
- hostname: physiome.agourakis.com
  service: http://physiome-ingest.beagle:8080
  originRequest:
    noTLSVerify: false
    connectTimeout: 30s
    tcpKeepAlive: 30s
    keepAliveConnections: 100
    keepAliveTimeout: 90s
    httpHostHeader: physiome.agourakis.com
```

**Order matters:** Insert this rule **above** the catch-all (the last `service: http_status:404`), so it matches before the catch-all rejects unknown hostnames.

### Step 2: Terraform DNS Record (Optional but Recommended)

Add a DNS CNAME in `terraform/cloudflare.tf`:

```hcl
resource "cloudflare_record" "physiome" {
  zone_id = var.cloudflare_zone_id
  name    = "physiome"
  value   = cloudflare_tunnel.beagle_production.cname
  type    = "CNAME"
  proxied = true
  ttl     = 1
}
```

**Note:** If you prefer to skip Terraform and add the DNS record manually via the CF dashboard, that's valid. Terraform gives you version control + audit trail.

### Step 3: iOS App Configuration

Update the iOS Beagle app's config to use:
```
PHYSIOME_INGEST_URL = "https://physiome.agourakis.com/api/physiome/ingest"
```

And pass the Bearer token from the Kubernetes secret:
```
Authorization: Bearer <value of physiome-secrets/PHYSIOME_INGEST_TOKEN>
```

### Step 4: Apply

```bash
# In the cluster, update the ConfigMap
kubectl apply -f /home/devsounio/beagle/k8s/cloudflare-config.yaml

# (Cloudflared watches the ConfigMap and reloads automatically)

# If using Terraform:
cd /home/devsounio/beagle/terraform
terraform apply \
  -var="cloudflare_api_token=$CF_API_TOKEN" \
  -var="cloudflare_zone_id=$CF_ZONE_ID" \
  -var="cloudflare_account_id=$CF_ACCOUNT_ID"
```

---

## Option B Implementation: API Gateway (Preferred)

### Step 1: Create API Gateway Service

Add a new lightweight reverse proxy. Example using a simple Node.js/Express forwarder or Rust/Axum:

**File:** `/home/devsounio/beagle/k8s/api-gateway.yaml` (new file)

```yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-gateway
  namespace: beagle
spec:
  replicas: 2
  selector:
    matchLabels:
      app: api-gateway
  template:
    metadata:
      labels:
        app: api-gateway
    spec:
      containers:
        - name: api-gateway
          image: 192.168.3.207:5003/api-gateway:0.1.0
          ports:
            - containerPort: 8080
          env:
            - name: PORT
              value: "8080"
            - name: BEAGLE_SERVER_URL
              value: "http://beagle-server.beagle:8080"
            - name: PHYSIOME_INGEST_URL
              value: "http://physiome-ingest.beagle:8080"
          livenessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 3
          resources:
            requests:
              cpu: "50m"
              memory: "64Mi"
            limits:
              cpu: "500m"
              memory: "256Mi"

---
apiVersion: v1
kind: Service
metadata:
  name: api-gateway
  namespace: beagle
spec:
  selector:
    app: api-gateway
  ports:
    - port: 8080
      targetPort: 8080
```

**Gateway Logic** (pseudocode; implement in your language of choice):

```javascript
// Node.js/Express example
import express from 'express';
import { createProxyMiddleware } from 'express-http-proxy';

const app = express();

// Physiome routes → physiome-ingest
app.use('/api/physiome', createProxyMiddleware({
  target: process.env.PHYSIOME_INGEST_URL || 'http://physiome-ingest.beagle:8080',
  changeOrigin: true,
  pathRewrite: { '^/api/physiome': '' }, // strip /api/physiome, forward as /
}));

// All other /api/* → beagle-server
app.use('/api', createProxyMiddleware({
  target: process.env.BEAGLE_SERVER_URL || 'http://beagle-server.beagle:8080',
  changeOrigin: true,
}));

// Catch-all
app.use((req, res) => res.status(404).json({ error: 'Not found' }));

app.listen(process.env.PORT || 8080);
```

### Step 2: Update Cloudflared Ingress

**File:** `/home/devsounio/beagle/k8s/cloudflare-config.yaml`

Replace the `api.agourakis.com` rule:

```yaml
# Main BEAGLE API Gateway (now routes via gateway which multiplexes to services)
- hostname: api.agourakis.com
  service: http://api-gateway.beagle:8080
  originRequest:
    noTLSVerify: false
    connectTimeout: 30s
    tcpKeepAlive: 30s
    keepAliveConnections: 100
    keepAliveTimeout: 90s
    httpHostHeader: api.agourakis.com
```

### Step 3: iOS App Configuration

Update the iOS app to continue using:
```
PHYSIOME_INGEST_URL = "https://beagle.chiuratto.ai/api/physiome/ingest"
```
(or whatever the main API domain is; same endpoint path, routed through gateway internally)

### Step 4: Apply

```bash
# Build and push the gateway image
docker build -t 192.168.3.207:5003/api-gateway:0.1.0 .
docker push 192.168.3.207:5003/api-gateway:0.1.0

# Deploy
kubectl apply -f /home/devsounio/beagle/k8s/api-gateway.yaml
kubectl apply -f /home/devsounio/beagle/k8s/cloudflare-config.yaml

# Verify
kubectl rollout status deployment/api-gateway -n beagle
```

---

## Authentication & Token Management

### PHYSIOME_INGEST_TOKEN Secret

**Location in cluster:**
```
Secret: physiome-secrets
Namespace: beagle
Key: PHYSIOME_INGEST_TOKEN
```

**Current value:**
```bash
kubectl get secret physiome-secrets -n beagle -o jsonpath='{.data.PHYSIOME_INGEST_TOKEN}' | base64 -d
```

### Token Deployment to iOS App

The PHYSIOME_INGEST_TOKEN must be:

1. **Retrieved** from the cluster secret (during CI/build or stored in Xcode build settings)
2. **Embedded** in the iOS app (as a build-time constant, NOT hardcoded in source)
3. **Sent** with every `/api/physiome/ingest` request:
   ```
   Authorization: Bearer <PHYSIOME_INGEST_TOKEN>
   X-Beagle-Consumer: beagle-operator
   ```

**Example (Swift):**
```swift
var request = URLRequest(url: url)
request.httpMethod = "POST"
request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
request.setValue("beagle-operator", forHTTPHeaderField: "X-Beagle-Consumer")
request.setValue("application/json", forHTTPHeaderField: "Content-Type")
```

### Token Rotation

To rotate the token:

```bash
# Generate a new secure token
NEW_TOKEN=$(openssl rand -hex 32)

# Update the secret
kubectl patch secret physiome-secrets -n beagle \
  --type merge -p "{\"stringData\":{\"PHYSIOME_INGEST_TOKEN\":\"$NEW_TOKEN\"}}"

# Verify
kubectl get secret physiome-secrets -n beagle -o jsonpath='{.data.PHYSIOME_INGEST_TOKEN}' | base64 -d

# Update the iOS app's token constant and rebuild
```

---

## Endpoint Contract

### Request

```
POST https://beagle.chiuratto.ai/api/physiome/ingest
  (or https://physiome.agourakis.com/api/physiome/ingest if Option A)

Headers:
  Authorization: Bearer <PHYSIOME_INGEST_TOKEN>
  X-Beagle-Consumer: beagle-operator
  Content-Type: application/json

Body (JSON):
{
  "health_samples": [
    {
      "uuid": "550e8400-e29b-41d4-a716-446655440000",
      "ts": "2026-06-23T10:30:00Z",
      "type": "HKQuantityTypeIdentifierHeartRate",
      "value": 72.0,
      "unit": "count/min",
      "source": "Apple Watch",
      "device": "SE2"
    },
    ...
  ],
  "weather_obs": [
    {
      "ts": "2026-06-23T10:30:00Z",
      "lat": -23.5505,
      "lon": -46.6333,
      "temp_c": 24.5,
      "pressure_hpa": 1013.2,
      "humidity": 65.0,
      "uv_index": 6.0,
      "precip": 0.0,
      "aqi": 45,
      "condition": "clear"
    }
  ]
}
```

### Response

**Success (200 OK):**
```json
{
  "status": "ok",
  "health_samples_accepted": 15,
  "weather_obs_accepted": 1,
  "failed": []
}
```

**Error (400 Bad Request):**
```json
{
  "error": "invalid_request",
  "details": "missing required field: type"
}
```

**Error (401 Unauthorized):**
```json
{
  "error": "unauthorized",
  "details": "Bearer token is invalid or expired"
}
```

---

## Cloudflare WAF / Page Rules Considerations

### Current WAF Rules (in terraform/cloudflare.tf)

The existing WAF ruleset blocks `/api/*` requests without a Bearer token:

```hcl
rules {
  action = "block"
  expression = "(http.request.uri.path contains \"/api/\" and not http.request.headers[\"authorization\"][0] contains \"Bearer\")"
  description = "Block API requests without authentication"
}
```

This **already** protects `/api/physiome/ingest`. No changes needed.

### Rate Limiting

Current limit: **1000 requests per minute per IP** (all `/api/*` paths).

For physiome:
- iOS batches typically 5–20 samples; payload ~2–5KB
- Expected cadence: **1–2 requests per day** (morning sync + before bed)
- This is **well under** 1000 req/min; no tuning needed

If you implement batch telemetry (e.g., background delivery every hour), adjust the limit:

```hcl
# Add a more lenient limit for /api/physiome specifically
resource "cloudflare_rate_limit" "physiome_limit" {
  zone_id = var.cloudflare_zone_id
  threshold = 100  # 100 requests per minute
  period = 60

  match {
    request {
      url_pattern = "api.agourakis.com/api/physiome/*"
    }
  }

  action {
    mode = "challenge"
    timeout = 600
  }
}
```

---

## Verification Checklist (Before Deploying)

- [ ] **Cloudflare tunnel ID** and hostname verified (via CF dashboard or `cloudflared tunnel list`)
- [ ] **K8s physiome service** is running: `kubectl get svc physiome-ingest -n beagle`
- [ ] **K8s physiome secret** exists with valid token: `kubectl get secret physiome-secrets -n beagle`
- [ ] **Cloudflare config** updated (either Option A or B) and applied to the cluster
- [ ] **Cloudflared pods** have reloaded the config: check logs `kubectl logs -n cloudflare-system -l app=cloudflared`
- [ ] **DNS propagation** checked (if using Terraform): `nslookup physiome.agourakis.com` (Option A) or `nslookup api.agourakis.com` (Option B)
- [ ] **TLS certificate** provisioned by Cloudflare (automatic on first request if proxied=true)
- [ ] **End-to-end test** from iOS device: `curl -H "Authorization: Bearer <token>" https://.../api/physiome/ingest` (or actual HTTP client)

---

## Troubleshooting

### Service unreachable (504 Gateway Timeout)

1. **Check cloudflared logs:**
   ```bash
   kubectl logs -n cloudflare-system -l app=cloudflared | tail -50
   ```
   Look for connection errors to the origin.

2. **Check physiome-ingest health:**
   ```bash
   kubectl exec -it -n beagle <physiome-ingest-pod> -- curl localhost:8090/healthz
   ```

3. **Verify DNS resolution inside cluster:**
   ```bash
   kubectl run -it --rm debug --image=busybox:1.28 -- nslookup physiome-ingest.beagle.svc.cluster.local
   ```

### 401 Unauthorized

1. **Verify token is set:**
   ```bash
   kubectl get secret physiome-secrets -n beagle -o jsonpath='{.data.PHYSIOME_INGEST_TOKEN}' | base64 -d
   ```

2. **Verify iOS app is sending correct Bearer token** (use Fiddler/Charles to inspect network traffic)

3. **Verify X-Beagle-Consumer header** is present (physiome endpoint may require it)

### 400 Bad Request (Invalid JSON)

1. **Check request payload** matches the contract (all required fields present, types correct)
2. **Verify UUID format** for health samples (must be valid UUID v4)
3. **Check timestamp format** (must be ISO 8601 UTC, e.g., `2026-06-23T10:30:00Z`)

---

## Related Docs

- [[/home/devsounio/beagle/docs/superpowers/specs/2026-06-22-beagle-physiome-foundation-design.md]] — Design spec (data flow, architecture, components)
- [[/home/devsounio/beagle/k8s/physiome/physiome.yaml]] — K8s manifests (deployment, service, secrets)
- [[/home/devsounio/beagle/k8s/cloudflare-config.yaml]] — Cloudflare tunnel ingress rules
- [[/home/devsounio/beagle/terraform/cloudflare.tf]] — Cloudflare DNS & WAF (Terraform)
- [[/home/devsounio/CLAUDE.md#beagle-core-api-auth]] — API auth patterns (Bearer token + X-Beagle-Consumer)

---

## Decision Record

**Chosen approach:** Option B (API Gateway) for UX reasons (single hostname, unified API surface).

**Implementation order:**
1. Implement / select API gateway (hand-rolled Axum forwarder or use existing library)
2. Deploy gateway K8s manifests
3. Update cloudflared ingress rule to point `api.agourakis.com` → gateway
4. Verify routing with curl (internal cluster test)
5. Update iOS app to send requests to `https://beagle.chiuratto.ai/api/physiome/ingest`
6. Deploy iOS app build with embedded PHYSIOME_INGEST_TOKEN

**Risk mitigation:**
- Gateway is stateless; easy to scale / fail-over
- No changes to beagle-server or physiome-ingest required (they continue to work independently)
- Rollback: revert cloudflared config to point directly to beagle-server; gateway can be removed without affecting other services

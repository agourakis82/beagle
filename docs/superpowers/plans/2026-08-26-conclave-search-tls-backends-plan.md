# conclave-search TLS Backends Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make SearXNG and `beagle-core` reachable over HTTPS at stable, literal IPv4 addresses, with certificates that `conclave-search`'s TLS stack (dotted-decimal-IP-only, IP-SAN-checking, single-hardcoded-trust-bundle) can actually validate.

**Architecture:** A small internal `cert-manager` CA issues IP-SAN certificates to two new TLS-terminating fronts: a new SearXNG deployment, and a new standalone proxy in front of the existing, untouched `beagle-core` service. The CA root is then extracted for a future container build step to trust.

**Tech Stack:** Kubernetes (`beagle` namespace), `cert-manager` v1 CRDs, `nginx` as the TLS-terminating reverse proxy, `openssl` for verification, Sounio/`souc` for the final end-to-end check.

**Spec:** [`docs/superpowers/specs/2026-08-26-conclave-search-tls-backends-design.md`](../specs/2026-08-26-conclave-search-tls-backends-design.md)

## Global Constraints

- The internal CA's private key algorithm MUST be ECDSA P-256
  (`privateKey.algorithm: ECDSA`, `privateKey.size: 256` on every
  `Certificate` resource this plan creates) — never P-384/SHA-384, which
  `conclave-search`'s upstream TLS stack (the separate `sounio` repo)
  fails closed on (documented as D15 there:
  `stdlib/x509/cert.sio`'s `x509_verify_signature` explicitly rejects
  `ecdsa-with-SHA384`).
- Both pinned ClusterIPs must be confirmed free in the cluster's service
  CIDR before being hardcoded into any manifest — run
  `kubectl get svc -A -o jsonpath='{range .items[*]}{.spec.clusterIP}{"\n"}{end}' | sort -u`
  and check the candidate IPs are absent from that list. Do not assume the
  spec's example IPs (`10.96.250.10`/`10.96.250.11`) are free without
  checking at the time you run this task — another service may have taken
  them since the spec was written.
- Never modify the existing, live `beagle-core` `Deployment` or `Service`
  in any way. The HTTPS front is a wholly separate new `Service` + pod.
- `conclave-search`'s trust anchor lives at the fixed path
  `/etc/ssl/certs/ca-certificates.crt` inside whatever container
  eventually runs its binary. No such container/deploy pipeline exists yet
  (explicitly out of scope for this plan) — the deliverable here is the
  extracted CA root certificate and the exact command to regenerate the
  extraction, ready for that future pipeline to consume, not a running
  container with it baked in.
- Every new Kubernetes manifest gets `kubectl apply --dry-run=server -f -`
  verified before being applied for real.
- No AI-attribution in commit messages.
- This is a SHARED checkout (`/home/devsounio/beagle`, branch
  `reconcile/unify-beagle`) with substantial unrelated uncommitted work
  from other sessions. Never `git add -A` or `git add .` — stage only the
  exact files each task's own commit touches.
- All manifests in this plan live under a new directory,
  `k8s/conclave-search-tls/`, in the `beagle` repo — keep them together
  since they're one cohesive unit, separate from the rest of `k8s/`.

---

### Task 1: Internal CA (bootstrap issuer, root certificate, cluster issuer)

**Files:**
- Create: `k8s/conclave-search-tls/00-internal-ca.yaml`

**Interfaces:**
- Consumes: nothing (first task).
- Produces: a `ClusterIssuer` named `internal-ip-ca-issuer`, ready for
  Tasks 2 and 3 to reference via `issuerRef: { name: internal-ip-ca-issuer,
  kind: ClusterIssuer }`. A `Secret` named `internal-ip-ca-root` in the
  `cert-manager` namespace holding the CA's cert+key, which Task 4
  extracts from.

- [ ] **Step 1: Write the manifest**

```yaml
# k8s/conclave-search-tls/00-internal-ca.yaml
#
# Internal CA for issuing IP-SAN certificates that conclave-search's TLS
# stack (dotted-decimal-IP-only, checks that same IP against the server
# cert's SAN) can validate. No public CA will issue for private RFC 1918
# addresses, so this cluster runs its own, scoped to exactly this purpose.
#
# Private key algorithm is deliberately ECDSA P-256 (not P-384) --
# conclave-search's upstream TLS stack fails closed on
# ecdsa-with-SHA384-signed chains (documented as D15 in the sibling
# sounio repo). Issuing from a P-256 root avoids that gap entirely.
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: internal-ip-ca-bootstrap
  namespace: cert-manager
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: internal-ip-ca-root
  namespace: cert-manager
spec:
  isCA: true
  commonName: conclave-search-internal-ca
  secretName: internal-ip-ca-root
  privateKey:
    algorithm: ECDSA
    size: 256
  issuerRef:
    name: internal-ip-ca-bootstrap
    kind: Issuer
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: internal-ip-ca-issuer
spec:
  ca:
    secretName: internal-ip-ca-root
```

- [ ] **Step 2: Dry-run verify**

Run: `kubectl apply --dry-run=server -f k8s/conclave-search-tls/00-internal-ca.yaml`
Expected: all three resources print with `(server dry run)` and no errors.

- [ ] **Step 3: Apply for real**

Run: `kubectl apply -f k8s/conclave-search-tls/00-internal-ca.yaml`
Expected: `issuer.cert-manager.io/internal-ip-ca-bootstrap created`,
`certificate.cert-manager.io/internal-ip-ca-root created`,
`clusterissuer.cert-manager.io/internal-ip-ca-issuer created`.

- [ ] **Step 4: Verify the certificate issued and the issuer is ready**

Run: `kubectl get certificate internal-ip-ca-root -n cert-manager`
Expected: `READY` column shows `True` within ~30 seconds (self-signed
issuance is fast — if it doesn't go ready, run
`kubectl describe certificate internal-ip-ca-root -n cert-manager` and
`kubectl describe issuer internal-ip-ca-bootstrap -n cert-manager` to see
why before proceeding).

Run: `kubectl get clusterissuer internal-ip-ca-issuer`
Expected: `READY` column shows `True`.

- [ ] **Step 5: Verify the root cert's key algorithm is genuinely P-256**

Run:
```bash
kubectl get secret internal-ip-ca-root -n cert-manager -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/internal-ip-ca-root.crt
openssl x509 -in /tmp/internal-ip-ca-root.crt -text -noout | grep -A2 "Public Key Algorithm"
```
Expected output contains `id-ecPublicKey` and `NIST CURVE: P-256` (or
`ASN1 OID: prime256v1`, the OpenSSL name for the same curve) — NOT
`secp384r1`/P-384. If it shows P-384, the `Certificate` spec in Step 1 was
wrong; fix and re-apply before continuing to any later task.

- [ ] **Step 6: Commit**

```bash
git add k8s/conclave-search-tls/00-internal-ca.yaml
git commit -m "feat(k8s): internal CA for conclave-search's IP-SAN certificates"
```

---

### Task 2: SearXNG deployment with TLS-terminating front

**Files:**
- Create: `k8s/conclave-search-tls/10-searxng.yaml`

**Interfaces:**
- Consumes: `internal-ip-ca-issuer` (Task 1).
- Produces: SearXNG reachable at a pinned ClusterIP on port 443, with a
  cert-manager-issued certificate carrying that IP as an `iPAddress` SAN.
  This task's chosen pinned IP is referenced by Task 5's interop test
  invocation.

**Design decision this task makes**: same-pod sidecar vs. a separate front
pod. **Use a separate front pod** (one `nginx` `Deployment` proxying over
the cluster network to SearXNG's own plain-HTTP `Service`, mirroring
exactly the pattern Task 3 uses for `beagle-core`) rather than a same-pod
sidecar. Reason: a sidecar's crash-loop can take the whole pod (including
SearXNG's own healthy container) down with it via shared pod lifecycle;
a separate front pod isolates that failure domain, at the cost of one
extra network hop within the cluster, which is negligible here. This also
keeps this task's manifest structurally identical to Task 3's, which is
worth more than the small resource savings of colocating.

- [ ] **Step 1: Confirm a free ClusterIP for SearXNG's own plain-HTTP service and for its HTTPS front**

Run: `kubectl get svc -A -o jsonpath='{range .items[*]}{.spec.clusterIP}{"\n"}{end}' | sort -u | grep "10\.96\.250\."`
Expected: no output (both `10.96.250.10` and `10.96.250.20` are free). If
either address IS listed, pick a different unused address in the
`10.96.0.0/16` range instead and use that everywhere below — do not
proceed with a colliding IP.

- [ ] **Step 2: Write the manifest**

```yaml
# k8s/conclave-search-tls/10-searxng.yaml
#
# SearXNG, for conclave-search's URL-discovery stage. Two Services: one
# plain-HTTP internal-only ClusterIP that only the front pod talks to, and
# one pinned-ClusterIP HTTPS front that conclave-search's tls_connect
# actually reaches.
apiVersion: apps/v1
kind: Deployment
metadata:
  name: searxng
  namespace: beagle
  labels:
    app: searxng
spec:
  replicas: 1
  selector:
    matchLabels:
      app: searxng
  template:
    metadata:
      labels:
        app: searxng
    spec:
      containers:
        - name: searxng
          image: docker.io/searxng/searxng:latest
          ports:
            - containerPort: 8080
          env:
            - name: SEARXNG_BASE_URL
              value: "http://searxng.beagle.svc.cluster.local/"
          readinessProbe:
            httpGet:
              path: /healthz
              port: 8080
            initialDelaySeconds: 5
            periodSeconds: 10
---
apiVersion: v1
kind: Service
metadata:
  name: searxng
  namespace: beagle
spec:
  selector:
    app: searxng
  ports:
    - name: http
      port: 80
      targetPort: 8080
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: searxng-https-tls
  namespace: beagle
spec:
  secretName: searxng-https-tls
  privateKey:
    algorithm: ECDSA
    size: 256
  ipAddresses:
    - 10.96.250.10
  issuerRef:
    name: internal-ip-ca-issuer
    kind: ClusterIssuer
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: searxng-https-front-nginx-conf
  namespace: beagle
data:
  default.conf: |
    server {
      listen 8443 ssl;
      ssl_certificate     /etc/nginx-tls/tls.crt;
      ssl_certificate_key /etc/nginx-tls/tls.key;
      location / {
        proxy_pass http://searxng.beagle.svc.cluster.local:80;
        proxy_set_header Host $host;
      }
    }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: searxng-https-front
  namespace: beagle
  labels:
    app: searxng-https-front
spec:
  replicas: 1
  selector:
    matchLabels:
      app: searxng-https-front
  template:
    metadata:
      labels:
        app: searxng-https-front
    spec:
      containers:
        - name: nginx
          image: docker.io/library/nginx:stable
          ports:
            - containerPort: 8443
          volumeMounts:
            - name: tls
              mountPath: /etc/nginx-tls
              readOnly: true
            - name: conf
              mountPath: /etc/nginx/conf.d
              readOnly: true
      volumes:
        - name: tls
          secret:
            secretName: searxng-https-tls
        - name: conf
          configMap:
            name: searxng-https-front-nginx-conf
---
apiVersion: v1
kind: Service
metadata:
  name: searxng-https
  namespace: beagle
spec:
  clusterIP: 10.96.250.10
  selector:
    app: searxng-https-front
  ports:
    - name: https
      port: 443
      targetPort: 8443
```

- [ ] **Step 3: Dry-run verify**

Run: `kubectl apply --dry-run=server -f k8s/conclave-search-tls/10-searxng.yaml`
Expected: all six resources print with `(server dry run)` and no errors.

- [ ] **Step 4: Apply for real**

Run: `kubectl apply -f k8s/conclave-search-tls/10-searxng.yaml`

- [ ] **Step 5: Verify pods come up**

Run: `kubectl get pods -n beagle -l app=searxng` and
`kubectl get pods -n beagle -l app=searxng-https-front`
Expected: both show `1/1 Running` within ~60 seconds. If `searxng`'s pod
doesn't reach Ready, check `kubectl logs -n beagle -l app=searxng` — the
public SearXNG image may need `SEARXNG_SECRET_KEY` or similar env vars in
newer versions; add whatever the image's own README/logs indicate is
missing, this is a real config detail that may need adjusting from this
plan's minimal starting manifest.

- [ ] **Step 6: Verify the certificate issued with the correct IP SAN**

Run: `kubectl get certificate searxng-https-tls -n beagle`
Expected: `READY` shows `True`.

Run:
```bash
kubectl get secret searxng-https-tls -n beagle -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -text -noout | grep -A1 "Subject Alternative Name"
```
Expected output contains `IP Address:10.96.250.10`.

- [ ] **Step 7: Verify the HTTPS front actually terminates TLS and chains to the internal CA**

This requires a shell inside the cluster's pod network — this session's
own shell does NOT have direct network access to ClusterIPs (confirmed:
a direct TCP connect to an existing ClusterIP from this session's shell
times out). Use a temporary debug pod:

```bash
kubectl run tls-verify-probe --rm -it --restart=Never --image=alpine/openssl -n beagle -- \
  s_client -connect 10.96.250.10:443 -CAfile /dev/stdin <<< "$(kubectl get secret internal-ip-ca-root -n cert-manager -o jsonpath='{.data.tls\.crt}' | base64 -d)"
```

Expected output includes `Verify return code: 0 (ok)`. If the debug pod
image `alpine/openssl` isn't pullable in this cluster, substitute any
small image with `openssl` installed that's already known to pull cleanly
here (check `k8s/` for one already in use elsewhere) — document whichever
image actually worked in this step's own commit message or a comment in
the manifest.

- [ ] **Step 8: Commit**

```bash
git add k8s/conclave-search-tls/10-searxng.yaml
git commit -m "feat(k8s): deploy SearXNG behind an internal-CA HTTPS front"
```

---

### Task 3: `beagle-core` HTTPS front

**Files:**
- Create: `k8s/conclave-search-tls/20-beagle-core-https-front.yaml`

**Interfaces:**
- Consumes: `internal-ip-ca-issuer` (Task 1); the EXISTING `beagle-core`
  Service in the `beagle` namespace (read-only — proxied to, never
  modified). Confirm its current address before writing this task's
  manifest: `kubectl get svc beagle-core -n beagle -o jsonpath='{.spec.clusterIP}:{.spec.ports[0].port}'`
  — the spec's `10.96.67.112:8080` was measured earlier in this project;
  re-confirm it's still accurate right now, since ClusterIPs can change if
  a Service is ever recreated (not just restarted).
- Produces: `beagle-core`'s GraphRAG API reachable over HTTPS at a second
  pinned ClusterIP. This task's chosen pinned IP is referenced by Task 5's
  interop test invocation.

- [ ] **Step 1: Confirm the free ClusterIP for this front (chosen in Task 2 Step 1 as `10.96.250.20`; re-confirm it's still free if any time has passed since Task 2)**

Run: `kubectl get svc -A -o jsonpath='{range .items[*]}{.spec.clusterIP}{"\n"}{end}' | sort -u | grep "10\.96\.250\.20"`
Expected: no output.

- [ ] **Step 2: Confirm the existing `beagle-core` Service's address**

Run: `kubectl get svc beagle-core -n beagle -o jsonpath='{.spec.clusterIP}:{.spec.ports[0].port}{"\n"}'`
Expected: `10.96.67.112:8080` (per this project's own prior measurement).
If it differs, use whatever this command actually reports in the `nginx`
`proxy_pass` directive below instead of the value shown in this plan.

- [ ] **Step 3: Write the manifest**

```yaml
# k8s/conclave-search-tls/20-beagle-core-https-front.yaml
#
# A wholly separate HTTPS front for the EXISTING, LIVE beagle-core
# Service -- proxies to it over the cluster network, never modifies it.
# beagle-core keeps serving plain HTTP to its existing consumers exactly
# as before; this is just another client of it.
apiVersion: v1
kind: ConfigMap
metadata:
  name: beagle-core-https-front-nginx-conf
  namespace: beagle
data:
  default.conf: |
    server {
      listen 8443 ssl;
      ssl_certificate     /etc/nginx-tls/tls.crt;
      ssl_certificate_key /etc/nginx-tls/tls.key;
      location / {
        proxy_pass http://beagle-core.beagle.svc.cluster.local:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Beagle-Consumer $http_x_beagle_consumer;
      }
    }
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: beagle-core-https-tls
  namespace: beagle
spec:
  secretName: beagle-core-https-tls
  privateKey:
    algorithm: ECDSA
    size: 256
  ipAddresses:
    - 10.96.250.20
  issuerRef:
    name: internal-ip-ca-issuer
    kind: ClusterIssuer
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: beagle-core-https-front
  namespace: beagle
  labels:
    app: beagle-core-https-front
spec:
  replicas: 1
  selector:
    matchLabels:
      app: beagle-core-https-front
  template:
    metadata:
      labels:
        app: beagle-core-https-front
    spec:
      containers:
        - name: nginx
          image: docker.io/library/nginx:stable
          ports:
            - containerPort: 8443
          volumeMounts:
            - name: tls
              mountPath: /etc/nginx-tls
              readOnly: true
            - name: conf
              mountPath: /etc/nginx/conf.d
              readOnly: true
      volumes:
        - name: tls
          secret:
            secretName: beagle-core-https-tls
        - name: conf
          configMap:
            name: beagle-core-https-front-nginx-conf
---
apiVersion: v1
kind: Service
metadata:
  name: beagle-core-https
  namespace: beagle
spec:
  clusterIP: 10.96.250.20
  selector:
    app: beagle-core-https-front
  ports:
    - name: https
      port: 443
      targetPort: 8443
```

Note: the `X-Beagle-Consumer` header is explicitly forwarded in the
`proxy_pass` block above — `beagle-core`'s real route handler requires it
for identity/rate-limiting on the GraphRAG endpoints (a fact measured
during `conclave-search`'s own Task 5), and `nginx` does not forward
custom headers by default beyond what `proxy_set_header` explicitly names.

- [ ] **Step 4: Dry-run verify**

Run: `kubectl apply --dry-run=server -f k8s/conclave-search-tls/20-beagle-core-https-front.yaml`
Expected: all four resources print with `(server dry run)` and no errors.

- [ ] **Step 5: Apply for real**

Run: `kubectl apply -f k8s/conclave-search-tls/20-beagle-core-https-front.yaml`

- [ ] **Step 6: Verify the pod comes up and the existing beagle-core is untouched**

Run: `kubectl get pods -n beagle -l app=beagle-core-https-front`
Expected: `1/1 Running` within ~30 seconds.

Run: `kubectl get svc beagle-core -n beagle -o jsonpath='{.spec.clusterIP}:{.spec.ports[0].port}{"\n"}'`
Expected: identical output to Step 2 — confirms this task made no change
to the existing Service.

- [ ] **Step 7: Verify the certificate's IP SAN**

Run:
```bash
kubectl get secret beagle-core-https-tls -n beagle -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -text -noout | grep -A1 "Subject Alternative Name"
```
Expected output contains `IP Address:10.96.250.20`.

- [ ] **Step 8: Verify TLS termination and chain validation**

Same debug-pod pattern as Task 2 Step 7, pointed at `10.96.250.20`:

```bash
kubectl run tls-verify-probe-2 --rm -it --restart=Never --image=alpine/openssl -n beagle -- \
  s_client -connect 10.96.250.20:443 -CAfile /dev/stdin <<< "$(kubectl get secret internal-ip-ca-root -n cert-manager -o jsonpath='{.data.tls\.crt}' | base64 -d)"
```
Expected: `Verify return code: 0 (ok)`.

- [ ] **Step 9: Verify an actual proxied request reaches beagle-core**

From the same debug pod session (or a fresh one), issue a real HTTPS
request through the front and confirm it gets a response from
`beagle-core` itself, not a proxy error:

```bash
kubectl run tls-verify-probe-3 --rm -it --restart=Never --image=curlimages/curl -n beagle -- \
  curl -sk -o /dev/null -w '%{http_code}\n' https://10.96.250.20/health
```
Expected: an HTTP status code `beagle-core` itself would plausibly return
for whatever path you probe (check `beagle-core`'s own route source for a
real lightweight endpoint to hit here, e.g. a health-check route, rather
than guessing `/health` blindly) — the important signal is that it's
NOT a connection-refused/502/504 from `nginx` itself, which would mean the
proxy can't reach `beagle-core`.

- [ ] **Step 10: Commit**

```bash
git add k8s/conclave-search-tls/20-beagle-core-https-front.yaml
git commit -m "feat(k8s): TLS front for beagle-core, existing service untouched"
```

---

### Task 4: Extract the internal CA root for future consumption

**Files:**
- Create: `k8s/conclave-search-tls/README.md`
- Create: `k8s/conclave-search-tls/extract-ca-root.sh`

**Interfaces:**
- Consumes: the `internal-ip-ca-root` Secret (Task 1).
- Produces: a documented, re-runnable extraction path that a future
  `conclave-search` container-image build step can call — this task does
  NOT build or modify any container image, since none exists yet for
  `conclave-search`'s runtime (out of scope per the spec).

- [ ] **Step 1: Write the extraction script**

```bash
#!/usr/bin/env bash
# k8s/conclave-search-tls/extract-ca-root.sh
#
# Prints the internal IP-SAN CA's root certificate (PEM) to stdout.
# A future conclave-search container-image build step should pipe this
# into its own image's trust bundle, e.g.:
#
#   bash extract-ca-root.sh > internal-ip-ca-root.crt
#   # then, in that image's Dockerfile:
#   #   COPY internal-ip-ca-root.crt /usr/local/share/ca-certificates/
#   #   RUN update-ca-certificates
#
# conclave-search's trust_store_load() (stdlib/x509/trust_store.sio in the
# sibling sounio repo) reads a single hardcoded path,
# /etc/ssl/certs/ca-certificates.crt, with no runtime parameterization --
# so the CA root MUST be present in that exact file inside whatever
# container actually runs the conclave-search binary. There is no such
# container/deploy pipeline yet; this script is what that future pipeline
# should call.
set -euo pipefail
kubectl get secret internal-ip-ca-root -n cert-manager -o jsonpath='{.data.tls\.crt}' | base64 -d
```

- [ ] **Step 2: Verify it runs and produces a valid certificate**

Run: `bash k8s/conclave-search-tls/extract-ca-root.sh | openssl x509 -text -noout | head -5`
Expected: valid X.509 certificate output (no `unable to load certificate`
error), showing `Issuer: CN = conclave-search-internal-ca` and
`Subject: CN = conclave-search-internal-ca` (self-signed root — issuer
and subject match).

- [ ] **Step 3: Write the README**

```markdown
# conclave-search TLS backends

This directory's manifests make SearXNG and beagle-core reachable over
HTTPS at stable, literal IPv4 addresses that conclave-search's TLS stack
(dotted-decimal-IP-only host, IP-SAN certificate checking, single
hardcoded system trust bundle) can validate. See
`docs/superpowers/specs/2026-08-26-conclave-search-tls-backends-design.md`
for the full design.

## What's here

- `00-internal-ca.yaml` -- a self-signed internal CA (ECDSA P-256 root --
  deliberately not P-384, see the spec for why), exposed cluster-wide as
  `ClusterIssuer/internal-ip-ca-issuer`.
- `10-searxng.yaml` -- SearXNG, deployed behind its own HTTPS front at
  `10.96.250.10:443`.
- `20-beagle-core-https-front.yaml` -- a separate HTTPS front for the
  EXISTING beagle-core service (never modifies it), at
  `10.96.250.20:443`.
- `extract-ca-root.sh` -- prints the internal CA's root certificate PEM to
  stdout. Run this, then feed the output into whatever future
  container-image build produces conclave-search's runtime image, so its
  `/etc/ssl/certs/ca-certificates.crt` trusts this CA.

## Pinned addresses

| What | Address |
|---|---|
| SearXNG HTTPS front | `10.96.250.10:443` |
| beagle-core HTTPS front | `10.96.250.20:443` |

These are the two IPv4 literals conclave-search's `argv[1]`/`argv[2]`
should be pointed at, once it's actually deployed somewhere that can
reach the cluster network and trusts this CA.

## No deploy pipeline yet

There is currently no container-image build pipeline for
`conclave-search`'s own binary. Wiring it into Conclave's chat tool (a
separate, later spec) is where that pipeline will need to be created --
this directory only prepares the two backends and the CA root it will
need to trust.
```

- [ ] **Step 4: Commit**

```bash
git add k8s/conclave-search-tls/README.md k8s/conclave-search-tls/extract-ca-root.sh
git commit -m "docs(k8s): document conclave-search TLS backends, add CA-root extraction script"
```

---

### Task 5: End-to-end verification with conclave-search's own live interop tests

**Files:**
- Modify: none in this repo (verification only).
- Reference: `tests/interop/discovery_searxng_live.sio` and
  `tests/interop/memory_context_beagle_core_live.sio` in the separate
  `Sounio-lang/conclave-search` repository, cloned locally at
  `/home/devsounio/conclave-search`.

**Interfaces:**
- Consumes: the two pinned IPs from Tasks 2 and 3
  (`10.96.250.10`/`10.96.250.20`), the extracted CA root from Task 4.
- Produces: a real pass/fail signal that these two backends are genuinely
  usable by `conclave-search`, closing out this plan.

- [ ] **Step 1: Determine how to run something with real cluster-network reachability**

This session's own shell does NOT have direct network access to
ClusterIPs (confirmed during Tasks 2/3's own verification steps — a
direct TCP connect from this shell times out; `kubectl run`-based debug
pods were used instead because THEY run inside the cluster's pod
network). `conclave-search`'s own interop tests need a full Sounio
toolchain (`souc` + `stdlib`) AND that same in-cluster network
reachability — a plain `alpine`/`curlimages` debug pod has neither.

Check whether the existing `sounio-workspace` Kubernetes pod (documented
in this project's own root `CLAUDE.md` under "Workspace (K8s)") already
has both: it's a real K8s pod (so on the cluster's pod network by
construction) and is the promoted development workspace for the `sounio`
repo (so it should already have a built `souc` toolchain). Confirm via:

```bash
kubectl get pods -A -o wide | grep sounio-workspace
```

If found, use `kubectl exec` into that pod for the rest of this task
(fastest path — no new infrastructure needed). If that pod either isn't
reachable, doesn't have network access to the `beagle` namespace's
ClusterIPs (namespaces can be network-policy-isolated — verify, don't
assume), or doesn't have both `sounio` and `conclave-search` checked out
with a working toolchain, fall back to a purpose-built temporary pod:
build a minimal image (or use an existing generic dev image already known
to work in this cluster) that clones both repos fresh and builds the
toolchain the same way this project's own `scripts/run_tests.sh`
convention does. Document in this task's own commit message /
`final-report.md` (see Step 5) which path was actually used and why,
since this determines how a future automated version of this
verification would need to be wired.

- [ ] **Step 2: Get the internal CA root into that environment's trust bundle**

Whatever environment Step 1 settled on, it needs the CA root from Task 4
appended to its own `/etc/ssl/certs/ca-certificates.crt` (the same fixed
path `trust_store_load()` reads) — this is a manual, one-off step for
this verification task, distinct from Task 4's future-pipeline artifact:

```bash
bash /home/devsounio/beagle/k8s/conclave-search-tls/extract-ca-root.sh > /tmp/internal-ip-ca-root.crt
# copy /tmp/internal-ip-ca-root.crt into the chosen environment, then inside it:
cat /tmp/internal-ip-ca-root.crt >> /etc/ssl/certs/ca-certificates.crt
```

(If the environment's base image uses `update-ca-certificates` instead of
a directly-appendable bundle file, use that mechanism instead — whichever
actually results in `trust_store_load()`'s exact hardcoded path containing
this CA's cert. Verify with `grep -c "conclave-search-internal-ca"
/etc/ssl/certs/ca-certificates.crt` showing a nonzero count, or the
equivalent check for whatever mechanism was actually used.)

- [ ] **Step 3: Run the SearXNG discovery interop test**

Inside the chosen environment, with `SOUNIO_STDLIB_PATH` pointed at a
built `sounio` checkout's `stdlib/` and `souc` invoked by full path,
matching this project's own established convention throughout
`conclave-search`'s own test suite. The known-working checkout as of this
plan's writing is
`/home/devsounio/sounio/.claude/worktrees/sounio-tls-on-madaros` (the
worktree that built and shipped `conclave-search`'s TLS/X.509 dependency)
— use that if it still exists in the chosen environment, or whatever
current checkout of the `sounio` repo has an equivalent built `bin/souc`
and `stdlib/` if it doesn't (that worktree is git-ignored scratch and may
have been cleaned up by the time this task runs):

```bash
SOUNIO_STDLIB_PATH=/home/devsounio/sounio/.claude/worktrees/sounio-tls-on-madaros/stdlib \
  /home/devsounio/sounio/.claude/worktrees/sounio-tls-on-madaros/bin/souc run \
  /home/devsounio/conclave-search/tests/interop/discovery_searxng_live.sio \
  10.96.250.10
```

(adjust the exact invocation to match whatever real argument convention
that specific test file's own header comment documents — read it first,
this plan does not repeat its exact CLI contract since it may have
evolved since it was written).

Expected: the test's own printed output reports genuine SearXNG results
parsed from a real response, not a connection/TLS/timeout failure. If it
fails, capture the exact error and diagnose whether it's this plan's
infrastructure (wrong IP, cert not trusted, `nginx` misconfigured) or
something inside `conclave-search`/`sounio` itself (out of this plan's
scope to fix, but document precisely which).

- [ ] **Step 4: Run the beagle-core memory-context interop test**

Same pattern, pointed at `10.96.250.20`:

```bash
SOUNIO_STDLIB_PATH=/home/devsounio/sounio/.claude/worktrees/sounio-tls-on-madaros/stdlib \
  /home/devsounio/sounio/.claude/worktrees/sounio-tls-on-madaros/bin/souc run \
  /home/devsounio/conclave-search/tests/interop/memory_context_beagle_core_live.sio \
  10.96.250.20
```

Expected: the test's own printed output reports genuine memory-context
data from `beagle-core`, not a connection/TLS/timeout/authentication
failure.

- [ ] **Step 5: Write the final report**

Document, in a new file `k8s/conclave-search-tls/verification-report.md`
in this repo: which environment was used for Step 1 and why, the exact
commands run for Steps 2-4, and the exact pass/fail outcome of both
interop tests with their real output (not a paraphrase) pasted in. If
either test failed for a reason outside this plan's own infrastructure
(a `conclave-search`/`sounio`-side defect), say so explicitly and do NOT
mark this plan's own deliverable as failed on that account — this plan's
job was making the backends reachable and trusted, which Steps 3/4's TLS
handshake succeeding (even if a later stage of either test then fails for
an unrelated reason) already proves.

- [ ] **Step 6: Commit**

```bash
git add k8s/conclave-search-tls/verification-report.md
git commit -m "docs(k8s): conclave-search TLS backend end-to-end verification report"
```

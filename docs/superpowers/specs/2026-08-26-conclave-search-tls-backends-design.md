# conclave-search TLS Backends: SearXNG + beagle-core HTTPS Front

## Background

`Sounio-lang/conclave-search` (a separate repository) is a Sounio-native
epistemic web-search CLI, fully built and tested. It has two upstream
dependencies it reaches over TLS:

- **SearXNG** — for URL discovery. Not deployed anywhere in this cluster
  yet.
- **`beagle-core`** — for memory-graph enrichment and gated write-back, via
  its `GraphRAG` HTTP API. Already deployed and live, but only reachable
  over **plain HTTP** on its ClusterIP (`10.96.67.112:8080`).

conclave-search's TLS stack (`stdlib/tls/client.sio` in the sibling `sounio`
repo) has two hard constraints, both already measured and documented, not
new to this design:

1. `tls_connect(host, host_len, port, trust_store, now_unix)` requires
   `host` to be **dotted-decimal IPv4 text** — there is no DNS resolver
   inside the TLS stack itself (conclave-search's own Task 9 added a
   DNS-over-HTTPS resolver, but that's a separate, outward-facing lookup;
   it doesn't change what `tls_connect` itself accepts).
2. That same `host` text is what `x509_verify_chain` checks the server
   certificate's SAN against. So whatever we put behind `tls_connect` must
   present a certificate whose SAN contains that **exact literal IPv4
   address** as an `iPAddress` entry (a gap in this checking was recently
   fixed — `x509_verify_hostname` now matches `iPAddress` SANs, not just
   `dNSName` — but the certificate must still actually carry one).
3. `trust_store_load()` (`stdlib/x509/trust_store.sio`) reads a single,
   hardcoded system CA bundle path (`/etc/ssl/certs/ca-certificates.crt`)
   with no parameterization — there is no way to hand it a custom trust
   anchor at runtime. Whatever CA signs the certificates in (2) must be
   present in that file, inside whatever container actually runs the
   `conclave-search` binary.

No public CA will issue a certificate for a private RFC 1918 ClusterIP.
This design builds a small internal CA and issues IP-SAN certificates from
it, rather than trying to make either backend reachable via a public,
domain-validated certificate.

**This spec is deliberately scoped to making the two backends
TLS-reachable with a certificate conclave-search can validate.** Wiring
conclave-search into Conclave's actual chat tool (the Node.js side,
`beagle/apps/gpu-chat/server/src/tools/`) is a separate, later spec —
this one is a precondition for it, not part of it.

## Goals

- SearXNG is deployed and reachable over HTTPS at a stable, literal IPv4
  address, with a certificate `conclave-search`'s `tls_connect` will
  accept.
- `beagle-core`'s existing GraphRAG API is reachable over HTTPS at a
  stable, literal IPv4 address, likewise — **without modifying the live
  `beagle-core` deployment itself**.
- `conclave-search`'s own trust store (wherever its binary actually runs)
  trusts the CA that signed both certificates.
- Both fronts are verified working with a real TLS client before this is
  considered done — specifically, by running conclave-search's own
  previously-unexecuted live interop tests
  (`tests/interop/discovery_searxng_live.sio`,
  `tests/interop/memory_context_beagle_core_live.sio`) against them for
  real.

## Non-goals

- Wiring conclave-search into Conclave's chat tool (separate spec).
- Public/internet-facing exposure of either service — both are
  cluster-internal only.
- Changing anything about the live `beagle-core` deployment's existing
  plain-HTTP service or its consumers.
- A general-purpose internal CA/PKI system for the whole cluster — this CA
  exists to serve exactly these two certificates; if a broader need for
  internal IP-SAN certs shows up later, it can be extended, but that's not
  scoped here.

## Architecture

### 1. Internal CA

A new, separate `cert-manager` `ClusterIssuer` — self-signed, not ACME —
distinct from the existing `letsencrypt-production`/`letsencrypt-staging`
issuers in `beagle/k8s/cert-manager.yaml` (those are for the public
`agourakis.com` domain and cannot issue IP-SAN certs for private
addresses).

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: internal-ip-ca-issuer
spec:
  ca:
    secretName: internal-ip-ca-root
---
# A self-signed root, generated once (Certificate + a bootstrapping
# self-signed Issuer), whose resulting secret internal-ip-ca-issuer
# reads from above. Standard cert-manager "own your own CA" pattern.
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: internal-ip-ca-bootstrap
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: internal-ip-ca-root
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
```

Note the private key algorithm is deliberately **ECDSA P-256** (not
P-384/SHA-384) — `conclave-search`'s upstream TLS stack has a known,
documented gap (D15 in the sibling `sounio` repo) where
`ecdsa-with-SHA384`-signed chains fail closed. Issuing from a P-256 root
avoids hitting that gap entirely, rather than working around it.

### 2. SearXNG deployment

New `Deployment` + `Service` in the `beagle` namespace. The Service pins
an explicit ClusterIP (`spec.clusterIP: 10.96.x.x`, a literal chosen from
the cluster's service CIDR, not auto-assigned) so it's a stable literal
conclave-search's config can hardcode.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: searxng
  namespace: beagle
spec:
  clusterIP: 10.96.250.10   # pin explicitly; confirm free in-cluster first
  selector:
    app: searxng
  ports:
    - name: https
      port: 443
      targetPort: 8443
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: searxng-tls
  namespace: beagle
spec:
  secretName: searxng-tls
  ipAddresses:
    - 10.96.250.10
  issuerRef:
    name: internal-ip-ca-issuer
    kind: ClusterIssuer
```

Pod spec: SearXNG's own container (standard SearXNG image, listening on
its default `8080`) plus an `nginx` sidecar listening on `8443`, terminating
TLS with the `searxng-tls` secret, reverse-proxying to `localhost:8080`.

### 3. `beagle-core` HTTPS front

A **new, separate** Service + `nginx` deployment — not a change to the
existing `beagle-core` Service or Deployment — that reverse-proxies to the
existing `beagle-core` ClusterIP (`10.96.67.112:8080`) over the cluster
network.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: beagle-core-https
  namespace: beagle
spec:
  clusterIP: 10.96.250.11   # pin explicitly; confirm free in-cluster first
  selector:
    app: beagle-core-https-front
  ports:
    - name: https
      port: 443
      targetPort: 8443
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: beagle-core-https-tls
  namespace: beagle
spec:
  secretName: beagle-core-https-tls
  ipAddresses:
    - 10.96.250.11
  issuerRef:
    name: internal-ip-ca-issuer
    kind: ClusterIssuer
```

Pod spec: a single `nginx` container, mounting `beagle-core-https-tls`,
terminating TLS on `8443`, `proxy_pass http://beagle-core.beagle.svc.cluster.local:8080;`.
This keeps the live `beagle-core` deployment completely untouched — it
keeps serving plain HTTP to its existing consumers exactly as today, and
this new front is just another client of it.

### 4. Trust anchor for `conclave-search`'s runtime

Wherever the `conclave-search` binary actually runs (its own container
image, once a deploy pipeline exists for it — out of scope here, but this
step must happen in that image's build), append `internal-ip-ca-root`'s CA
certificate (extracted from the `internal-ip-ca-root` Secret) to
`/etc/ssl/certs/ca-certificates.crt` inside that image, e.g. via a build
step:

```dockerfile
COPY internal-ip-ca-root.crt /usr/local/share/ca-certificates/
RUN update-ca-certificates
```

This is the ONLY change `conclave-search`'s own runtime needs — no code
change, since `trust_store_load()` already reads the system bundle at that
exact path.

## Data flow

1. Apply the `ClusterIssuer`/bootstrap `Issuer`/root `Certificate` (one-time
   setup).
2. Apply SearXNG's `Deployment`/`Service`/`Certificate`.
3. Apply the `beagle-core-https` front's `Deployment`/`Service`/`Certificate`.
4. Extract `internal-ip-ca-root`'s CA cert; stage it for whatever build
   process produces `conclave-search`'s runtime container (tracked as a
   follow-up, since that pipeline doesn't exist yet — see Non-goals).
5. Verify: from a pod inside the cluster,
   `openssl s_client -connect 10.96.250.10:443` and
   `openssl s_client -connect 10.96.250.11:443`, each showing a chain that
   validates against the internal CA root.
6. Verify for real with conclave-search itself: run
   `tests/interop/discovery_searxng_live.sio` and
   `tests/interop/memory_context_beagle_core_live.sio` (already written,
   never executed against a real target) pointed at `10.96.250.10` and
   `10.96.250.11` respectively, from an environment that has the internal
   CA root in its trust bundle and can reach the cluster network.

## Error handling

- `cert-manager` issuance failure → the `Certificate` resource stays
  `Ready: False`, the sidecar/front pod's volume mount for the secret
  fails, the pod doesn't start. Visible via `kubectl get certificate` /
  `kubectl describe pod`, not silent.
- Trust anchor not yet present wherever `conclave-search` runs →
  `trust_store_load()`/`x509_verify_chain` fails closed, and
  `discover_candidates`/`fetch_memory_context` already handle that as an
  `ok=false` fail-soft degradation (proven behavior, no new code path).
- SearXNG/`beagle-core` HTTPS front pod crash-loops → the plain-HTTP
  services underneath are completely unaffected (SearXNG's own container
  keeps running independently of its sidecar's health in a crash-loop
  scenario only if using a sidecar container within the same pod is
  avoided for this reason — **note for implementation**: if the SearXNG
  sidecar's own restarts risk taking the whole pod down with it, consider
  the same "separate front Service" pattern used for `beagle-core` instead
  of a same-pod sidecar, trading one extra network hop for full
  isolation. This is a small decision to make during implementation, not
  a blocking one for this spec.

## Testing strategy

- `kubectl apply --dry-run=server` on every new manifest before applying
  for real.
- Confirm both pinned ClusterIPs are actually free in the cluster's
  service CIDR before hardcoding them (`kubectl get svc -A -o
  jsonpath='{.items[*].spec.clusterIP}'` and check for collisions).
- `openssl s_client` verification (Data flow step 5) as the first real
  signal.
- conclave-search's own live interop tests (Data flow step 6) as the real
  acceptance criterion — these were written during conclave-search's own
  Task 5 specifically for this moment and have never had a real target
  until now.
- No new tests need to be written in `conclave-search` itself — this spec
  only makes its existing, already-written interop tests finally
  executable for real.

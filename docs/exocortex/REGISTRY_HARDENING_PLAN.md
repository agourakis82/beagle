# Registry Hardening Plan

**Registry**: `192.168.3.207:5003` (host daemon on `5860-proxmox`)
**Status**: plain HTTP, no auth, `--insecure-registry` in every kaniko build job
**Date authored**: 2026-06-23
**Applies to**: all kaniko build jobs + every pod that pulls from this registry

---

## Scope and blast-radius map

Before touching anything, understand what breaks if the registry becomes
unreachable or its TLS cert is untrusted:

| Workload | Namespace | Image tag style |
|---|---|---|
| `beagle-core-exocortex` | `beagle` | mutable tag |
| `beagle-mcp-server` | `beagle` | mutable tag |
| `beagle-memory-engine` | `beagle-memory-lab` | mutable tag |
| `beagle-workspace-agent` | `beagle`, `sounio-workspace-habitat` | mutable tag |
| `project-cockpit` | `beagle` | mutable tag |
| `physiome` | `beagle` | mutable tag |
| `moshi-server` | `beagle` | mutable tag |
| `sounio-lab-*-workspace-ide-*` | `sounio-workspace`, `sounio-workspace-habitat` | stable tag |
| `sounio-lab-*-workspace-ssh-*` | `sounio-workspace`, `sounio-workspace-habitat` | stable tag |

All four cluster nodes (`t560`, `r740`, `r770`, `5860`) pull from
`192.168.3.207:5003` via `--plain-http pull` in containerd. Every node's
containerd daemon must be re-configured before TLS is enforced.

**Key constraint**: containerd v2 uses `config_path` under `cri.v1.images` for
per-registry config; the old `[plugins."io.containerd.grpc.v1.cri".registry]`
inline block is gone. Both syntaxes must be audited per-node before the
insecure flag is removed.

---

## Registry daemon — current state

The registry runs as a **host systemd service on `5860-proxmox`**
(`192.168.3.207`). It is the Docker Distribution v2 daemon bound to `:5003`
with no TLS, no authentication, and no content trust. The 10Gb service fabric
(VLAN 130, `10.30.0.0/24`) is the intended long-term home for this service edge,
but the registry currently binds on the management fabric (`192.168.3.0/24`).

Artifact: the `sounio-networking/service-fabric-10g/README.md` notes
`192.168.3.207:5003` as a "registry/artifact cache landing zone" on the service
fabric. Migration of the registry listener to `10.30.0.x` is a distinct
(later) task; this plan hardens TLS and signing without requiring that move.

---

## Threat model (what we are fixing)

1. **Plaintext push/pull** — any host on the management LAN can MITM kaniko
   pushes and inject a malicious layer.
2. **No image signing** — a pushed tag can be silently overwritten; pods pull
   whatever the registry returns for a mutable tag.
3. **Mutable tag pinning** — `stable`, `latest`, and commit-SHA tags are all
   mutable; a re-push changes what the cluster schedules.
4. **No pull-time verification** — even with signing, pods currently have no
   enforcement of the signature check.

---

## Three-pillar hardening

| Pillar | What | Primary risk |
|---|---|---|
| **A — TLS** | Front registry with cert from cluster CA; trust that CA in containerd on every node | Break all pulls if trust is wrong; wrong move = cluster-wide outage |
| **B — cosign signing** | Sign every image in kaniko build jobs; add a verification init-container before app containers | Signing failures block deploys; key management is new infra |
| **C — Digest pinning** | Replace mutable tags with `image@sha256:…` in all deployments | Image refs become stale if not refreshed after each build |

All three pillars are independent; each can be rolled back independently.
Apply them in order A → B → C. Never apply more than one node in pillar A
until the first node is confirmed healthy.

---

## Pillar A — TLS

### A0 — Prerequisites (no cluster changes yet)

1. Confirm cert-manager is installed and the `letsencrypt-production`
   ClusterIssuer is healthy:
   ```
   kubectl get clusterissuer letsencrypt-production -o jsonpath='{.status.conditions[*]}'
   ```
   If not ready, fix cert-manager before proceeding.

2. Decide on the CA strategy. Two options:

   **Option A1 — Internal CA via cert-manager** (recommended for a private
   registry on a private LAN):
   - Create a `ClusterIssuer` of type `CA` backed by a self-signed root stored
     in a Secret. cert-manager will issue and auto-rotate the registry cert.
   - The CA cert is distributed to containerd on each node (one-time manual
     step per node).
   - No public DNS or ACME required. The registry stays on `192.168.3.207:5003`
     or acquires a stable hostname like `registry.lab.sounio` on the
     `lab.sounio` zone (already served by dnsmasq on `5860`).

   **Option A2 — Let's Encrypt wildcard** (if registry gets a public
   sub-domain, e.g., `registry.agourakis.com`):
   - cert-manager issues via DNS-01/Cloudflare; works today since the
     `letsencrypt-production` ClusterIssuer already has Cloudflare config.
   - Requires the registry to be reachable on a name with a valid public cert.
   - Simpler for containerd trust (public root already trusted by all nodes).

   **Recommendation**: Option A1. The registry is purely private; exposing it
   publicly adds attack surface. Option A1 is chosen for the manifests below.

### A1 — Cluster CA bootstrap

Apply once. This creates the self-signed root CA and the cert-manager
`CA` ClusterIssuer.

```yaml
# k8s/registry-hardening/00-cluster-ca.yaml
---
# Self-signed root (bootstraps the CA key)
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-bootstrap
spec:
  selfSigned: {}

---
# Root CA certificate (stored in cert-manager namespace)
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: beagle-lab-ca
  namespace: cert-manager
spec:
  isCA: true
  commonName: beagle-lab-ca
  secretName: beagle-lab-ca-secret
  duration: 87600h   # 10 years
  renewBefore: 720h
  privateKey:
    algorithm: ECDSA
    size: 384
  issuerRef:
    name: selfsigned-bootstrap
    kind: ClusterIssuer

---
# CA-backed ClusterIssuer for all internal certs
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: beagle-lab-ca
spec:
  ca:
    secretName: beagle-lab-ca-secret
```

**Apply**:
```bash
kubectl apply -f k8s/registry-hardening/00-cluster-ca.yaml
# Wait for CA cert to be issued:
kubectl wait --for=condition=Ready certificate/beagle-lab-ca -n cert-manager --timeout=120s
```

**Rollback**: delete the ClusterIssuer and Certificate; no cluster traffic is
affected since no node trusts this CA yet.

### A2 — Registry TLS certificate

Issue a cert for the registry hostname. Use `registry.lab.sounio` (add an A
record to the dnsmasq config on `5860` pointing to `192.168.3.207`), or keep
the IP and use `ipAddresses` in the SAN.

```yaml
# k8s/registry-hardening/01-registry-cert.yaml
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: registry-tls
  namespace: cert-manager
spec:
  secretName: registry-tls-secret
  duration: 8760h   # 1 year
  renewBefore: 720h
  issuerRef:
    name: beagle-lab-ca
    kind: ClusterIssuer
  commonName: registry.lab.sounio
  dnsNames:
    - registry.lab.sounio
  ipAddresses:
    - 192.168.3.207
  privateKey:
    algorithm: ECDSA
    size: 256
```

**Apply** (after A1 is healthy):
```bash
kubectl apply -f k8s/registry-hardening/01-registry-cert.yaml
kubectl wait --for=condition=Ready certificate/registry-tls -n cert-manager --timeout=120s
# Extract the issued cert and key:
kubectl get secret registry-tls-secret -n cert-manager \
  -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/registry.crt
kubectl get secret registry-tls-secret -n cert-manager \
  -o jsonpath='{.data.tls\.key}' | base64 -d > /tmp/registry.key
kubectl get secret registry-tls-secret -n cert-manager \
  -o jsonpath='{.data.ca\.crt}' | base64 -d > /tmp/lab-ca.crt
```

**Rollback**: delete the Certificate; the registry daemon is not touched yet.

### A3 — Configure the registry daemon on 5860

The registry daemon is a host service. SSH to `5860-proxmox` and update its
config. The Docker Distribution config file is typically at
`/etc/docker/registry/config.yml`.

**Before editing, back up the existing config**:
```bash
ssh 5860-proxmox "cp /etc/docker/registry/config.yml /etc/docker/registry/config.yml.bak.$(date +%Y%m%d)"
```

Minimum TLS block to add/replace in `config.yml`:
```yaml
http:
  addr: :5003
  tls:
    certificate: /etc/docker/registry/tls/registry.crt
    key:         /etc/docker/registry/tls/registry.key
```

Copy certs to the host:
```bash
scp /tmp/registry.crt 5860-proxmox:/etc/docker/registry/tls/registry.crt
scp /tmp/registry.key 5860-proxmox:/etc/docker/registry/tls/registry.key
chmod 640 /etc/docker/registry/tls/registry.key   # registry daemon user only
```

**Do NOT restart the service yet.** Proceed to A4 first.

### A4 — Distribute the CA cert to containerd on every node

Each node's containerd must trust the cluster CA before the registry is
switched to TLS, otherwise all pulls fail cluster-wide.

containerd v2 per-registry config lives under a directory pointed to by
`config_path` in `/etc/containerd/config.toml` under the
`[plugins."io.containerd.cri.v1.images".registry]` section. The file structure:

```
/etc/containerd/certs.d/
  192.168.3.207:5003/
    hosts.toml
```

`hosts.toml` content:
```toml
server = "https://192.168.3.207:5003"

[host."https://192.168.3.207:5003"]
  capabilities = ["pull", "resolve", "push"]
  ca = "/etc/containerd/certs.d/192.168.3.207:5003/lab-ca.crt"
  # After TLS is confirmed, add: skip_verify = false
```

**Per node** (do one node at a time, starting with a non-critical node — pick
`r740` or `r770`, NOT `t560` which runs etcd):

```bash
ssh <node> "mkdir -p /etc/containerd/certs.d/192.168.3.207:5003"
scp /tmp/lab-ca.crt <node>:/etc/containerd/certs.d/192.168.3.207:5003/lab-ca.crt
# Write hosts.toml (shown above)
ssh <node> "systemctl reload containerd"   # reload, not restart, to avoid pod churn
```

Confirm containerd config_path is set. If not:
```bash
ssh <node> "grep -A5 'cri.v1.images' /etc/containerd/config.toml"
```
If `config_path` is absent, add:
```toml
[plugins."io.containerd.cri.v1.images".registry]
  config_path = "/etc/containerd/certs.d"
```
Then `systemctl restart containerd` (pods will restart on this node — do it
during a low-traffic window and only one node at a time).

**Test before moving to the next node**:
```bash
# From the node (not from the cluster):
curl --cacert /tmp/lab-ca.crt https://192.168.3.207:5003/v2/ -v
# Expect: HTTP 200, no SSL error
```

Repeat for all four nodes. Order: `r740` → `r770` → `r740`-verify → `5860` →
`t560` (last, because it hosts etcd and apiserver).

### A5 — Switch registry daemon to TLS and remove insecure flags

Only after ALL four nodes have the CA installed and containerd reloaded:

```bash
ssh 5860-proxmox "systemctl restart docker-registry   # or whatever the unit name is"
# Confirm port is live over TLS:
curl --cacert /tmp/lab-ca.crt https://192.168.3.207:5003/v2/
```

Now update every kaniko build job: remove `--insecure-registry` and add
`--registry-certificate=192.168.3.207:5003=/kaniko/tls/lab-ca.crt`. The
CA cert must be mounted into the kaniko container (see manifest snippet in
pillar C section).

**Rollback for A5**: restart the registry daemon with the old config (the .bak
file). Nodes still have their CA trust installed, which is harmless; the
`--insecure-registry` flags in build jobs can be restored from git.

---

## Pillar B — cosign image signing

### B0 — Key generation

Generate a cosign key pair. Store the private key as a Kubernetes Secret in
the `beagle` namespace. The public key goes into a ConfigMap consumed by the
verification init-container.

```bash
# On the operator workstation (not in the cluster):
cosign generate-key-pair
# Produces cosign.key and cosign.pub
kubectl create secret generic cosign-signing-key \
  --namespace beagle \
  --from-file=cosign.key=./cosign.key
kubectl create configmap cosign-public-key \
  --namespace beagle \
  --from-file=cosign.pub=./cosign.pub
# Store cosign.key in a password manager; delete local copy after import.
rm ./cosign.key
```

### B1 — Sign in kaniko build jobs

After the kaniko container pushes the image, a second container in the same
pod signs it with cosign. Because kaniko runs as the only container in the
pod (Job), the signature step is an additional container that shares the
workspace via an emptyDir, or a separate Job triggered by a CronJob / pipeline.

The cleanest pattern is a **sidecar-style signing container** in the same pod,
running sequentially via an initContainer → kaniko → sign ordering using
`postStart` hooks or a wrapper script. Since kaniko does not support
`postStart`, the recommended approach is a **wrapper Job** with two sequential
containers using a shared `done` file signal, or simply a second Job that the
CI/CD pipeline triggers after confirming the push.

Example two-step Job pattern (applicable to every existing build-job.yaml):

```yaml
# Appended to the existing kaniko container spec — the signing container:
      - name: sign
        image: bitnami/cosign:latest
        command:
          - /bin/sh
          - -c
          - |
            # Wait for kaniko to finish (kaniko exits, this container runs after)
            IMAGE="192.168.3.207:5003/${IMAGE_NAME}:${BEAGLE_IMAGE_TAG}"
            # Resolve to digest before signing (ensures we sign the exact bytes pushed)
            DIGEST=$(cosign triangulate --type digest ${IMAGE} \
              --registry-cacert /cosign/tls/lab-ca.crt 2>/dev/null || \
              crane digest --insecure ${IMAGE})
            cosign sign --yes \
              --key /cosign/key/cosign.key \
              --registry-ca-cert /cosign/tls/lab-ca.crt \
              "${IMAGE}@${DIGEST}"
        env:
          - name: IMAGE_NAME
            value: beagle-core-exocortex    # override per build job
          - name: BEAGLE_IMAGE_TAG
            valueFrom:
              fieldRef:
                fieldPath: metadata.labels['job-name']   # or hardcode
          - name: COSIGN_PASSWORD
            valueFrom:
              secretKeyRef:
                name: cosign-signing-key
                key: cosign.password        # if key is passphrase-protected
        volumeMounts:
          - name: cosign-key
            mountPath: /cosign/key
            readOnly: true
          - name: registry-ca
            mountPath: /cosign/tls
            readOnly: true
      volumes:
        - name: cosign-key
          secret:
            secretName: cosign-signing-key
        - name: registry-ca
          configMap:
            name: registry-ca-cert         # see A6 below
```

**Note**: The cosign container runs after kaniko only if it is listed after
the kaniko container in `spec.containers`. In a Job with a single pod,
containers start concurrently. The proper sequencing is to use an
`initContainer` for kaniko (which exits 0 on success) and then the signing
step in the main container. This is a minor refactor of the existing jobs.

### B2 — Verify signatures on pull (init-container pattern)

Add an `initContainer` to every Deployment / StatefulSet that verifies the
cosign signature before the main container starts. If verification fails, the
pod does not start.

```yaml
      initContainers:
        - name: verify-signature
          image: bitnami/cosign:latest
          command:
            - cosign
            - verify
            - "--key=/cosign/pub/cosign.pub"
            - "--registry-ca-cert=/cosign/tls/lab-ca.crt"
            - "192.168.3.207:5003/$(IMAGE_NAME):$(IMAGE_TAG)"
          env:
            - name: IMAGE_NAME
              value: beagle-core-exocortex
            - name: IMAGE_TAG
              value: modernization-601b8e31
          volumeMounts:
            - name: cosign-pub
              mountPath: /cosign/pub
              readOnly: true
            - name: registry-ca
              mountPath: /cosign/tls
              readOnly: true
      volumes:
        - name: cosign-pub
          configMap:
            name: cosign-public-key
        - name: registry-ca
          configMap:
            name: registry-ca-cert
```

**Rollback for B**: remove the `sign` container from build jobs and the
`verify-signature` initContainer from deployments. No running pods are
affected until they are next rescheduled.

---

## Pillar C — Immutable digest pinning

### C0 — Why digests

A tag like `beagle-core-exocortex:modernization-601b8e31` can be re-pushed.
`image@sha256:<hash>` cannot be silently changed without updating the manifest.
This is the last line of defense: even if signing is compromised, a pinned
digest prevents a MITM from serving a different image.

### C1 — Resolving digests after a build

After every successful kaniko push + cosign sign, resolve and record the
digest:

```bash
DIGEST=$(crane digest --insecure 192.168.3.207:5003/${IMAGE_NAME}:${TAG})
# or after TLS:
DIGEST=$(crane digest --cacert /tmp/lab-ca.crt https://192.168.3.207:5003/${IMAGE_NAME}:${TAG})
echo "${IMAGE_NAME}@${DIGEST}" > /tmp/pinned-ref.txt
```

Use this `image@sha256:…` ref in all Deployment / StatefulSet / Pod specs
instead of the mutable tag.

### C2 — Updating existing deployments

Each existing deployment currently references a mutable tag. The migration is:

1. For each image reference in `k8s/`, resolve the current digest:
   ```bash
   # For each tag in grep output:
   for ref in $(grep -rh '192.168.3.207:5003' k8s/ | grep -oP '192\.168\.3\.207:5003/\S+'); do
     echo "$ref -> $(crane digest --insecure $ref 2>/dev/null || echo 'UNRESOLVABLE')"
   done
   ```
2. Update the YAML to use `image: 192.168.3.207:5003/<name>@sha256:<hash>`.
3. Keep the tag as a comment (`# was: :stable`) for human readability.

### C3 — CA ConfigMap for kaniko and cosign

Create a shared ConfigMap holding the lab CA cert (extracted from the
cert-manager Secret in step A2):

```yaml
# k8s/registry-hardening/02-registry-ca-configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: registry-ca-cert
  namespace: beagle
data:
  lab-ca.crt: |
    -----BEGIN CERTIFICATE-----
    # PASTE the base64-decoded content of lab-ca.crt here
    -----END CERTIFICATE-----
```

Mount this ConfigMap into every kaniko container replacing the
`--insecure-registry` flag:

```yaml
          args:
            - "--dockerfile=/workspace/apps/.../Dockerfile"
            - "--context=dir:///workspace"
            - "--destination=192.168.3.207:5003/$(IMAGE_NAME):$(BEAGLE_IMAGE_TAG)"
            # REMOVED: --insecure-registry=192.168.3.207:5003
            - "--registry-certificate=192.168.3.207:5003=/kaniko/tls/lab-ca.crt"
          volumeMounts:
            - name: workspace
              mountPath: /workspace
            - name: registry-ca
              mountPath: /kaniko/tls
              readOnly: true
      volumes:
        - name: registry-ca
          configMap:
            name: registry-ca-cert
```

---

## Staged rollout sequence

```
Phase 0 — Audit (read-only, no changes)
  └─ Confirm cert-manager is healthy
  └─ Confirm dnsmasq on 5860 can serve registry.lab.sounio → 192.168.3.207
  └─ Inventory all image refs + current digests (crane loop above)
  └─ Confirm cosign is installable in build job nodes

Phase 1 — CA bootstrap (no traffic impact)
  └─ Apply 00-cluster-ca.yaml          (creates CA key in cert-manager only)
  └─ Apply 01-registry-cert.yaml       (issues TLS cert, stored in Secret)
  └─ Extract certs to /tmp on operator workstation

Phase 2 — Node trust rollout (one node at a time, 15min gap)
  └─ r740: install CA, reload containerd, test curl
  └─ r770: install CA, reload containerd, test curl
  └─ 5860: install CA, reload containerd, test curl
  └─ t560: install CA, reload containerd, test curl (last — runs etcd)

Phase 3 — Registry TLS cut-over (brief window; coordinate with team)
  └─ Back up /etc/docker/registry/config.yml on 5860
  └─ Deploy TLS cert files to 5860 host
  └─ Restart registry daemon on 5860
  └─ Immediately test: curl --cacert lab-ca.crt https://192.168.3.207:5003/v2/
  └─ Test a pull from each node: ctr --plain-http=false image pull 192.168.3.207:5003/<image>@<digest>
  └─ If ANY node fails: revert registry config, restart daemon, cluster recovers

Phase 4 — Build job migration (one job at a time)
  └─ Apply 02-registry-ca-configmap.yaml
  └─ Update beagle build-job.yaml: remove --insecure-registry, add --registry-certificate
  └─ Run one build, verify push succeeds
  └─ Roll out to remaining build jobs

Phase 5 — cosign signing (new builds only, does not affect running pods)
  └─ Generate cosign key pair, import to Kubernetes Secrets
  └─ Add sign container to one build job (beagle-core-build as pilot)
  └─ Verify signature is queryable: cosign verify ...
  └─ Roll out to all build jobs

Phase 6 — cosign verification init-containers
  └─ Add verify-signature initContainer to beagle Deployment (pilot)
  └─ Confirm pod starts and initContainer exits 0
  └─ Roll out to all Deployments / StatefulSets

Phase 7 — Digest pinning
  └─ Resolve current digests for all running images
  └─ Update k8s YAML files to image@sha256:...
  └─ Update catalog env files (workspace-platform/catalog/always-on/*.env)
  └─ Roll out deployments one namespace at a time

Phase 8 — Remove insecure entries from containerd hosts.toml
  └─ After all nodes confirmed healthy on TLS, remove any residual skip_verify=true
```

---

## Rollback procedures

| Phase | Rollback action |
|---|---|
| Phase 1 | `kubectl delete -f 00-cluster-ca.yaml -f 01-registry-cert.yaml` — no cluster impact |
| Phase 2 | `ssh <node> "rm -rf /etc/containerd/certs.d/192.168.3.207:5003 && systemctl reload containerd"` |
| Phase 3 | `ssh 5860-proxmox "cp /etc/docker/registry/config.yml.bak.<date> /etc/docker/registry/config.yml && systemctl restart docker-registry"` |
| Phase 4 | Restore `--insecure-registry` in build job YAML; rebuild |
| Phase 5 | Remove signing container from build jobs; existing signed images remain valid |
| Phase 6 | Remove `verify-signature` initContainer from Deployments; next rollout |
| Phase 7 | Revert image refs to mutable tags; next rollout |

---

## What this plan does NOT cover (future work)

- **Registry authentication** (basic auth or token auth): adds push/pull
  access control; requires updating kaniko with `--registry-auth` and
  containerd `hosts.toml` with `[host.auth]` blocks.
- **Notary v2 / TUF**: a more mature supply-chain model; cosign is sufficient
  for this cluster size.
- **Registry migration to VLAN 130 / `10.30.0.x`**: the service fabric README
  identifies this as the preferred home; TLS makes the migration trivial
  (just update the SAN to include the new IP/hostname and repeat Phase 2-3).
- **Admission webhook enforcement** (e.g., OPA/Kyverno policy): policy-as-code
  that rejects pods without a valid cosign signature at admission time, removing
  the need for initContainers. Recommended once pillar B is stable.

---

## Files this plan introduces

All new files go under `k8s/registry-hardening/`:

```
k8s/registry-hardening/
  00-cluster-ca.yaml          — self-signed bootstrap CA + ClusterIssuer
  01-registry-cert.yaml       — TLS Certificate for 192.168.3.207:5003
  02-registry-ca-configmap.yaml — CA cert as ConfigMap (fill in after Phase 2)
  README.md                   — one-liner index pointing here
```

Existing files to patch (not yet patched — do in Phase 4+):

- `k8s/beagle/build-job.yaml`
- `k8s/beagle/mcp-build-job.yaml`
- `k8s/beagle-memory-lab/build-job.yaml`
- `k8s/project-cockpit/build-job.yaml`
- `k8s/physiome/build-job.yaml`
- `k8s/workspace-platform/workspace-agent-build-job.yaml`
- `k8s/moshi/build-job.yaml`
- `k8s/moshi/build-job-configmap.yaml`

---

## Human actions required to apply

1. **Verify cert-manager health** before applying anything:
   ```bash
   kubectl get clusterissuer letsencrypt-production
   kubectl get pods -n cert-manager
   ```
2. **Apply Phase 1** manifests (in `k8s/registry-hardening/`).
3. **Extract certs** and distribute to nodes one at a time (Phase 2).
   Keep a terminal open on each node during the reload.
4. **Coordinate Phase 3** cut-over with yourself: pick a window when no
   builds are in-flight and no pods are being rescheduled. The window for
   the registry restart is under 30 seconds if TLS is pre-configured.
5. **Run Phase 4 builds** one at a time; do not update all jobs simultaneously.
6. **Generate cosign key pair offline** (not on a cluster node) and import
   via kubectl — never store the private key in the repo.
7. **Fill in `02-registry-ca-configmap.yaml`** with the actual PEM from the
   cert-manager Secret after Phase 1 (the PEM is not hardcoded here because
   it is generated at runtime by cert-manager).

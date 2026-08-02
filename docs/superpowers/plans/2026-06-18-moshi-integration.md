# Moshi Voice Integration Plan
# 2026-06-18

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Integrate Kyutai Moshi full-duplex voice model as a live streaming voice interface for the Beagle exocortex. Two tasks, both implemented in this session (2026-06-18).

---

## Status: IMPLEMENTED

Both tasks were implemented and committed in session 2026-06-18. See commits:
- `feat(k8s): add Moshi full-duplex voice server deployment on r770 L4`
- `feat(backend): Moshi WebSocket proxy at GET /api/moshi/v1/session`

---

## Task 1: K8s Moshi Server Deployment (DONE)

**Files created:**
- `k8s/moshi/namespace.yaml` — Namespace `moshi`, label `app.kubernetes.io/part-of: beagle`
- `k8s/moshi/pvc.yaml` — Ceph RBD SSD PVC 20Gi for HuggingFace model cache
- `k8s/moshi/Dockerfile` — python:3.11-slim + libopus + ffmpeg + `pip install moshi`; CMD `python -m moshi.server --host 0.0.0.0 --port 8998`
- `k8s/moshi/deployment.yaml` — Deployment on r770-proxmox L4 GPU; runtimeClassName=nvidia; seccompProfile=Unconfined; HF_TOKEN from secret `moshi-secrets`; startupProbe TCP 120-cycle window for weight download; resources 18Gi–22Gi memory, 1 GPU
- `k8s/moshi/service.yaml` — ClusterIP on port 8998, name `moshi` in namespace `moshi`
- `k8s/moshi/kustomization.yaml` — Kustomize bundle

**Key design decisions:**
- `seccompProfile: Unconfined` — required per cluster doctrine (asyncio/socketpair blocked by default seccomp)
- `startupProbe.failureThreshold: 120` — Moshi downloads ~7B weights from HuggingFace on first start; 120 × 15s = 30 minutes window
- `nodeSelector: r770-proxmox` — L4 GPU node with 24GB VRAM (Moshi fits comfortably)
- `storageClassName: ceph-rbd-ssd` — SSD tier for model cache I/O

**Pre-deploy requirements:**
```bash
# Create HuggingFace token secret
kubectl create secret generic moshi-secrets \
  --namespace moshi \
  --from-literal=HF_TOKEN=<your-hf-token>

# Build and push image
docker build -t 192.168.3.207:5003/moshi-server:2026-06-18 k8s/moshi/
docker push 192.168.3.207:5003/moshi-server:2026-06-18

# Apply
kubectl apply -k k8s/moshi/
```

---

## Task 2: Beagle Backend WebSocket Proxy (DONE)

**Files modified/created:**
- `apps/beagle-monorepo/Cargo.toml` — Added `axum` feature `"ws"`, `tokio-tungstenite = "0.23"`, `futures = { workspace = true }`
- `apps/beagle-monorepo/src/http_exocortex/moshi.rs` — New module: bidirectional WS proxy
- `apps/beagle-monorepo/src/http_exocortex/mod.rs` — Wired `mod moshi; pub(crate) use moshi::*;`
- `apps/beagle-monorepo/src/http_exocortex/routes.rs` — Added `.route("/api/moshi/v1/session", get(moshi_session_handler))`

**Route:** `GET /api/moshi/v1/session` (WebSocket upgrade)

**Architecture:**
```
iOS/client ──WS──► beagle-core /api/moshi/v1/session ──WS──► moshi.moshi.svc:8998
                         │
                         ├── Audio frames (binary): bidirectional passthrough
                         └── Text frames (Inner Monologue): captured to
                             /api/exocortex/v1/capture/sessions/{id}/events
                             kind=inner_monologue
```

**Behaviour:**
- Opens a capture session on connect (fail-soft — voice continues if capture unavailable)
- Binary frames: bidirectional passthrough with zero processing
- Text frames from Moshi (Inner Monologue tokens): buffered at 20-char threshold, then posted to exocortex capture pipeline
- On disconnect: posts `session_closed` event and terminates both WebSocket connections

**Environment variables consumed:**
- `MOSHI_SERVER_URL` — upstream WebSocket URL (default: `ws://moshi.moshi.svc:8998/api`)
- `BEAGLE_CORE_SELF_URL` — self-reference for capture API (default: `http://localhost:8080`)
- `BEAGLE_API_TOKEN` — bearer token for capture API

---

## Future Tasks (not yet implemented)

### Task 3: iOS Client Integration
- Add `MoshiVoiceSession` Swift class using `URLSessionWebSocketTask`
- Present in BeagleCockpit as a "Voice Mode" surface
- Render Inner Monologue text stream in real-time alongside audio waveform visualization

### Task 4: Inner Monologue Memory Pipeline
- Promote captured `inner_monologue` events from capture sessions into durable memory atoms
- Tag with `source: moshi`, `session_id`, `occurred_at`
- Index in memory-engine for semantic recall

### Task 5: Kaniko Build Job
- Add kaniko build job for `moshi-server` image similar to existing cockpit build jobs
- Trigger on changes to `k8s/moshi/Dockerfile`

---

## Key Invariants

1. Voice session MUST continue even if exocortex capture is unavailable (fail-soft throughout)
2. Audio frames (binary) are never decoded or stored — only forwarded
3. Inner Monologue text frames are buffered minimally before capture (20-char threshold) to avoid excessive API calls
4. `seccompProfile: Unconfined` is non-negotiable for Moshi (asyncio requires socketpair)
5. `MOSHI_SERVER_URL` must be configurable for local dev without the cluster

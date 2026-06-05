# Project Cockpit Deployment

This is the cluster publication surface for the `project-cockpit` app.

Operational note:
- the live cockpit is currently pinned to `r770-proxmox` so the research and
  supercomputing truth lanes keep a stable path to Prometheus and the
  observability fabric

## What it publishes

- cluster service:
  - `project-cockpit.beagle.svc.cluster.local`
- tailnet HTTP service:
  - `http://sounio-cockpit.tail21cbc4.ts.net`
- Cloudflare mobile gateway:
  - `https://beagle.chiuratto.ai`
  - private origin: `http://project-cockpit.beagle.svc.cluster.local:80`
  - tunnel connector: `cloudflared-beagle-mobile`
  - secret: `cloudflared-beagle-mobile`

The mobile hostname is meant for Apple native clients and keeps the origin
private. The Cloudflare side owns the ingress mapping:

- `beagle.chiuratto.ai` -> `http://project-cockpit.beagle.svc.cluster.local:80`
- catch-all -> `http_status:404`

The native beagle contract is mediated by the cockpit auth bridge:

- public hostname: `beagle.chiuratto.ai`
- auth endpoint: `/api/auth/beagle-token`
- mobile chat endpoint: `/api/mobile/v1/chat`
- mobile idea route: `/api/mobile/v1/projects/:slug/ideas`
- mobile delegation route: `/api/mobile/v1/projects/:slug/delegations`
- mobile summary route: `/api/mobile/v1/summary`
- legacy compatibility endpoint: `/api/llm/complete`
- native apps should prefer `/api/mobile/v1/chat`; the legacy alias stays
  available for compatibility but is not the canonical public contract
- the mobile contract now makes the native semantics explicit:
  - `Talk` -> chat completion with provenance
  - `Save Idea` -> persisted idea with sync state
  - `Delegate` -> agent-backed handoff with session provenance
- private beagle-core: not exposed directly on this hostname
- mobile model-lane research:
  - [MOBILE_MODEL_RESEARCH.md](MOBILE_MODEL_RESEARCH.md)
- cluster model probe plan:
  - [CLUSTER_MODEL_PROBE_PLAN.md](CLUSTER_MODEL_PROBE_PLAN.md)

The Workbench Context backend is now part of the cluster deployment, not only
the local bridge. It persists under the `project-cockpit-data` PVC mounted at
`/var/lib/cockpit` and publishes both REST and HTTP JSON-RPC MCP surfaces:

- `GET /api/workbench/:slug/context/status`
- `GET /api/workbench/:slug/context/doctor`
- `POST /api/workbench/:slug/context/doctor`
- `GET /api/workbench/:slug/context/clients`
- `GET /api/workbench/:slug/context/sessions`
- `GET /api/workbench/:slug/context/audit`
- `GET /api/workbench/:slug/context/audit/events`
- `GET /api/workbench/:slug/context/recent`
- `GET /api/workbench/:slug/context/export`
- `GET /api/workbench/:slug/context/mcp/tools`
- `POST /api/workbench/:slug/context/ingest`
- `POST /api/workbench/:slug/context/import`
- `POST /api/workbench/:slug/context/query`
- `POST /api/workbench/:slug/context/graphrag/query`
- `POST /api/workbench/:slug/context/compiler/compile`
- `POST /api/workbench/:slug/context/mcp`
- `POST /api/workbench/:slug/mcp`

The HTTP MCP routes support JSON-RPC `initialize`, `tools/list`, `tools/call`,
and `ping`. They reuse the cockpit Beagle auth bridge and Beagle Core memory
paths for upstream write-through/query, while the PVC-backed local overlay
guarantees read-after-write and survives cockpit rollouts.
On the cluster deployment, HTTP MCP requires `Authorization: Bearer <token>`;
clients can use the existing `/api/auth/beagle-token` bridge to obtain the
operator token. The browser-facing REST Workbench routes remain same-origin
Cockpit routes.
Use `/api/workbench/:slug/context/doctor` as the deployment proof route:
`write_probe=true` validates PVC write, Beagle auth/write-through, RAG++
readback, bounded GraphRAG, and compiler in one packet.

Current rollout image for this Workbench Context + HTTP MCP contract:

- `192.168.3.207:5003/project-cockpit:workbench-context-http-mcp-20260523T233057Z`

Current rollout image for the GPU lease API / Action Ledger control contract:

- `192.168.3.207:5003/project-cockpit:gpu-lease-api-20260525T101842Z`

This image includes:

- `/opt/hpc-sota/ops/gpu-lease`
- `/opt/hpc-sota/GPU_RESOURCE_DOMAINS.yaml`
- `bash`, `python3`, `kubectl`, `ssh`, and `flock`
- `PROJECT_COCKPIT_ROOT=/app` so spawned cockpit commands do not inherit the
  host-only `/home/devsounio` cwd inside the container

Live proof, 2026-05-25 10:21 UTC:

- `GET /api/cluster/ops/gpu-leases` returns `darwin.gpu_lease_control.v1`
- `POST /api/cluster/ops/gpu-leases/r740-proxmox/preview` returns a dry-run
  proposal for Action Ledger
- `POST /api/cluster/ops/gpu-leases/r740-proxmox/apply` rejects missing ledger
  or missing idempotency with a non-2xx response
- idempotent `admit-batch r740-proxmox` passed through Action Ledger and
  returned HTTP `200` with receipt
- `r740-proxmox` remained batch/admitted after the live E2E
- `GET /api/cluster/ops/summary` observes Kubernetes from inside the cockpit:
  `4/4` nodes Ready, Cilium observed, `3` GPUs allocatable
- the summary separates active unhealthy pods from historical failed pods:
  active `Pending=6`, historical `Failed=305` at the original proof time
- residual yellow is real cluster state, not missing cockpit tools:
  host freshness is blocked by lack of host SSH/sudo path from the container
- live proof refreshed at 2026-05-25 11:34 UTC:
  - active unhealthy pods are `0`
  - historical `phase=Failed` pod tombstones were pruned
  - Grafana tailnet responds and the service has endpoint `10.0.0.196`
  - the remaining yellow on `/api/cluster/ops/summary` is host freshness only
- the embedded cockpit deployment sets `GPU_LEASE_HOST_PROCESS_CHECK=0`
  because host-level GPU process checks require operator SSH credentials; run
  `/home/devsounio/beagle/k8s/hpc-sota/ops/gpu-lease status` from the machine
  root for the full `HOST_GPU` column

The completion routes stay cockpit-owned. They now pass through the internal
model registry and operator policy wrapper before reaching a model endpoint:

- default/mobile execution uses the live `LFM2.5-1.2B-Instruct` always-on lane
  when available
- helper/audit/research lanes are recorded with probe evidence and currently
  fall back to the always-on lane unless deliberately stood up
- raw operator mutation is blocked; no current candidate is approved to suggest
  RBAC, node, package, scheduler, or Kubernetes write actions without a
  human-reviewed Cockpit operator packet
- operator-routed completions are constrained to JSON text with
  `decision: readonly | blocked` in this first gate; command lists are emitted
  empty, and future mutation paths must go through the action ledger/operator
  packet contract

Registry endpoint:

- `/api/projects/sounio/inference/model-registry`

Current cluster rollout image carrying this contract plus the agent MCP
`cockpit_model_registry`, `cockpit_action_ledger`, and
`cockpit_propose_action` tools:

- `192.168.3.207:5003/project-cockpit:model-registry-actionledger-20260523T013135Z`

Use the helper when you have the Cloudflare API token for the already-created
named tunnel:

```bash
CLOUDFLARE_API_TOKEN=... \
CLOUDFLARE_ACCOUNT_ID=83e53c929885be6ea1326d6baf8e0b91 \
CLOUDFLARE_TUNNEL_ID=e1145ee4-1aac-4502-be2d-d22ef35a8ef1 \
bash /home/devsounio/beagle/scripts/infrastructure/beagle/setup_beagle_mobile_tunnel.sh
```

The first route to care about is:

- `/projects`
- `/projects/sounio`

The sovereign index now carries posture language that should stay aligned with
the machine-level policy in:

- [/home/devsounio/projects/PROJECT_POSTURE_POLICY.md](/home/devsounio/projects/PROJECT_POSTURE_POLICY.md)

It also now carries a backend-authored `Go work now` packet per project so the
catalog can publish activation, attach, and standby commands as part of the
live control surface instead of recomputing that posture only in the browser.

The sovereign `/projects` route can now also trigger the narrowest safe
habitat actions directly for project surfaces:

- activate a `warm` habitat
- return a `warm` habitat to standby

This stays intentionally separate from cluster-truth mutations.

## Build and publish

```bash
cd /home/devsounio/beagle/apps/project-cockpit
podman build -t localhost/project-cockpit:20260406-9 .
bash /home/devsounio/beagle/k8s/workspace-platform/scripts/publish-node-local-images.sh \
  --registry-host 192.168.3.207:5003 \
  --prefix sounio-lab \
  --ttl stable \
  --plain-http \
  --out /home/devsounio/artifacts/workspace-platform-image-defaults-lab-registry-20260406.env
kubectl apply -k /home/devsounio/beagle/k8s/project-cockpit
kubectl rollout status deployment/project-cockpit -n beagle
```

## Browser smoke

Use the helper when you want a real browser-based gut check of the live route:

```bash
bash /home/devsounio/beagle/k8s/project-cockpit/smoke-browser.sh
```

Notes:
- browser automation should treat the advertised Tailnet VIP as the canonical
  path first
- the published hostname can still hit `ERR_BLOCKED_BY_CLIENT` in Chrome
  automation on this host, even when the service is healthy for humans
- `Lightpanda` can read both the hostname and the VIP on this host, which
  points away from an app bug and toward a Chrome/agent-browser runtime quirk
  for the hostname path
- the smoke helper now opens the VIP first and only falls back to the hostname
  if the VIP path is unavailable
- the same rule now applies to the `Sounio` planning lane inside the cockpit:
  humans can keep using the hostname route, but browser automation should copy
  the VIP-backed smoke URL instead
- the `Memory lane` now follows the same idea:
  - humans can still open the cockpit on the hostname route
  - but the UI prefers the VIP-backed `memory/fast` and `memory/deep` paths for
    resume hydration to avoid the slow hostname edge path
  - if the VIP-backed API path is slow or flaky from the current machine, the
    browser now falls back to the cockpit's same-origin API instead of leaving
    the `Memory lane` hanging
  - after the `fastedgepub3` rollout, both the VIP and the hostname route were
    measured fast again from the host for `memory/fast`
  - after the `guidedreview` rollout, the quick host smoke still held:
    - VIP: `elapsed=0.01`
    - hostname: `elapsed=0.21`
  - after the `memoryedge6` rollout, pod-local validation confirmed:
    - `memory/fast` returns warm cache responses in ~`1ms` app time
    - `memory/deep` no longer fails with `500` when the deep hydration path
      times out talking to the in-cluster apiserver
    - instead it degrades to:
      - `depth=deep-fast-fallback`
      - `meta.fallback=fast-memory`
      so re-entry still gets a useful sovereign packet instead of a hard error
  - after the `memoryedge8` rollout:
    - session heartbeats no longer blow away the deep cache
    - they mark it stale and let the next deep read refresh in the background
    - the `Continuity timeline` now survives re-entry with timestamped sovereign
      publication events instead of showing up empty
    - public `memory/deep` was measured healthy again from the host:
      - hostname: `elapsed=0.20`
      - VIP: `elapsed=0.00`
    - the returned packet now keeps:
      - `publicationStage`
      - `lastPrUrl`
      - `continuityTimeline`

## Publication continuity

The cockpit now exposes a more guided review/publication surface for Sounio:

- `Publication continuity`
  - open the current PR
  - open the public base branch
  - open the public compare view
  - copy reviewer context
  - copy merge-later checklist
- `Guided review flow`
  - open review thread
  - open changed files
  - open checks
  - copy a guided review packet
- `Merge readiness`
  - records the current review step in the cockpit session ledger
  - records merge readiness alongside the current PR URL
  - lets the memory lane rehydrate review state across machines
  - also records:
    - `checks pass`
    - `comments review`
    - `merge decision`
    - `publication stage`
  - publication stage now speaks in project-shaped states:
    - `working`
    - `published`
    - `under-review`
    - `merge-ready`
    - `merged-later`
- if the cockpit looks healthy but the workspace browser/SSH surfaces disappear
  after ingress churn, check the workspace tailnet repair lane before blaming
  the cockpit itself:
  - `/home/devsounio/beagle/k8s/hpc-sota/ops/repair-workspace-tailnet-services.sh`

## Notes

- The deployment now runs on the validated worker pair:
  - `r740-proxmox`
  - `r770-proxmox`
- It still prefers `r740-proxmox` first.
- The operational contract is now:
  - publish the image to the lab push registry at `192.168.3.207:5003`
  - let the validated workers pull via containerd's lab-registry hosts config
  - keep `r740` as the preferred landing node
  - allow `r770` to take over without changing manifests again
- That move remains intentional:
  - it keeps the cockpit off the `t560-proxmox` control-plane node
  - it avoids the recent `DiskPressure` churn that was evicting alpha cockpit
    pods on `t560-proxmox`
  - it gives the cockpit a clean worker failover lane inside the GPU-batch
    pool
- The worker-pool placement requires explicit tolerations for:
  - `sounio.dev/compute=heavy:NoSchedule`
  - `sounio.dev/pool=gpu-batch:NoSchedule`
- The current live image line is:
  - `ttl.sh/project-cockpit-goworkactions-20260411150337:24h`
- The current pod runs the app process as `root` inside the container because
  this runtime rejects `child_process.spawn(...)` for the unprivileged `node`
  user, and the cockpit depends on spawning `kubectl` and `tmux` bridge
  helpers.
- The current deployment also relaxes `seccomp` and `AppArmor` to
  `Unconfined` for the same reason; this is intentionally narrow to the
  cockpit pod and should be revisited if we later replace shelling-out with
  direct Kubernetes and Git APIs.
- The service account is intentionally narrow and only supports the current
  cockpit shape:
  - list/get pods
  - list/get/create/delete services
  - list/get deployments
  - list/get statefulsets
  - list/get cluster-scoped `tailscale.com/v1alpha1 ProxyGroup`
  - patch deployments and statefulsets for explicit rollout restarts
  - create exec sessions into pods
 - The cluster lane now reads and mutates Kubernetes primarily through the
   in-cluster HTTPS API.
 - `kubectl` remains in the cockpit for:
   - workspace shell actions in the habitat
   - the terminal `tmux` bridge

## Live alpha shape

The current live alpha now exposes:

- sovereign project index:
  - `http://sounio-cockpit.tail21cbc4.ts.net/projects`
- public route:
  - `http://sounio-cockpit.tail21cbc4.ts.net/projects/sounio`
- viewer lane:
  - `GET /api/viewer`
- toolchain lane:
  - `GET /api/projects/sounio/toolchain`
- git guardrails lane:
  - `GET /api/projects/sounio/git/guardrails`
- cluster lane:
  - `GET /api/projects/sounio/cluster/summary`
  - `GET /api/projects/sounio/cluster/actions/preview`
  - `POST /api/projects/sounio/cluster/actions/repair-workspace-tailnet-services`

That means the published cockpit can now answer, over the public Tailnet
surface:

- which project tools are installed in the habitat
- the live `Claude Code`, `Codex`, `Kimi`, and `agent-browser` versions
- whether GitHub auth is healthy
- whether commit, push, and draft PR actions are safe to offer
- whether the workspace HTTP/SSH publish lane is green
- and it can run the narrow workspace tailnet repair from inside the cluster
  surface when the habitat is healthy but the Tailscale operator status is stale
- the Memory lane now renders a visual continuity timeline instead of only a
  text block
- the Memory lane now also renders:
  - `Timeline by phase`
  - `Work`
  - `Publish`
  - `Review`
  - `Merge`
  so re-entry has an executive summary before the detailed ledger
- that executive summary now classifies each phase as:
  - `active`
  - `blocked`
  - `ready`
- the sovereign ledger now surfaces richer timeline events such as:
  - terminal re-entry
  - AI lane activation
  - useful command
  - publication stage
  - checks/comments review
  - merge decision and merge action
- the browser now prefers the current cockpit origin for `memory/fast` and only
  falls back to the alternate route if that first path is slow or unavailable
- browser automation still treats the hostname route as blocked on this host,
  so the VIP remains the canonical automation path even though the hostname is
  healthy for humans
- the public `/projects` route now renders the sovereign multi-project index
  instead of collapsing back into the `Sounio` pilot page
- that index now also hydrates a lightweight executive state per project from
  `memory/fast`, so the catalog itself starts behaving like a sovereign control
  plane instead of a static directory
- the terminal lane now lazy-loads `xterm` and its addons, which keeps the
  `/projects` route lighter and reduces runtime spillover into the browser
  automation path

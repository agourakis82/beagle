# conclave-search Chat Tool Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire `conclave-search` into Conclave's chat backend as a normal LLM tool call, via a new dedicated service that compiles it once and runs it safely with a timeout.

**Architecture:** A new `services/epistemic-search/` FastAPI service wraps a pre-compiled `conclave-search` binary in a timeout-bounded subprocess call, mirroring the proven `services/sounio-inference/` pattern. `apps/gpu-chat/server`'s tool registry gets a small interface change (`Tool.execute` becomes async-capable) and a new `search` tool that calls this service over HTTP.

**Tech Stack:** TypeScript/Vitest (`apps/gpu-chat/server`), Python/FastAPI (`services/epistemic-search`), Docker/podman two-stage build, Kubernetes.

**Spec:** [`docs/superpowers/specs/2026-08-26-conclave-search-chat-tool-design.md`](../specs/2026-08-26-conclave-search-chat-tool-design.md)

## Global Constraints

- `Tool.execute`'s new type is `(args: Record<string, unknown>) => string | Promise<string>` — the existing two tools (`calculate.ts`, `get-current-time.ts`) must continue to satisfy this without any change to their own code.
- The one call site (`apps/gpu-chat/server/src/routes/chat.ts`) must gain `await` — confirmed by grep to be the only non-test call site of `tool.execute(`.
- `services/epistemic-search/`'s k8s manifest must mirror `services/sounio-inference/k8s/deployment.yaml`'s real, current values exactly (node selector, tolerations, seccomp/AppArmor profiles, registry prefix `192.168.3.207:5003`) — not invented placeholder values.
- `SEARXNG_HOST`/`BEAGLE_CORE_HOST` default to the two pinned IPs from the TLS-backends plan: `10.96.250.10` / `10.96.250.20`.
- This plan does NOT have a working image-build-and-push-to-cluster-registry pipeline available in this session, and does NOT have write access to actually roll out a live Kubernetes deployment change to `gpu-chat-server` or `epistemic-search`. Tasks 3, 4, and 5 are explicit about exactly what CAN be verified locally (a `podman build` + local container run, `kubectl apply --dry-run=server`) versus what is real, necessary, but out-of-session-scope follow-up work (pushing an image, a live `kubectl apply`, a live rollout). Do not skip stating this plainly in each of those tasks.
- No AI-attribution in commit messages.
- This is a SHARED checkout (`/home/devsounio/beagle`, branch `reconcile/unify-beagle`) with substantial unrelated uncommitted work from other sessions. Never `git add -A` or `git add .` — stage only the exact files each task's own commit touches.

---

### Task 1: `Tool.execute` interface change + `chat.ts` await

**Files:**
- Modify: `apps/gpu-chat/server/src/tools/types.ts`
- Modify: `apps/gpu-chat/server/src/routes/chat.ts:104`

**Interfaces:**
- Consumes: nothing (first task).
- Produces: `Tool.execute: (args: Record<string, unknown>) => string | Promise<string>` — every later task's tool code relies on being allowed to return a `Promise<string>`.

- [ ] **Step 1: Confirm the current state (no test needed to "fail" here — this is a type-level change with no new runtime behavior yet)**

Read `apps/gpu-chat/server/src/tools/types.ts` — it currently reads:
```typescript
export interface Tool {
  name: string
  description: string
  parameters: Record<string, unknown>
  execute: (args: Record<string, unknown>) => string
}
```

- [ ] **Step 2: Change the interface**

```typescript
export interface Tool {
  name: string
  description: string
  parameters: Record<string, unknown>
  execute: (args: Record<string, unknown>) => string | Promise<string>
}
```

- [ ] **Step 3: Update the call site**

In `apps/gpu-chat/server/src/routes/chat.ts`, find this line (currently line 104, inside the `for (const call of result.tool_calls)` loop, inside a `try` block):
```typescript
toolResultText = tool.execute(args)
```
Change it to:
```typescript
toolResultText = await tool.execute(args)
```
The enclosing function is already `async` (it already does `await chatCompletion(...)` earlier in the same loop, at line 84), so no other structural change is needed.

- [ ] **Step 4: Run the existing test suite to confirm nothing broke**

Run: `cd apps/gpu-chat/server && npm test`
Expected: all existing tests still pass (this is a widening type change — every existing synchronous `execute` implementation still satisfies `string | Promise<string>` — plus `await`ing a plain, already-resolved value is a no-op, so runtime behavior for the two existing tools is unchanged).

- [ ] **Step 5: Also run the TypeScript build to confirm no type errors**

Run: `cd apps/gpu-chat/server && npm run build`
Expected: exits 0, no type errors (this specifically confirms `calculate.ts`'s and `get-current-time.ts`'s existing synchronous `execute` implementations still satisfy the widened interface with no changes needed on their end).

- [ ] **Step 6: Commit**

```bash
git add apps/gpu-chat/server/src/tools/types.ts apps/gpu-chat/server/src/routes/chat.ts
git commit -m "feat(gpu-chat): allow async tool execution"
```

---

### Task 2: `search.ts` tool + tests + registration

**Files:**
- Create: `apps/gpu-chat/server/src/tools/search.ts`
- Create: `apps/gpu-chat/server/src/tools/search.test.ts`
- Modify: `apps/gpu-chat/server/src/tools/index.ts`

**Interfaces:**
- Consumes: `Tool` (from `./types.js`, Task 1's widened interface).
- Produces: `searchTool: Tool` (name `search`), and the pure function `formatAnswer(answer: SynthesizedAnswer): string` — exported so tests can call it directly without a network mock.

- [ ] **Step 1: Write the failing tests**

```typescript
// apps/gpu-chat/server/src/tools/search.test.ts
import { describe, it, expect } from 'vitest'
import { searchTool, formatAnswer } from './search.js'

describe('searchTool', () => {
  it('has the expected name and a required query string parameter', () => {
    expect(searchTool.name).toBe('search')
    expect(searchTool.parameters).toEqual({
      type: 'object',
      properties: { query: { type: 'string', description: 'The search query' } },
      required: ['query'],
    })
  })

  it('rejects a non-string query', async () => {
    const result = await searchTool.execute({ query: 42 })
    expect(result).toBe('Error: "query" must be a non-empty string')
  })

  it('rejects an empty query', async () => {
    const result = await searchTool.execute({ query: '   ' })
    expect(result).toBe('Error: "query" must be a non-empty string')
  })
})

describe('formatAnswer', () => {
  it('renders a placeholder-concat summary with a corroboration-width note', () => {
    const out = formatAnswer({
      summary: 'Fact one. Fact two.',
      summary_kind: 'placeholder-concat',
      confidence_low: 0.68,
      confidence_high: 1.32,
      confidence_semantics: 'independent-corroboration-width',
    })
    expect(out).toContain('Fact one. Fact two.')
    expect(out).toContain('concatenation of relevant source sentences')
    expect(out).toContain('0.68-1.32')
    expect(out).toContain('less independent corroboration')
  })

  it('renders surfaced conflicts', () => {
    const out = formatAnswer({
      summary: 'Summary text.',
      summary_kind: 'placeholder-concat',
      confidence_low: 15.0,
      confidence_high: 25.0,
      confidence_semantics: 'independent-corroboration-width',
      conflicts: [
        {
          claim_a: { text: 'X is true', source_url: 'https://a.example' },
          claim_b: { text: 'X is false', source_url: 'https://b.example' },
          note: 'possible disagreement (negation marker near shared term) -- not a confirmed semantic conflict',
        },
      ],
    })
    expect(out).toContain('Possible conflicts found')
    expect(out).toContain('X is true')
    expect(out).toContain('https://a.example')
    expect(out).toContain('X is false')
    expect(out).toContain('https://b.example')
  })

  it('renders a plain summary with no extra notes for unrecognized markers', () => {
    const out = formatAnswer({
      summary: 'Plain text.',
      summary_kind: 'some-future-kind',
      confidence_low: 0,
      confidence_high: 1,
      confidence_semantics: 'some-future-semantics',
    })
    expect(out).toBe('Plain text.')
  })
})
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd apps/gpu-chat/server && npm test -- search`
Expected: FAIL — `./search.js` does not exist yet.

- [ ] **Step 3: Write `search.ts`**

```typescript
// apps/gpu-chat/server/src/tools/search.ts
import { Tool } from './types.js'

const EPISTEMIC_SEARCH_URL =
  process.env.EPISTEMIC_SEARCH_URL ?? 'http://epistemic-search.beagle.svc.cluster.local'
const FETCH_TIMEOUT_MS = 65_000 // slightly above the service's own 60s SEARCH_TIMEOUT_SECONDS

export interface SynthesizedAnswer {
  summary: string
  summary_kind: string
  confidence_low: number
  confidence_high: number
  confidence_semantics: string
  conflicts?: Array<{
    claim_a: { text: string; source_url: string }
    claim_b: { text: string; source_url: string }
    note: string
  }>
}

export function formatAnswer(answer: SynthesizedAnswer): string {
  const kindNote =
    answer.summary_kind === 'placeholder-concat'
      ? ' (this is a concatenation of relevant source sentences, not a generated summary)'
      : ''
  const confNote =
    answer.confidence_semantics === 'independent-corroboration-width'
      ? ` [corroboration interval: ${answer.confidence_low.toFixed(2)}-${answer.confidence_high.toFixed(2)}, wider = less independent corroboration]`
      : ''
  let out = `${answer.summary}${kindNote}${confNote}`
  if (answer.conflicts && answer.conflicts.length > 0) {
    out += '\n\nPossible conflicts found:\n'
    for (const c of answer.conflicts) {
      out += `- "${c.claim_a.text}" (${c.claim_a.source_url}) vs. "${c.claim_b.text}" (${c.claim_b.source_url}): ${c.note}\n`
    }
  }
  return out
}

export const searchTool: Tool = {
  name: 'search',
  description:
    "Searches the web and the user's own memory graph for a query, and returns a single synthesized, confidence-calibrated answer (not a list of links).",
  parameters: {
    type: 'object',
    properties: { query: { type: 'string', description: 'The search query' } },
    required: ['query'],
  },
  execute: async (args) => {
    const query = args.query
    if (typeof query !== 'string' || query.trim().length === 0) {
      return 'Error: "query" must be a non-empty string'
    }
    try {
      const res = await fetch(`${EPISTEMIC_SEARCH_URL}/v1/search`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ query }),
        signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
      })
      if (!res.ok) {
        return `Error: search backend returned ${res.status}`
      }
      const { raw_stdout } = (await res.json()) as { raw_stdout: string }
      const answer = JSON.parse(raw_stdout) as SynthesizedAnswer
      return formatAnswer(answer)
    } catch (err) {
      return `Error: ${(err as Error).message}`
    }
  },
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd apps/gpu-chat/server && npm test -- search`
Expected: PASS, all 6 test cases.

- [ ] **Step 5: Register the tool**

In `apps/gpu-chat/server/src/tools/index.ts`, currently:
```typescript
import { Tool } from './types.js'
import { getCurrentTimeTool } from './get-current-time.js'
import { calculateTool } from './calculate.js'

export const tools: Tool[] = [getCurrentTimeTool, calculateTool]
```
Change to:
```typescript
import { Tool } from './types.js'
import { getCurrentTimeTool } from './get-current-time.js'
import { calculateTool } from './calculate.js'
import { searchTool } from './search.js'

export const tools: Tool[] = [getCurrentTimeTool, calculateTool, searchTool]
```

- [ ] **Step 6: Run the full test suite and the build**

Run: `cd apps/gpu-chat/server && npm test && npm run build`
Expected: all tests pass, build exits 0.

- [ ] **Step 7: Commit**

```bash
git add apps/gpu-chat/server/src/tools/search.ts apps/gpu-chat/server/src/tools/search.test.ts apps/gpu-chat/server/src/tools/index.ts
git commit -m "feat(gpu-chat): add search tool calling the epistemic-search service"
```

---

### Task 3: `services/epistemic-search/` — build and locally verify the service

**Files:**
- Create: `services/epistemic-search/Dockerfile`
- Create: `services/epistemic-search/build.sh`
- Create: `services/epistemic-search/app.py`
- Create: `services/epistemic-search/requirements.txt`

**Interfaces:**
- Consumes: a built `sounio` toolchain (this session's own worktree at
  `/home/devsounio/sounio/.claude/worktrees/sounio-tls-on-madaros` has one
  already, from this project's own prior work — use it directly as the
  real input for `build.sh`'s staging step, no need to build a fresh
  toolchain) and a real `conclave-search` checkout (already present at
  `/home/devsounio/conclave-search`, complete and tested).
- Produces: a locally-built container image and a proven, exact request/
  response contract (`POST /v1/search {"query": "..."}` ->
  `{"raw_stdout": "..."}`) that Task 2's `search.ts` already assumes.

**What this task CAN prove, locally, in this session**: that the
two-stage build genuinely produces a working `conclave-search` binary
inside a minimal runtime image, and that `app.py`'s subprocess wrapper
genuinely invokes it correctly end-to-end, using `podman` (confirmed
available in this environment). **What this task CANNOT do**: push the
built image anywhere, or run it against the live cluster's real SearXNG/
beagle-core HTTPS fronts from outside the cluster network (those are only
reachable from inside the cluster, per the TLS-backends plan's own
findings) — this task's local run will therefore genuinely execute
`conclave-search` and exercise the full HTTP/subprocess/timeout plumbing,
but the underlying search itself will legitimately fail to reach
SearXNG/beagle-core (connection refused/timeout) since this session's
shell has no direct network path to their ClusterIPs. That is an accepted,
expected limitation of local-only testing, not a bug in this task's own
deliverable — the acceptance bar for this task is "the service correctly
runs the binary and returns its real output (including a real, legitimate
failure)", not "a live search succeeds."

- [ ] **Step 1: Write `requirements.txt`**

```
fastapi
uvicorn[standard]
pydantic
```

- [ ] **Step 2: Write `app.py`**

```python
# services/epistemic-search/app.py
import os
import subprocess
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

BINARY = os.environ.get("CONCLAVE_SEARCH_BIN", "/opt/conclave-search/bin/conclave-search")
SEARXNG_HOST = os.environ.get("SEARXNG_HOST", "10.96.250.10")
BEAGLE_CORE_HOST = os.environ.get("BEAGLE_CORE_HOST", "10.96.250.20")
SEARCH_TIMEOUT = int(os.environ.get("SEARCH_TIMEOUT_SECONDS", "60"))

app = FastAPI(title="Epistemic Search Service", version="0.1.0")

class SearchRequest(BaseModel):
    query: str

@app.get("/health")
def health():
    return {"status": "ok", "binary_exists": os.path.exists(BINARY)}

@app.post("/v1/search")
def search(req: SearchRequest):
    if not req.query.strip():
        raise HTTPException(422, "query must not be empty")
    try:
        result = subprocess.run(
            [BINARY, req.query, SEARXNG_HOST, BEAGLE_CORE_HOST],
            capture_output=True, text=True, timeout=SEARCH_TIMEOUT,
        )
    except subprocess.TimeoutExpired:
        raise HTTPException(504, f"search timed out after {SEARCH_TIMEOUT}s")
    if result.returncode != 0:
        raise HTTPException(502, f"search failed (exit {result.returncode}): {result.stdout[-500:]}")
    return {"raw_stdout": result.stdout}
```

- [ ] **Step 3: Write the Dockerfile**

```dockerfile
# services/epistemic-search/Dockerfile
# Stage 1: compile conclave-search ONCE, using the Sounio toolchain.
FROM debian:bookworm-slim AS build
COPY sounio-runtime/bin/souc /opt/sounio/bin/souc
COPY sounio-runtime/bin/souc-linux-x86_64 /opt/sounio/bin/souc-linux-x86_64
COPY sounio-runtime/stdlib /opt/sounio/stdlib
COPY conclave-search-src /opt/conclave-search-src
ENV SOUNIO_STDLIB_PATH=/opt/sounio/stdlib
RUN /opt/sounio/bin/souc compile /opt/conclave-search-src/src/main.sio \
      -o /opt/conclave-search-src/bin/conclave-search

# Stage 2: minimal runtime -- just the compiled binary, no toolchain.
FROM python:3.12-slim
COPY --from=build /opt/conclave-search-src/bin/conclave-search /opt/conclave-search/bin/conclave-search
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
EXPOSE 8800
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8800/health').status==200 else 1)"
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8800"]
```

Note: this task's Dockerfile deliberately omits the
`COPY internal-ip-ca-root.crt ...` / `RUN update-ca-certificates` step the
spec's own Dockerfile sketch includes — that step needs a real CA-root PEM
file staged into the build context, which is a real deployment concern
(Task 4/5's territory), not something this task's local proof-of-concept
build needs in order to prove the compile-and-subprocess mechanism works.
Add it back when this image is actually built for real deployment.

- [ ] **Step 4: Write `build.sh`**

```bash
#!/usr/bin/env bash
# services/epistemic-search/build.sh
# Stages the Sounio runtime and conclave-search source into a build
# context, then builds the service image. Mirrors
# services/sounio-inference/build.sh's exact staging pattern.
set -euo pipefail

SOUNIO_DIR="${SOUNIO_DIR:-/home/devsounio/sounio}"
CONCLAVE_SEARCH_DIR="${CONCLAVE_SEARCH_DIR:-/home/devsounio/conclave-search}"
IMAGE="${IMAGE:-epistemic-search:dev}"
ENGINE="${ENGINE:-podman}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CTX="$(mktemp -d)"
trap 'rm -rf "$CTX"' EXIT

echo "==> staging Sounio runtime from $SOUNIO_DIR"
mkdir -p "$CTX/sounio-runtime/bin"
cp "$SOUNIO_DIR/bin/souc"               "$CTX/sounio-runtime/bin/"
cp "$SOUNIO_DIR/bin/souc-linux-x86_64"  "$CTX/sounio-runtime/bin/"
cp -r "$SOUNIO_DIR/stdlib"              "$CTX/sounio-runtime/stdlib"

echo "==> staging conclave-search source from $CONCLAVE_SEARCH_DIR"
cp -r "$CONCLAVE_SEARCH_DIR/src"    "$CTX/conclave-search-src/src"
cp -r "$CONCLAVE_SEARCH_DIR/search" "$CTX/conclave-search-src/search"

cp "$HERE/app.py" "$HERE/requirements.txt" "$HERE/Dockerfile" "$CTX/"

echo "==> building $IMAGE with $ENGINE"
"$ENGINE" build -t "$IMAGE" "$CTX"
echo "==> done: $IMAGE"
```

- [ ] **Step 5: Build the image locally, using this session's own real toolchain and conclave-search checkout**

Run:
```bash
SOUNIO_DIR=/home/devsounio/sounio/.claude/worktrees/sounio-tls-on-madaros \
  CONCLAVE_SEARCH_DIR=/home/devsounio/conclave-search \
  bash services/epistemic-search/build.sh
```
Expected: the build completes, ending with `==> done: epistemic-search:dev`.
If the `souc compile` step inside the build fails, check the exact error —
this is a real, meaningful signal (e.g. a missing module the build
context didn't stage; check whether `conclave-search`'s `src/main.sio`
imports anything beyond `src/` and `search/` that also needs staging).

- [ ] **Step 6: Run the built image locally and verify `/health`**

Run:
```bash
podman run -d --name epistemic-search-test -p 8800:8800 epistemic-search:dev
sleep 2
curl -s http://127.0.0.1:8800/health
```
Expected: `{"status":"ok","binary_exists":true}`.

- [ ] **Step 7: Run a real search request and verify the subprocess/timeout plumbing works end-to-end**

Run:
```bash
curl -s -X POST http://127.0.0.1:8800/v1/search \
  -H 'Content-Type: application/json' \
  -d '{"query": "test query"}'
```
Expected: since this container has no network path to the real SearXNG/
beagle-core ClusterIPs (they're only reachable inside the cluster), this
will genuinely fail — most likely a `502` with `conclave-search: ...`
failure text in the body (e.g. a connection failure to `10.96.250.10`),
NOT a timeout (`504`) and NOT a `500`/crash. A `502` with real
`conclave-search`-authored error text in it is the correct, expected
result here — it proves the full chain (HTTP -> subprocess -> the real
compiled binary -> the binary's own real argv/host handling -> a real,
legitimate network failure) all worked correctly. If you instead get a
`504` (timeout) or a raw Python traceback, investigate — those would
indicate an actual defect in this task's own code, not just the expected
absence of network access.

- [ ] **Step 8: Clean up the local test container**

Run: `podman rm -f epistemic-search-test`

- [ ] **Step 9: Commit**

```bash
git add services/epistemic-search/Dockerfile services/epistemic-search/build.sh services/epistemic-search/app.py services/epistemic-search/requirements.txt
git commit -m "feat(epistemic-search): new service wrapping conclave-search in a timeout-bounded subprocess"
```

---

### Task 4: Kubernetes manifests for `services/epistemic-search/` (dry-run only, NOT deployed)

**Files:**
- Create: `services/epistemic-search/k8s/deployment.yaml`

**Interfaces:**
- Consumes: `services/sounio-inference/k8s/deployment.yaml`'s real, current
  content (read it directly — its node selector, tolerations, security
  context, and resource values are mirrored here, not invented).
- Produces: a `Deployment` named `epistemic-search` and a `Service` named
  `epistemic-search` (ClusterIP, port 80 -> targetPort 8800) in the
  `beagle` namespace — Task 5's env-var wiring references this Service's
  DNS name (`epistemic-search.beagle.svc.cluster.local`).

**This task does NOT deploy anything.** It produces a manifest verified
only via `kubectl apply --dry-run=server`. Actually applying it requires
an image at `192.168.3.207:5003/epistemic-search:vN` to exist in the
cluster's registry first — building and pushing that image is real,
necessary follow-up work this plan explicitly does not attempt, since
this session has no established path to push to that private in-cluster
registry. State this plainly when this task reports back; do not imply
a real rollout happened.

- [ ] **Step 1: Read the real reference file**

Run: `cat services/sounio-inference/k8s/deployment.yaml`
Note its exact `nodeSelector`, `affinity`, `tolerations`,
`securityContext` (both pod- and container-level), and `resources`
blocks — you will reuse these exact values below, changing only the
name, image, port, and env vars to match this new service.

- [ ] **Step 2: Write the manifest**

```yaml
# services/epistemic-search/k8s/deployment.yaml
#
# Mirrors services/sounio-inference/k8s/deployment.yaml's node-pool,
# toleration, and security-context conventions -- both services run
# Sounio-compiled native binaries and need the same seccomp/AppArmor
# exemption on this cluster.
apiVersion: apps/v1
kind: Deployment
metadata:
  name: epistemic-search
  namespace: beagle
  labels:
    app: epistemic-search
spec:
  replicas: 1
  selector:
    matchLabels:
      app: epistemic-search
  template:
    metadata:
      labels:
        app: epistemic-search
    spec:
      securityContext:
        seccompProfile:
          type: Unconfined
      nodeSelector:
        sounio.dev/runtime-role: cluster-core
      affinity:
        nodeAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              preference:
                matchExpressions:
                  - key: kubernetes.io/hostname
                    operator: In
                    values:
                      - r770-proxmox
      tolerations:
        - key: sounio.dev/compute
          operator: Equal
          value: heavy
          effect: NoSchedule
        - key: sounio.dev/pool
          operator: Equal
          value: gpu-batch
          effect: NoSchedule
      containers:
        - name: epistemic-search
          image: 192.168.3.207:5003/epistemic-search:v1
          imagePullPolicy: Always
          ports:
            - containerPort: 8800
          env:
            - name: SEARXNG_HOST
              value: "10.96.250.10"
            - name: BEAGLE_CORE_HOST
              value: "10.96.250.20"
          securityContext:
            allowPrivilegeEscalation: false
            appArmorProfile:
              type: Unconfined
            seccompProfile:
              type: Unconfined
          livenessProbe:
            httpGet:
              path: /health
              port: 8800
            initialDelaySeconds: 15
            periodSeconds: 20
            failureThreshold: 3
          readinessProbe:
            httpGet:
              path: /health
              port: 8800
            initialDelaySeconds: 10
            periodSeconds: 10
            failureThreshold: 3
          resources:
            requests:
              cpu: 250m
              memory: 256Mi
            limits:
              cpu: "1"
              memory: 512Mi
---
apiVersion: v1
kind: Service
metadata:
  name: epistemic-search
  namespace: beagle
  labels:
    app: epistemic-search
spec:
  type: ClusterIP
  selector:
    app: epistemic-search
  ports:
    - port: 80
      targetPort: 8800
      protocol: TCP
```

- [ ] **Step 3: Dry-run verify against the live cluster's API (this validates the manifest's shape without creating anything)**

Run: `kubectl apply --dry-run=server -f services/epistemic-search/k8s/deployment.yaml`
Expected: `deployment.apps/epistemic-search created (server dry run)` and
`service/epistemic-search created (server dry run)`, no validation errors.
This confirms the manifest is well-formed and would be accepted by this
specific cluster's API/admission rules (e.g. the `seccompProfile`/
`appArmorProfile` fields this cluster's own policy requires) — it does
NOT create anything.

- [ ] **Step 4: Commit**

```bash
git add services/epistemic-search/k8s/deployment.yaml
git commit -m "feat(epistemic-search): k8s manifest (dry-run verified, not deployed -- needs an image push first)"
```

---

### Task 5: Wire the service URL into `gpu-chat-server`'s deployment config (prepared, NOT rolled out)

**Files:**
- Modify: `apps/gpu-chat/k8s/deployment.yaml`

**Interfaces:**
- Consumes: `EPISTEMIC_SEARCH_URL` (read by Task 2's `search.ts` via
  `process.env.EPISTEMIC_SEARCH_URL ?? 'http://epistemic-search.beagle.svc.cluster.local'`
  — the default already matches Task 4's Service DNS name, so this env
  var is a redundant-but-explicit override, not strictly required to
  function, but added for the same reason `LITELLM_BASE_URL` is
  explicit rather than relying on its own code default).

**This task does NOT roll out `gpu-chat-server`.** It prepares the exact
env var addition to the real deployment manifest, verified only via
`kubectl apply --dry-run=server`. Actually rolling this out requires
`gpu-chat-server`'s own image to be rebuilt (to include Task 1/2's code
changes) and pushed, then the live `Deployment` updated and a real
`kubectl rollout` performed — none of which this session can do (same
registry-push limitation as Task 4). State this plainly; do not imply a
live rollout happened.

- [ ] **Step 1: Read the real reference env block**

Run: `grep -n -A2 "LITELLM_BASE_URL" apps/gpu-chat/k8s/deployment.yaml`
Confirm the exact existing convention (as of this plan's writing):
```yaml
          env:
            - name: LITELLM_BASE_URL
              value: http://router.llm-router.svc.cluster.local:4000
```

- [ ] **Step 2: Add the new env var, following the same convention**

In `apps/gpu-chat/k8s/deployment.yaml`, add a new entry to the existing
`env:` list (in the same container spec as `LITELLM_BASE_URL`):
```yaml
            - name: EPISTEMIC_SEARCH_URL
              value: http://epistemic-search.beagle.svc.cluster.local
```

- [ ] **Step 3: Dry-run verify**

Run: `kubectl apply --dry-run=server -f apps/gpu-chat/k8s/deployment.yaml`
Expected: `deployment.apps/gpu-chat-server configured (server dry run)`
(or `unchanged` for any other resources in the same file), no validation
errors. This confirms the edited manifest is well-formed; it does NOT
apply the change or affect the live, running `gpu-chat-server` pods.

- [ ] **Step 4: Commit**

```bash
git add apps/gpu-chat/k8s/deployment.yaml
git commit -m "feat(gpu-chat): wire EPISTEMIC_SEARCH_URL env var (dry-run verified, not rolled out -- needs a rebuilt image first)"
```

---

## After This Plan

Two real pieces of follow-up work remain, both requiring registry/deploy
access this session doesn't have: (1) build and push a real
`epistemic-search` image (with the internal CA root baked in, per the
spec's full Dockerfile — Task 3's local build deliberately omitted this
step) to `192.168.3.207:5003`, then `kubectl apply` Task 4's manifest for
real; (2) rebuild and push `gpu-chat-server`'s own image with Tasks 1/2's
code changes, then roll out Task 5's env var change live. Both are
mechanical once someone with registry/deploy access picks them up — all
the actual code and manifests are already written, reviewed, and
committed by this plan.

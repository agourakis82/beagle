# Wiring conclave-search into Conclave's Chat Tool

## Background

`Sounio-lang/conclave-search` (a separate repository) is a complete,
tested Sounio-native CLI that performs correlation-aware web+memory
search: given a query, it queries `beagle-core`'s memory graph, discovers
candidate URLs via SearXNG, fetches and extracts claims from them,
combines everything into a confidence-calibrated answer, and gates a
write-back to the exocortex. A prior spec/plan
(`2026-08-26-conclave-search-tls-backends-design.md`) made its two
upstream dependencies — SearXNG and `beagle-core` — reachable over HTTPS
with certificates its TLS stack can validate, and verified this live.

Conclave (a SwiftUI chat app, built on a separate machine, not present in
this filesystem) never talks to search backends directly — it only calls
the shared chat backend, `apps/gpu-chat/server` (Fastify/Node.js/TypeScript),
over REST/SSE. That backend's tool registry
(`apps/gpu-chat/server/src/tools/`) currently has two tools
(`calculate.ts`, `get-current-time.ts`), both synchronous, pure-JS,
single-file. This spec wires `conclave-search` in as a third tool.

**Key existing constraint discovered while designing this**: `Tool.execute`
(`apps/gpu-chat/server/src/tools/types.ts`) is currently typed
`(args) => string` — synchronous. `conclave-search` is a native binary
invoked as a subprocess, which is inherently asynchronous in Node, and has
a real, documented risk of hanging indefinitely (its own TLS stack has no
connect/receive timeout). This spec changes that interface.

**Key existing precedent this spec reuses directly**: `services/sounio-inference/`
is a production service (live 74+ days) that already solves "run a Sounio
binary from a request, safely, with a timeout" — it wraps
`subprocess.run(..., timeout=...)` in a FastAPI service, ships a minimal
container with just the static `souc` compiler + stdlib (no full dev
toolchain), and deploys with a specific node-pool/toleration/seccomp
pattern already proven to work for Sounio-compiled binaries on this
cluster. This spec follows that same pattern, simplified: `conclave-search`
compiles to a single fixed binary rather than per-request snippets, so the
new service compiles it ONCE at image-build time and ships only the
resulting ELF at runtime — no toolchain/stdlib needed in the runtime image
at all.

## Goals

- Conclave's chat backend can invoke `conclave-search` as a normal LLM
  tool call, get back a readable answer (with its confidence-semantics and
  summary-kind markers rendered into plain text, not raw JSON), within a
  bounded time.
- A hung or slow search can never hang the chat backend's own event loop
  or a chat request indefinitely.
- The new service is deployed following this cluster's own proven
  conventions for running Sounio-compiled binaries (mirroring
  `sounio-inference`'s k8s shape), not a new, ad hoc pattern.
- `conclave-search`'s own binary and TLS-dependency wiring (the two pinned
  IPs from the TLS-backends plan) require zero code changes in
  `conclave-search` itself — this spec only builds around it.

## Non-goals

- Changing anything in `conclave-search` itself (a separate, already-complete
  repo).
- Changing anything about the TLS-backends infrastructure (already built,
  separate spec).
- A general request-time Sounio-compilation service (that's what
  `sounio-inference` already is, for a different purpose — this is a
  fixed-binary service, deliberately simpler).
- Streaming partial search results — `conclave-search` produces one JSON
  answer per invocation; this spec treats it as a single request/response,
  matching how `calculate`/`get-current-time` already behave.
- Rate-limiting, caching, or cost controls on search invocations — a
  real, later concern once this is live and used, not designed here
  speculatively.

## Architecture

### 1. `services/epistemic-search/` — the new backend service

A new service, in the same `services/` location and following the same
layout as `services/sounio-inference/`:

```
services/epistemic-search/
  Dockerfile         # two-stage build (see below)
  build.sh           # stages conclave-search source + sounio toolchain, builds image
  app.py             # FastAPI wrapper around the compiled binary
  requirements.txt
  k8s/
    deployment.yaml  # mirrors sounio-inference's node-pool/toleration/seccomp
    service.yaml
```

**Dockerfile, two stages:**

```dockerfile
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
COPY internal-ip-ca-root.crt /usr/local/share/ca-certificates/
RUN update-ca-certificates
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
EXPOSE 8800
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8800/health').status==200 else 1)"
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8800"]
```

**`build.sh`** stages three things into the build context before invoking
the image build, mirroring `sounio-inference/build.sh`'s exact staging
pattern: the sounio runtime (`bin/souc`, `bin/souc-linux-x86_64`,
`stdlib/`) from a `sounio` checkout, the `conclave-search` source from its
own checkout, and the internal CA root PEM produced by
`bash k8s/conclave-search-tls/extract-ca-root.sh` (from the TLS-backends
plan, same repo, already committed).

**`app.py`** (FastAPI, mirroring `sounio-inference/app.py`'s
subprocess-with-timeout shape, simplified — no compile-and-cache step,
since the binary is already compiled into the image):

```python
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

The `SEARXNG_HOST`/`BEAGLE_CORE_HOST` defaults are the two pinned IPs the
TLS-backends plan established and verified reachable
(`10.96.250.10`/`10.96.250.20`) — passed as `conclave-search`'s own
documented `argv[1]`/`argv[2]` overrides (its README confirms these are
real, optional CLI args on `main.sio`, distinct from the compile-time
constants Task 5 found were specific to its *test* files, not the shipped
binary).

**`k8s/deployment.yaml`** mirrors `sounio-inference`'s proven shape:
same `nodeSelector`/`tolerations` (wherever Sounio-compiled binaries are
scheduled on this cluster), same `seccompProfile: Unconfined` requirement
(Sounio-compiled ELFs need this, per existing cluster policy), pushed to
the same in-cluster registry (`192.168.3.207:5003/epistemic-search:vN`),
liveness probe on `/health`. `k8s/service.yaml` exposes it as a plain
ClusterIP (no external/tailnet exposure needed — only `gpu-chat-server`
calls it, in-cluster).

### 2. `apps/gpu-chat/server/src/tools/types.ts` — the interface change

```typescript
export interface Tool {
  name: string
  description: string
  parameters: Record<string, unknown>
  execute: (args: Record<string, unknown>) => string | Promise<string>
}
```

The existing two tools (`calculate.ts`, `get-current-time.ts`) are
unaffected — a plain `string` return still satisfies `string | Promise<string>`.

### 3. `apps/gpu-chat/server/src/routes/chat.ts` — the one call site

```typescript
// before:
toolResultText = tool.execute(args)
// after:
toolResultText = await tool.execute(args)
```

This is the only call site (confirmed by grep — `tool.execute(` appears
exactly once outside test files). The surrounding function is already
`async` (it already `await`s `chatCompletion` earlier in the same loop),
so adding `await` here requires no other structural change.

### 4. `apps/gpu-chat/server/src/tools/search.ts` — the new tool

```typescript
import { Tool } from './types.js'

const EPISTEMIC_SEARCH_URL =
  process.env.EPISTEMIC_SEARCH_URL ?? 'http://epistemic-search.beagle.svc.cluster.local'
const FETCH_TIMEOUT_MS = 65_000 // slightly above the service's own 60s SEARCH_TIMEOUT_SECONDS

interface SynthesizedAnswer {
  summary: string
  summary_kind: string
  confidence_low: number
  confidence_high: number
  confidence_semantics: string
  conflicts?: Array<{ claim_a: { text: string; source_url: string }; claim_b: { text: string; source_url: string }; note: string }>
}

export const searchTool: Tool = {
  name: 'search',
  description:
    'Searches the web and the user\'s own memory graph for a query, and returns a single synthesized, confidence-calibrated answer (not a list of links).',
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

function formatAnswer(answer: SynthesizedAnswer): string {
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
```

### 5. `apps/gpu-chat/server/src/tools/index.ts` — registration

```typescript
import { searchTool } from './search.js'
export const tools: Tool[] = [getCurrentTimeTool, calculateTool, searchTool]
```

## Data flow

1. The LLM (via `chatCompletion`) decides to call the `search` tool with a
   `query` argument.
2. `chat.ts`'s tool-call loop calls `await tool.execute(args)` — now
   awaited, per the interface change.
3. `search.ts` POSTs `{"query": ...}` to `epistemic-search`'s ClusterIP,
   with its own 65s abort timeout.
4. `epistemic-search`'s `app.py` runs the pre-compiled `conclave-search`
   binary with a 60s subprocess timeout, passing the two pinned
   SearXNG/beagle-core IPs as argv overrides.
5. On success, `app.py` returns the binary's raw JSON stdout wrapped in
   `{"raw_stdout": "..."}`; `search.ts` parses it and formats it into a
   readable string (summary + honestly-labeled confidence + any surfaced
   conflicts) for the LLM to read as the tool result.
6. On any failure (binary timeout, nonzero exit, network failure, fetch
   timeout, malformed JSON), `search.ts` returns a plain `Error: ...`
   string — matching `calculate.ts`'s own failure convention exactly, so
   the LLM sees a normal failed-tool-call message, not an exception
   propagating up through `chat.ts`.

## Error handling

- **Binary hangs** (a real, documented risk — `conclave-search`'s TLS
  stack has no connect/receive timeout): bounded by `app.py`'s
  `subprocess.run(..., timeout=SEARCH_TIMEOUT)`, which raises
  `TimeoutExpired` and `subprocess` guarantees the child is killed. The
  chat request itself is separately bounded by `search.ts`'s own
  `AbortSignal.timeout`, so even a service-level failure to enforce its
  own timeout can't hang the chat backend.
- **`epistemic-search` service itself is down/unreachable**: `fetch`
  throws, caught by `search.ts`'s `try/catch`, returned as a plain `Error:`
  string.
- **`conclave-search` exits non-zero** (e.g. zero usable sources across
  the whole run, per its own documented exit convention): surfaced as a
  502 with the last 500 bytes of its stdout for diagnostic value, which
  `search.ts` turns into a generic `Error: search backend returned 502`
  (the raw diagnostic stays server-side, in `epistemic-search`'s own
  logs, not leaked to the LLM/user — a deliberate choice to avoid dumping
  internal stack/CLI noise into a chat response).
- **Malformed/unparseable JSON from the binary** (shouldn't happen given
  `conclave-search`'s own established buffer-safety and JSON-escaping
  work, but defensively handled): `JSON.parse` throws, caught by the same
  `try/catch`, same `Error:` convention.

## Testing strategy

- **`search.test.ts`** (new, matching `calculate.test.ts`/
  `get-current-time.test.ts`'s existing conventions): unit tests for
  `formatAnswer` given hand-constructed sample `SynthesizedAnswer` objects
  (with and without conflicts, with each `summary_kind`/
  `confidence_semantics` value), and for `execute`'s error paths (empty
  query, non-string query) — no real network call needed for these.
- **`epistemic-search`'s own tests**: a lightweight test hitting `/health`
  against a real running container (build it, run it, curl `/health`,
  confirm `binary_exists: true`) — this is the actual proof the two-stage
  build genuinely produces a working binary, not just that the Dockerfile
  parses.
- **Real end-to-end** (manual, once deployed): trigger a real chat message
  that invokes the `search` tool, confirm a readable answer comes back
  within a reasonable time, and separately confirm the tool degrades
  honestly (a clear `Error:` string, not a hang or a raw stack trace) when
  the backend is stopped.

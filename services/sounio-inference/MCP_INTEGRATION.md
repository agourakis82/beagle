# MCP Integration Proposal: Sounio Inference Tools

This document is a copy-pasteable integration plan. Do not edit the live MCP
server source speculatively — apply each section only after the k8s Service for
`sounio-inference` is healthy and reachable from inside the `beagle` namespace.

---

## 1. Files to modify

| File | Action |
|------|--------|
| `/home/devsounio/beagle/apps/project-cockpit/server/contract.mjs` | Add 3 entries to the `cockpitManifest.endpoints` array |
| `/home/devsounio/beagle/apps/project-cockpit/server/job-routes.mjs` | Add HTTP proxy helpers + route registrations inside `registerJobRoutes` |
| `/home/devsounio/beagle/apps/project-cockpit/server/index.mjs` | No change needed — `registerJobRoutes` is already called at line 14763 |

---

## 2. Environment variable

Add to the project-cockpit Deployment at
`/home/devsounio/beagle/k8s/project-cockpit/deployment.yaml` (in the `env:` block):

```yaml
- name: SOUNIO_INFERENCE_URL
  value: "http://sounio-inference.beagle.svc.cluster.local:8000"
```

This is the only wiring change in the k8s manifests. The service name and port
must match whatever is declared in
`/home/devsounio/beagle/services/sounio-inference/k8s/service.yaml`.

---

## 3. contract.mjs — new manifest entries

Locate the closing bracket of the `endpoints` array (currently after the
`cockpit_beagle_discover` entry, around line 489). Insert the three entries
**before** the closing `]`:

```js
    {
      name: "sounio_smt_check",
      method: "POST",
      path: "/api/sounio/smt/check",
      description:
        "QF_LIA satisfiability check via Sounio's DPLL(T) engine. " +
        "Returns SAT / UNSAT / UNKNOWN for a set of linear-integer constraints. " +
        "Use to verify that a claim-set is mutually consistent before reasoning over it.",
      input_schema: {
        type: "object",
        required: ["constraints"],
        properties: {
          constraints: {
            type: "array",
            minItems: 1,
            maxItems: 64,
            description: "Array of QF_LIA constraints (up to 16 variables each).",
            items: {
              type: "object",
              required: ["coeffs", "bound"],
              properties: {
                coeffs: {
                  type: "array",
                  items: { type: "integer" },
                  maxItems: 16,
                  description: "Coefficients c_i such that Σ c_i·x_i ≤ bound."
                },
                bound: { type: "integer", description: "Right-hand-side bound." },
                label: { type: "string", description: "Human-readable label for this constraint." }
              }
            }
          }
        }
      },
      error_codes: ["BAD_REQUEST", "RUNTIME_UNAVAILABLE", "TIMEOUT", "INTERNAL"]
    },
    {
      name: "sounio_gum_propagate",
      method: "POST",
      path: "/api/sounio/gum/propagate",
      description:
        "GUM (JCGM 100) uncertainty propagation via Sounio's epistemic::gum stdlib. " +
        "Combines two measured quantities under a binary arithmetic operation and " +
        "returns the combined standard uncertainty, coverage factor k₉₅, expanded " +
        "uncertainty U₉₅, relative uncertainty %, and the 95 % confidence interval. " +
        "Use for any numeric measurement whose uncertainty must be tracked.",
      input_schema: {
        type: "object",
        required: ["inputs", "op"],
        properties: {
          inputs: {
            type: "array",
            minItems: 2,
            maxItems: 2,
            description: "Exactly two measured quantities (v1 binary form).",
            items: {
              type: "object",
              required: ["value", "u"],
              properties: {
                value: { type: "number", description: "Measured value." },
                u:     { type: "number", description: "Standard uncertainty (1σ)." },
                label: { type: "string", description: "Optional label." }
              }
            }
          },
          op: {
            type: "string",
            enum: ["add", "sub", "mul", "div"],
            description: "Binary operation to apply to the two inputs."
          }
        }
      },
      error_codes: ["BAD_REQUEST", "RUNTIME_UNAVAILABLE", "TIMEOUT", "INTERNAL"]
    },
    {
      name: "sounio_causal_dsep",
      method: "POST",
      path: "/api/sounio/causal/dsep",
      description:
        "d-separation (conditional independence) check via Sounio's causal::base " +
        "Pearl Bayes-ball algorithm. Given a DAG, source node X, target node Y, and " +
        "optional conditioning set Z, returns whether X ⊥ Y | Z holds in the graph. " +
        "Use before any causal inference step to confirm assumed independencies.",
      input_schema: {
        type: "object",
        required: ["n", "edges", "x", "y"],
        properties: {
          n:     { type: "integer", minimum: 1, maximum: 32, description: "Number of nodes (0-indexed)." },
          edges: {
            type: "array",
            description: "Directed edges as [source, target] integer pairs.",
            items: {
              type: "array",
              items: { type: "integer" },
              minItems: 2,
              maxItems: 2
            }
          },
          x:     { type: "integer", description: "Source node index." },
          y:     { type: "integer", description: "Target node index." },
          z:     {
            type: "array",
            items: { type: "integer" },
            maxItems: 32,
            default: [],
            description: "Conditioning set (node indices). Empty = marginal independence."
          }
        }
      },
      error_codes: ["BAD_REQUEST", "RUNTIME_UNAVAILABLE", "TIMEOUT", "INTERNAL"]
    },
```

---

## 4. job-routes.mjs — proxy helpers and route registrations

### 4a. Add the env constant near the top of the file (after line 36)

```js
const SOUNIO_INFERENCE_URL =
  process.env.SOUNIO_INFERENCE_URL ||
  "http://sounio-inference.beagle.svc.cluster.local:8000";
const SOUNIO_INFERENCE_TIMEOUT_MS = Number(
  process.env.SOUNIO_INFERENCE_TIMEOUT_MS || 90000
);
```

### 4b. Add the proxy helper function before `registerJobRoutes`

Insert this block immediately above the `// ─── Route registration ─────` comment
(currently at line 864):

```js
// ─── Sounio Inference proxy ──────────────────────────────────────────────
//
// Thin HTTP proxy: validate that the upstream is reachable, forward the
// request body as-is (FastAPI / Pydantic does its own schema validation),
// and re-wrap the response in the contract envelope. The sounio-inference
// service is CPU-only, namespace-local, and has no auth requirements.

async function proxySounioVerb(verb, body) {
  const url = `${SOUNIO_INFERENCE_URL}/v1/${verb}`;
  let response;
  const ac = new AbortController();
  const timer = setTimeout(() => ac.abort(), SOUNIO_INFERENCE_TIMEOUT_MS);
  try {
    response = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
      signal: ac.signal,
    });
  } catch (err) {
    if (err.name === "AbortError") {
      throw contractFailure(ErrorCode.TIMEOUT, `sounio-inference timed out for ${verb}`);
    }
    throw contractFailure(ErrorCode.RUNTIME_UNAVAILABLE, `sounio-inference unreachable: ${err.message}`);
  } finally {
    clearTimeout(timer);
  }

  let payload;
  try {
    payload = await response.json();
  } catch {
    throw contractFailure(ErrorCode.INTERNAL, `sounio-inference returned non-JSON for ${verb}`);
  }

  if (response.status === 422) {
    throw contractFailure(ErrorCode.BAD_REQUEST, payload?.detail?.[0]?.msg || "validation error");
  }
  if (response.status === 502 || response.status === 503) {
    throw contractFailure(ErrorCode.RUNTIME_UNAVAILABLE, payload?.detail || `sounio verb ${verb} failed`);
  }
  if (!response.ok) {
    throw contractFailure(ErrorCode.INTERNAL, `sounio-inference ${verb} HTTP ${response.status}`);
  }
  return payload;
}
```

### 4c. Add route registrations inside `registerJobRoutes`

Append the three `app.post` calls at the **end** of the `registerJobRoutes`
function body, just before its closing `}` (currently near line 1000+, after the
last existing route):

```js
  // ─── Sounio Inference verbs ────────────────────────────────────────
  // These are namespace-local: no slug, no project context required.
  // Path prefix /api/sounio/ keeps them distinct from /api/projects/:slug/*.

  app.post(
    "/api/sounio/smt/check",
    withEnvelope(async (req) => ({
      data: await proxySounioVerb("smt/check", req.body || {})
    }))
  );

  app.post(
    "/api/sounio/gum/propagate",
    withEnvelope(async (req) => ({
      data: await proxySounioVerb("gum/propagate", req.body || {})
    }))
  );

  app.post(
    "/api/sounio/causal/dsep",
    withEnvelope(async (req) => ({
      data: await proxySounioVerb("causal/dsep", req.body || {})
    }))
  );
```

---

## 5. Redeploy steps

After making the edits above:

```bash
# 1. Verify sounio-inference Service is live in the beagle namespace
kubectl -n beagle get svc sounio-inference

# 2. Trigger a Kaniko build of project-cockpit
#    (edit image tag in the build Job or bump the tag env var)
kubectl -n beagle delete job project-cockpit-build 2>/dev/null; true
kubectl -n beagle apply -f /home/devsounio/beagle/k8s/project-cockpit/build-job.yaml

# 3. Wait for build completion
kubectl -n beagle wait --for=condition=complete job/project-cockpit-build --timeout=300s

# 4. Update Deployment image tag to the newly built image
#    (the build job prints the pushed digest; set it in deployment.yaml)
kubectl -n beagle rollout restart deployment/project-cockpit

# 5. Smoke-test through the cockpit manifest endpoint
curl -sf http://project-cockpit.beagle.svc.cluster.local:4370/api/mcp/manifest.json \
  | jq '[.endpoints[].name] | map(select(startswith("sounio_")))'
# Expected: ["sounio_smt_check","sounio_gum_propagate","sounio_causal_dsep"]

# 6. Quick functional test
curl -sf -X POST \
  http://project-cockpit.beagle.svc.cluster.local:4370/api/sounio/smt/check \
  -H 'Content-Type: application/json' \
  -d '{"constraints":[{"coeffs":[1],"bound":10,"label":"x<=10"},{"coeffs":[-1],"bound":-5,"label":"x>=5"}]}' \
  | jq .
# Expected: ok:true, data.result:"SAT"
```

---

## 6. Design rationale and alternatives considered

**Path layout** (`/api/sounio/*` not `/api/projects/:slug/sounio/*`):
The sounio-inference service is a shared compute primitive, not scoped to one
project. Using a top-level prefix avoids requiring a project slug for every call
and mirrors how `/api/jobs/queue` is scoped (queue-routes.mjs, no slug).

**No new routes file**: The volume of new code is small (one helper + three
route registrations). Adding a dedicated `sounio-inference-routes.mjs` would be
appropriate only if additional verbs or request middleware (auth, rate limit) are
added later. At that point, extract `proxySounioVerb` and the three
`app.post` blocks into that file and import/register it in `index.mjs` following
the same pattern as `registerQueueRoutes`.

**No `idempotent()` wrapper**: All three verbs are pure computation (POST bodies
are deterministic given inputs). Idempotency middleware in this codebase is for
mutations with side effects (job submission, habitat scale). Omitting it here is
intentional and consistent with read-only tool patterns.

**Timeout default (90 s)**: `souc compile` is capped at 120 s inside the
inference service (`SOUNIO_COMPILE_TIMEOUT`), but cache hits run in ~1 ms. A
90 s proxy timeout covers the worst-case cold compile on a warm cluster without
blocking the cockpit request thread for the full compile window.

// contract.mjs
//
// Agent contract primitives: uniform envelope, structured error codes,
// request_id idempotency, and MCP manifest publication.
//
// Preserves our epistemic invariants (truthMode) on top of the generic
// {ok, data, error, meta} envelope. The envelope is opt-in per-route so
// existing routes continue to work; new mutations use it for safety.
//

import { randomUUID } from "node:crypto";

// ─── Error codes ───────────────────────────────────────────────────────
// Retryable: caller can re-attempt with exponential backoff.
// Non-retryable: caller should surface to user, no automatic retry.

export const ErrorCode = Object.freeze({
  // Retryable
  CLUSTER_UNREACHABLE:  { code: "CLUSTER_UNREACHABLE",  retryable: true,  http: 503 },
  RUNTIME_UNAVAILABLE:  { code: "RUNTIME_UNAVAILABLE",  retryable: true,  http: 503 },
  RATE_LIMIT:           { code: "RATE_LIMIT",           retryable: true,  http: 429 },
  TIMEOUT:              { code: "TIMEOUT",              retryable: true,  http: 504 },
  INTERNAL:             { code: "INTERNAL",             retryable: true,  http: 500 },

  // Non-retryable
  BAD_REQUEST:          { code: "BAD_REQUEST",          retryable: false, http: 400 },
  UNAUTHORIZED:         { code: "UNAUTHORIZED",         retryable: false, http: 401 },
  NOT_FOUND:            { code: "NOT_FOUND",            retryable: false, http: 404 },
  INVALID_SLUG:         { code: "INVALID_SLUG",         retryable: false, http: 400 },
  HABITAT_BUSY:         { code: "HABITAT_BUSY",         retryable: false, http: 409 },
  CONFLICT:             { code: "CONFLICT",             retryable: false, http: 409 },
});

/**
 * Build a contract error object.
 * @param {{code, retryable, http}} def — from ErrorCode
 * @param {string} message — human-readable detail
 */
export function contractError(def, message, extra = {}) {
  return {
    code: def.code,
    message: message || def.code,
    retryable: def.retryable,
    ...extra,
  };
}

// ─── Envelope ──────────────────────────────────────────────────────────
//
// Standard response shape:
//   { ok, data, error, meta: { truthMode, observedAt, latency_ms, attempt, request_id, trace_id? } }
//
// Legacy routes continue to return their existing payload; new routes use
// envelopeOk/envelopeErr to emit the contracted shape.

export function envelopeOk(data, meta = {}) {
  const defaultMeta = {
    truthMode: "observed",
    observedAt: new Date().toISOString(),
    ...meta,
  };
  return { ok: true, data, error: null, meta: defaultMeta };
}

export function envelopeErr(def, message, meta = {}) {
  return {
    ok: false,
    data: null,
    error: contractError(def, message, meta.errorExtra),
    meta: {
      truthMode: "stale",
      observedAt: null,
      ...meta,
    },
  };
}

/**
 * Wrap an async handler to produce a contract envelope and measure latency.
 * Usage:
 *   app.post("/foo", withEnvelope(async (req) => { ... return { data, meta }; }));
 */
export function withEnvelope(handler) {
  return async (req, res) => {
    const started = Date.now();
    const requestId = req.requestId || randomUUID();
    try {
      const result = await handler(req);
      const latency = Date.now() - started;

      if (result && result.__envelope === "err") {
        const env = envelopeErr(result.errorDef || ErrorCode.INTERNAL, result.message, {
          ...result.meta,
          latency_ms: latency,
          request_id: requestId,
        });
        res.status(result.errorDef?.http || 500).json(env);
        return;
      }

      const env = envelopeOk(result?.data ?? result, {
        ...result?.meta,
        latency_ms: latency,
        request_id: requestId,
      });
      res.json(env);
    } catch (err) {
      const latency = Date.now() - started;
      const def = err.code && ErrorCode[err.code] ? ErrorCode[err.code] : ErrorCode.INTERNAL;
      const env = envelopeErr(def, err.message, {
        latency_ms: latency,
        request_id: requestId,
      });
      res.status(def.http).json(env);
    }
  };
}

/**
 * Helper to signal errors from inside a handler.
 * Usage:
 *   throw contractFailure(ErrorCode.INVALID_SLUG, "unknown slug: xyz");
 */
export function contractFailure(errorDef, message) {
  const err = new Error(message);
  err.code = errorDef.code;
  return err;
}

// ─── Request-ID idempotency middleware ────────────────────────────────
//
// Clients send X-Request-ID on mutations. If the same request_id hits
// within TTL, we replay the original response instead of re-running the
// side effect. LRU cache, default 60s TTL.
//
// Usage:
//   app.post("/mutate", idempotent({ ttlMs: 60_000 }), handler);

const idempotencyStore = new Map();  // request_id → { at, response, statusCode }
const IDEMPOTENCY_TTL_MS_DEFAULT = 60_000;
const IDEMPOTENCY_MAX_ENTRIES = 2000;

function evictOld() {
  const now = Date.now();
  for (const [k, v] of idempotencyStore) {
    if (now - v.at > v.ttl) idempotencyStore.delete(k);
  }
  // Hard cap (LRU-ish): if still too big, remove oldest
  if (idempotencyStore.size > IDEMPOTENCY_MAX_ENTRIES) {
    const sorted = [...idempotencyStore.entries()].sort((a, b) => a[1].at - b[1].at);
    for (const [k] of sorted.slice(0, idempotencyStore.size - IDEMPOTENCY_MAX_ENTRIES)) {
      idempotencyStore.delete(k);
    }
  }
}

export function idempotent({ ttlMs = IDEMPOTENCY_TTL_MS_DEFAULT, requireHeader = false } = {}) {
  return (req, res, next) => {
    evictOld();
    const rid = req.header("X-Request-ID") || req.header("x-request-id");

    if (!rid) {
      if (requireHeader) {
        res.status(400).json(envelopeErr(
          ErrorCode.BAD_REQUEST,
          "mutation requires X-Request-ID header for idempotency"
        ));
        return;
      }
      // No request_id: generate one and proceed without caching replay.
      req.requestId = randomUUID();
      return next();
    }

    req.requestId = rid;

    // Replay if we've seen this request_id recently
    const cached = idempotencyStore.get(rid);
    if (cached && Date.now() - cached.at < cached.ttl) {
      res.set("X-Idempotent-Replay", "true");
      res.status(cached.statusCode).json(cached.response);
      return;
    }

    // Intercept res.json to cache the response
    const origJson = res.json.bind(res);
    res.json = (body) => {
      idempotencyStore.set(rid, {
        at: Date.now(),
        response: body,
        statusCode: res.statusCode,
        ttl: ttlMs,
      });
      return origJson(body);
    };

    next();
  };
}

// ─── MCP Manifest ──────────────────────────────────────────────────────
//
// Machine-readable description of all agent-facing endpoints.
// Published at /api/mcp/manifest.yaml and /api/mcp/manifest.json.
// Any MCP-compatible client (Claude Desktop, Cursor, ChatGPT Apps,
// custom agents) can discover our tools without running our stdio server.

export const cockpitManifest = {
  mcp_version: "1.0",
  agent: "beagle-cockpit",
  description: "Sovereign supercomputing control surface — multi-platform, truth-aware.",
  version: "0.10.0",
  truth_modes: ["observed", "remembered", "declared", "stale"],
  endpoints: [
    {
      name: "cockpit_catalog",
      method: "GET",
      path: "/api/catalog/executive",
      description: "All sovereign projects with postures and current executive state.",
      output_schema: {
        type: "object",
        properties: {
          generatedAt: { type: "string", format: "date-time" },
          projects: { type: "array", items: { $ref: "#/components/schemas/Project" } }
        }
      },
      cached_ttl_ms: 15000
    },
    {
      name: "cockpit_posture_policy",
      method: "GET",
      path: "/api/catalog/project-posture-policy",
      description: "Posture definitions (always-on/warm/cold) and assignments."
    },
    {
      name: "cockpit_mission_control",
      method: "GET",
      path: "/api/projects/{slug}/mission-control",
      description: "Full mission control packet — habitat, branch, execution packets.",
      params: [{ name: "slug", in: "path", required: true }]
    },
    {
      name: "cockpit_cluster_truth",
      method: "GET",
      path: "/api/projects/{slug}/cluster/lane-truth",
      description: "Cluster lane truth — infrastructure-shaped, not research-shaped.",
      params: [{ name: "slug", in: "path", required: true }]
    },
    {
      name: "cockpit_research_operations",
      method: "GET",
      path: "/api/projects/{slug}/research/operations",
      description: "Latest research operations (ABIDE campaigns, runs).",
      params: [{ name: "slug", in: "path", required: true }]
    },
    {
      name: "cockpit_inference_runtime",
      method: "GET",
      path: "/api/projects/{slug}/inference/runtime",
      description: "SGLang engine + Dynamo control plane + available models."
    },
    {
      name: "cockpit_viewer_runtime",
      method: "GET",
      path: "/api/projects/{slug}/viewer/runtime",
      description: "WebGPU renderer state + platform matrix."
    },
    {
      name: "cockpit_agent_sessions",
      method: "GET",
      path: "/api/projects/{slug}/agent/sessions",
      description: "Active agent pods (Claude Code, Codex, local) for this project."
    },
    {
      name: "cockpit_agent_session_start",
      method: "POST",
      path: "/api/projects/{slug}/agent/session/start",
      description: "Spawn a new persistent agent pod.",
      idempotency: { header: "X-Request-ID", ttl_ms: 60000 },
      input_schema: {
        type: "object",
        required: ["kind"],
        properties: {
          kind: { type: "string", enum: ["claude-code", "codex", "local-sglang", "custom"] }
        }
      },
      error_codes: ["INVALID_SLUG", "BAD_REQUEST", "CLUSTER_UNREACHABLE", "CONFLICT"]
    },
    {
      name: "cockpit_agent_session_pause",
      method: "POST",
      path: "/api/projects/{slug}/agent/session/{kind}/pause",
      idempotency: { header: "X-Request-ID", ttl_ms: 60000 },
      description: "Scale agent StatefulSet to 0 replicas (preserve PVC)."
    },
    {
      name: "cockpit_agent_session_resume",
      method: "POST",
      path: "/api/projects/{slug}/agent/session/{kind}/resume",
      idempotency: { header: "X-Request-ID", ttl_ms: 60000 }
    },
    {
      name: "cockpit_agent_session_stop",
      method: "POST",
      path: "/api/projects/{slug}/agent/session/{kind}/stop",
      idempotency: { header: "X-Request-ID", ttl_ms: 60000 },
      description: "Delete StatefulSet + Service. Optional: deletePVC, deleteMCPConfig."
    },
    {
      name: "cockpit_activate_habitat",
      method: "POST",
      path: "/api/projects/{slug}/go-work-now/actions/activate-habitat",
      description: "Mutate: wake a warm project habitat (scale to 1).",
      idempotency: { header: "X-Request-ID", ttl_ms: 60000 },
      error_codes: ["INVALID_SLUG", "HABITAT_BUSY", "CLUSTER_UNREACHABLE"]
    },
    {
      name: "cockpit_standby_habitat",
      method: "POST",
      path: "/api/projects/{slug}/go-work-now/actions/standby-habitat",
      description: "Mutate: put a project habitat on standby (scale to 0).",
      idempotency: { header: "X-Request-ID", ttl_ms: 60000 }
    },
    {
      name: "cockpit_hpc_profiles",
      method: "GET",
      path: "/api/projects/{slug}/hpc/profiles",
      description: "Approved Darwin HPC workload profiles for this project. Use this before any GPU submission from a workspace."
    },
    {
      name: "cockpit_submit_hpc_job",
      method: "POST",
      path: "/api/projects/{slug}/hpc/jobs/submit",
      description: "Submit a typed Darwin HPC job. Canonical path for GPU and supercomputing work from agent workspaces.",
      idempotency: { header: "X-Request-ID", ttl_ms: 60000 },
      input_schema: {
        type: "object",
        required: ["profile_id"],
        properties: {
          profile_id: {
            type: "string",
            enum: ["cpu-short-v1", "cpu-batch-v1", "gpu-single-v1"]
          },
          parameters: {
            type: "object",
            description: "Darwin HPC profile parameters. `run_label` is required by the upstream contract but Cockpit will synthesize one if omitted."
          },
          run_label: {
            type: "string",
            description: "Optional shorthand for parameters.run_label."
          }
        }
      },
      error_codes: ["INVALID_SLUG", "BAD_REQUEST", "CLUSTER_UNREACHABLE", "TIMEOUT"]
    },
    {
      name: "cockpit_hpc_job_status",
      method: "GET",
      path: "/api/projects/{slug}/hpc/jobs/{job_id}",
      description: "Status of a typed Darwin HPC job."
    },
    {
      name: "cockpit_hpc_job_artifact",
      method: "GET",
      path: "/api/projects/{slug}/hpc/jobs/{job_id}/artifact",
      description: "Fetch the published primary artifact bytes for a Darwin HPC job."
    },
    {
      name: "cockpit_hpc_job_artifact_manifest",
      method: "GET",
      path: "/api/projects/{slug}/hpc/jobs/{job_id}/artifact-manifest",
      description: "Structured artifact manifest for a Darwin HPC job."
    },
    {
      name: "cockpit_hpc_job_stdout",
      method: "GET",
      path: "/api/projects/{slug}/hpc/jobs/{job_id}/stdout",
      description: "Stdout artifact for a Darwin HPC job."
    },
    {
      name: "cockpit_hpc_job_stdout_object",
      method: "GET",
      path: "/api/projects/{slug}/hpc/jobs/{job_id}/stdout-object",
      description: "Fetch the published raw stdout object for a Darwin HPC job."
    },
    {
      name: "cockpit_hpc_job_stderr",
      method: "GET",
      path: "/api/projects/{slug}/hpc/jobs/{job_id}/stderr",
      description: "Stderr artifact for a Darwin HPC job."
    },
    {
      name: "cockpit_hpc_job_stderr_object",
      method: "GET",
      path: "/api/projects/{slug}/hpc/jobs/{job_id}/stderr-object",
      description: "Fetch the published raw stderr object for a Darwin HPC job."
    },
    {
      name: "cockpit_hpc_results",
      method: "GET",
      path: "/api/projects/{slug}/hpc/results",
      description: "Object-backed Darwin HPC result catalog. Accepts optional filters like profile_id, run_label, state, and node_list."
    },
    {
      name: "cockpit_hpc_result",
      method: "GET",
      path: "/api/projects/{slug}/hpc/results/{job_id}",
      description: "Lookup a published Darwin HPC result catalog entry by job id."
    },
    {
      name: "cockpit_hpc_result_manifest",
      method: "GET",
      path: "/api/projects/{slug}/hpc/results/{job_id}/manifest",
      description: "Published object-backed result manifest for a Darwin HPC result."
    },
    {
      name: "cockpit_submit_job",
      method: "POST",
      path: "/api/projects/{slug}/jobs/submit",
      description: "Submit a generic Kubernetes batch Job. Use this for plain cluster batch work, not as the canonical GPU/HPC path.",
      idempotency: { header: "X-Request-ID", ttl_ms: 60000 },
      input_schema: {
        type: "object",
        required: ["command"],
        properties: {
          campaign: { type: "string" },
          image: { type: "string", default: "ttl.sh/beagle-sounio:latest" },
          command: { oneOf: [{ type: "array" }, { type: "string" }] },
          resources: {
            type: "object",
            properties: {
              cpu: { type: "string" },
              memory: { type: "string" },
              gpu: { type: "integer" }
            }
          },
          data_mounts: {
            type: "array",
            items: { type: "string", enum: ["orangefs-training", "hf-cache", "workspace"] }
          },
          timeout_seconds: { type: "integer" },
          kind: { type: "string", enum: ["k8s", "slurm"], default: "k8s" }
        }
      },
      error_codes: ["INVALID_SLUG", "BAD_REQUEST", "CLUSTER_UNREACHABLE"]
    },
    {
      name: "cockpit_job_status",
      method: "GET",
      path: "/api/projects/{slug}/jobs/{job_id}",
      description: "Status of one submitted job (phase, pods, timing)."
    },
    {
      name: "cockpit_jobs_list",
      method: "GET",
      path: "/api/projects/{slug}/jobs",
      description: "List cockpit-submitted jobs for a project."
    },
    {
      name: "cockpit_job_cancel",
      method: "POST",
      path: "/api/projects/{slug}/jobs/{job_id}/cancel",
      description: "Delete a running job (kubectl delete job).",
      idempotency: { header: "X-Request-ID", ttl_ms: 60000 }
    },
    {
      name: "cockpit_jobs_queue",
      method: "GET",
      path: "/api/jobs/queue",
      description: "Unified timeline of compute queue — K8s Jobs + Slurm + Kueue. For iOS Jobs panel."
    },
    {
      name: "cockpit_job_detail",
      method: "GET",
      path: "/api/jobs/{job_id}/detail",
      description: "Deep detail of a job (K8s manifest or Slurm scontrol output)."
    },
    {
      name: "cockpit_beagle_token",
      method: "GET",
      path: "/api/auth/beagle-token",
      description: "Auth bridge — returns operator token + URL for beagle-server (Rust). iOS calls once, caches in Keychain."
    },
    {
      name: "cockpit_beagle_discover",
      method: "GET",
      path: "/api/auth/beagle-discover",
      description: "Full endpoint catalog of beagle-server (Rust). Use to wire up clients."
    },
    {
      name: "sounio_smt_check",
      method: "POST",
      path: "/api/sounio/smt/check",
      description:
        "QF_LIA satisfiability via Sounio's theorem::smt DPLL(T) solver. Returns SAT/UNSAT/UNKNOWN " +
        "for linear-integer constraints (sum coeffs[i]*x_i <= bound). Use to verify a claim-set is " +
        "mutually consistent. UNSAT = constraints provably contradictory (not 'the draft is wrong').",
      input_schema: {
        type: "object",
        required: ["constraints"],
        properties: {
          constraints: {
            type: "array", minItems: 1, maxItems: 64,
            items: {
              type: "object", required: ["coeffs", "bound"],
              properties: {
                coeffs: { type: "array", items: { type: "integer" }, maxItems: 16 },
                bound: { type: "integer" },
                label: { type: "string" }
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
        "GUM (JCGM 100) uncertainty propagation via Sounio's epistemic::gum stdlib. Combines two measured " +
        "quantities under add/sub/mul/div and returns combined standard uncertainty, coverage factor k95, " +
        "expanded uncertainty U95, relative %, and the 95% interval.",
      input_schema: {
        type: "object",
        required: ["inputs", "op"],
        properties: {
          inputs: {
            type: "array", minItems: 2, maxItems: 2,
            items: {
              type: "object", required: ["value", "u"],
              properties: {
                value: { type: "number" }, u: { type: "number" }, label: { type: "string" }
              }
            }
          },
          op: { type: "string", enum: ["add", "sub", "mul", "div"] }
        }
      },
      error_codes: ["BAD_REQUEST", "RUNTIME_UNAVAILABLE", "TIMEOUT", "INTERNAL"]
    },
    {
      name: "sounio_causal_dsep",
      method: "POST",
      path: "/api/sounio/causal/dsep",
      description:
        "d-separation (conditional independence) via Sounio's causal::base Pearl Bayes-ball. Given a DAG, " +
        "X, Y and an optional conditioning set Z, returns whether X _||_ Y | Z holds. Use before any causal " +
        "inference step to confirm assumed independencies / check backdoor closure.",
      input_schema: {
        type: "object",
        required: ["n", "edges", "x", "y"],
        properties: {
          n: { type: "integer", minimum: 1, maximum: 32 },
          edges: { type: "array", items: { type: "array", items: { type: "integer" }, minItems: 2, maxItems: 2 } },
          x: { type: "integer" },
          y: { type: "integer" },
          z: { type: "array", items: { type: "integer" }, maxItems: 32, default: [] }
        }
      },
      error_codes: ["BAD_REQUEST", "RUNTIME_UNAVAILABLE", "TIMEOUT", "INTERNAL"]
    }
  ],
  retry_policy: {
    strategy: "exponential_jitter",
    base_ms: 200,
    max_ms: 5000,
    max_attempts: 5,
    retryable_codes: ["CLUSTER_UNREACHABLE", "RUNTIME_UNAVAILABLE", "RATE_LIMIT", "TIMEOUT", "INTERNAL"]
  },
  observability: {
    truth_propagation: "All GET responses preserve truthMode from their backing source.",
    latency_field: "meta.latency_ms",
    request_id_field: "meta.request_id",
    header: "X-Request-ID (client-supplied for idempotency)"
  },
  components: {
    schemas: {
      Project: {
        type: "object",
        properties: {
          projectSlug: { type: "string" },
          mode: { type: "string", enum: ["always-on", "warm", "cold"] },
          namespace: { type: "string" },
          branch: { type: "string" },
          workspaceBootstrapBranch: { type: "string" },
          preferredPrBase: { type: "string" }
        }
      },
      TruthfulResponse: {
        type: "object",
        description: "Envelope shape for contract-compliant responses.",
        properties: {
          ok: { type: "boolean" },
          data: { type: "object", nullable: true },
          error: {
            type: "object",
            nullable: true,
            properties: {
              code: { type: "string" },
              message: { type: "string" },
              retryable: { type: "boolean" }
            }
          },
          meta: {
            type: "object",
            properties: {
              truthMode: { type: "string", enum: ["observed", "remembered", "declared", "stale"] },
              observedAt: { type: "string", nullable: true },
              latency_ms: { type: "integer" },
              request_id: { type: "string" }
            }
          }
        }
      }
    }
  }
};

// Minimal YAML serializer for our manifest (avoid pulling js-yaml dependency).
// Handles strings, numbers, booleans, arrays, plain objects, nulls.
// Not a full YAML spec — enough for our well-known schema.
function toYaml(value, indent = 0) {
  const pad = "  ".repeat(indent);
  if (value === null || value === undefined) return "null";
  if (typeof value === "string") {
    if (value.includes("\n") || value.match(/[:#\-&*!|>'"{}\[\]]/)) {
      return JSON.stringify(value);
    }
    return value;
  }
  if (typeof value === "number" || typeof value === "boolean") return String(value);
  if (Array.isArray(value)) {
    if (value.length === 0) return "[]";
    return value.map((item) => `${pad}- ${toYamlInline(item, indent + 1)}`).join("\n");
  }
  if (typeof value === "object") {
    const entries = Object.entries(value);
    if (entries.length === 0) return "{}";
    return entries.map(([k, v]) => {
      if (v === null || v === undefined) return `${pad}${k}: null`;
      if (typeof v === "object") {
        return `${pad}${k}:\n${toYaml(v, indent + 1)}`;
      }
      return `${pad}${k}: ${toYaml(v, indent)}`;
    }).join("\n");
  }
  return String(value);
}

function toYamlInline(value, indent) {
  if (value === null || value === undefined) return "null";
  if (typeof value === "string" || typeof value === "number" || typeof value === "boolean") {
    return toYaml(value, indent);
  }
  if (Array.isArray(value) || typeof value === "object") {
    return "\n" + toYaml(value, indent);
  }
  return String(value);
}

export function manifestYaml() {
  return toYaml(cockpitManifest);
}

export function manifestJson() {
  return cockpitManifest;
}

/**
 * Register manifest endpoints on an Express app.
 */
export function registerManifestRoutes(app) {
  app.get("/api/mcp/manifest.json", (_req, res) => {
    res.json(cockpitManifest);
  });

  app.get("/api/mcp/manifest.yaml", (_req, res) => {
    res.type("text/yaml").send(manifestYaml());
  });

  // Convenience: `/api/mcp` redirects to the JSON form for discovery tools
  app.get("/api/mcp", (_req, res) => {
    res.json({
      manifest_json: "/api/mcp/manifest.json",
      manifest_yaml: "/api/mcp/manifest.yaml",
      agent: cockpitManifest.agent,
      version: cockpitManifest.version,
      endpoint_count: cockpitManifest.endpoints.length
    });
  });
}

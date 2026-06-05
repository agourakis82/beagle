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
      name: "cockpit_catalog_audit",
      method: "GET",
      path: "/api/catalog/audit",
      description: "Catalog/posture drift audit. Blocking failures prevent cockpit habitat mutations."
    },
    {
      name: "cockpit_project_control_plane",
      method: "GET",
      path: "/api/projects/{slug}/control-plane",
      description: "Compact per-project control packet: posture, workspace state, branch lease, blockers, safe actions, and agent/job routes.",
      params: [{ name: "slug", in: "path", required: true }]
    },
    {
      name: "cockpit_project_os",
      method: "GET",
      path: "/api/project-os",
      description: "Darwin Project OS packet: posture, workspace, risk, agents, jobs, autopilot proposals, and action ledger counts."
    },
    {
      name: "cockpit_action_ledger_global",
      method: "GET",
      path: "/api/project-os/actions",
      description: "Recent Darwin Action Ledger entries across all cataloged projects. Read-only."
    },
    {
      name: "cockpit_cluster_ops_summary",
      method: "GET",
      path: "/api/cluster/ops/summary",
      description: "Darwin cluster ops summary: Kubernetes, Slurm, OrangeFS, GPU capacity, host freshness, risks, and allowed actions."
    },
    {
      name: "cockpit_cluster_ops_actions",
      method: "GET",
      path: "/api/cluster/ops/actions",
      description: "Allowlisted Darwin cluster actions with risk level and confirmation requirements."
    },
    {
      name: "cockpit_gpu_leases",
      method: "GET",
      path: "/api/cluster/ops/gpu-leases",
      description: "Observed GPU lease/domain state across Kubernetes serving, Slurm gpu-orangefs, and Kueue ResourceFlavor mappings."
    },
    {
      name: "cockpit_project_gpu_leases",
      method: "GET",
      path: "/api/projects/{slug}/gpu-leases",
      description: "Project-scoped GPU lease/domain state. For Sounio this is the official exocortex compute ownership readback.",
      params: [{ name: "slug", in: "path", required: true }]
    },
    {
      name: "cockpit_gpu_lease_preview",
      method: "POST",
      path: "/api/cluster/ops/gpu-leases/{node}/preview",
      description: "Dry-run one GPU lease transition and return the exact Action Ledger proposal required before apply.",
      params: [{ name: "node", in: "path", required: true }],
      idempotency: { header: "X-Request-ID", ttl_ms: 60000 },
      input_schema: {
        type: "object",
        required: ["transition"],
        properties: {
          transition: {
            type: "string",
            enum: ["serving-to-batch", "batch-to-serving", "admit-batch", "quarantine"]
          },
          deployment: { type: "string" }
        }
      }
    },
    {
      name: "cockpit_gpu_lease_apply",
      method: "POST",
      path: "/api/cluster/ops/gpu-leases/{node}/apply",
      description: "Apply one GPU lease transition after confirmed Action Ledger intent; returns command output, receipt, and live readback.",
      params: [{ name: "node", in: "path", required: true }],
      idempotency: { header: "X-Request-ID", ttl_ms: 60000 },
      input_schema: {
        type: "object",
        required: ["transition", "confirmed", "ledgerId"],
        properties: {
          transition: {
            type: "string",
            enum: ["serving-to-batch", "batch-to-serving", "admit-batch", "quarantine"]
          },
          confirmed: { type: "boolean", const: true },
          ledgerId: { type: "string" },
          deployment: { type: "string" }
        }
      },
      error_codes: ["BAD_REQUEST", "NOT_FOUND", "CONFLICT", "TIMEOUT", "INTERNAL"]
    },
    {
      name: "cockpit_cluster_ops_action_run",
      method: "POST",
      path: "/api/cluster/ops/actions/{action_id}/run",
      description: "Execute one allowlisted cluster action after Action Ledger intent confirmation and return receipt plus readback.",
      params: [{ name: "action_id", in: "path", required: true }],
      idempotency: { header: "X-Request-ID", ttl_ms: 60000 },
      input_schema: {
        type: "object",
        required: ["confirmed", "ledgerId"],
        properties: {
          confirmed: { type: "boolean", const: true },
          ledgerId: { type: "string" },
          targetNode: { type: "string", enum: ["r770-proxmox", "5860-proxmox", "r740-proxmox"] }
        }
      },
      error_codes: ["BAD_REQUEST", "NOT_FOUND", "CONFLICT", "TIMEOUT", "INTERNAL"]
    },
    {
      name: "cockpit_action_ledger_project",
      method: "GET",
      path: "/api/projects/{slug}/actions",
      description: "Recent Action Ledger entries for one project.",
      params: [{ name: "slug", in: "path", required: true }]
    },
    {
      name: "cockpit_action_ledger_propose",
      method: "POST",
      path: "/api/projects/{slug}/actions/propose",
      description: "Record an autopilot or agent proposal. This never executes the proposed action.",
      idempotency: { header: "X-Request-ID", ttl_ms: 60000 }
    },
    {
      name: "cockpit_action_ledger_confirm_intent",
      method: "POST",
      path: "/api/projects/{slug}/actions/{ledger_id}/confirm-intent",
      description: "Record human/operator intent and return control-plane readback. This does not execute cluster, agent, habitat, or job mutations.",
      idempotency: { header: "X-Request-ID", ttl_ms: 60000 }
    },
    {
      name: "cockpit_action_ledger_reject",
      method: "POST",
      path: "/api/projects/{slug}/actions/{ledger_id}/reject",
      description: "Record rejection of an Action Ledger proposal. This never executes the proposed action.",
      idempotency: { header: "X-Request-ID", ttl_ms: 60000 }
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
      name: "cockpit_foundry_runs",
      method: "GET",
      path: "/api/projects/{slug}/foundry/runs",
      description: "Recent Sounio Compiler Foundry runs read from the Cockpit read-only OrangeFS mount.",
      params: [{ name: "slug", in: "path", required: true }]
    },
    {
      name: "cockpit_foundry_run_summary",
      method: "GET",
      path: "/api/projects/{slug}/foundry/runs/{run_id}/summary",
      description: "Structured summary, run packet, and artifact paths for one Sounio Compiler Foundry run.",
      params: [
        { name: "slug", in: "path", required: true },
        { name: "run_id", in: "path", required: true }
      ]
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
      input_schema: {
        type: "object",
        required: ["confirmed"],
        properties: {
          confirmed: { type: "boolean", const: true },
          idempotencyKey: { type: "string" }
        }
      },
      error_codes: ["INVALID_SLUG", "HABITAT_BUSY", "CLUSTER_UNREACHABLE"]
    },
    {
      name: "cockpit_standby_habitat",
      method: "POST",
      path: "/api/projects/{slug}/go-work-now/actions/standby-habitat",
      description: "Mutate: put a project habitat on standby (scale to 0).",
      idempotency: { header: "X-Request-ID", ttl_ms: 60000 },
      input_schema: {
        type: "object",
        required: ["confirmed"],
        properties: {
          confirmed: { type: "boolean", const: true },
          idempotencyKey: { type: "string" }
        }
      }
    },
    {
      name: "cockpit_submit_job",
      method: "POST",
      path: "/api/projects/{slug}/jobs/submit",
      description: "Submit batch job (K8s Job). Canonical escalation path from agent workspaces — never handcraft YAML.",
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
      name: "workbench_context_connect",
      method: "GET",
      path: "/api/workbench/{slug}/context/connect",
      description: "Client connection pack for Claude Desktop, ChatGPT, Grok, Codex, Kimi, and local zellij agents.",
      params: [{ name: "slug", in: "path", required: true }]
    },
    {
      name: "workbench_context_status",
      method: "GET",
      path: "/api/workbench/{slug}/context/status",
      description: "Workbench shared MCP/RAG++ status, feature flags, client registry, and local memory counts.",
      params: [{ name: "slug", in: "path", required: true }]
    },
    {
      name: "workbench_context_doctor",
      method: "POST",
      path: "/api/workbench/{slug}/context/doctor",
      description: "Operational doctor for Workbench Context. With write_probe=true, verifies storage, Beagle auth/write-through, RAG++ readback, GraphRAG, and compiler.",
      params: [{ name: "slug", in: "path", required: true }],
      input_schema: {
        type: "object",
        properties: {
          write_probe: { type: "boolean", default: false },
          query: { type: "string" },
          sentinel: { type: "string" }
        }
      }
    },
    {
      name: "workbench_context_clients",
      method: "GET",
      path: "/api/workbench/{slug}/context/clients",
      description: "Known and observed context clients: Claude Desktop, ChatGPT, Grok, Codex, Kimi, and local zellij agents.",
      params: [{ name: "slug", in: "path", required: true }]
    },
    {
      name: "workbench_context_sessions",
      method: "GET",
      path: "/api/workbench/{slug}/context/sessions",
      description: "Observed shared-memory sessions in the Workbench context overlay.",
      params: [{ name: "slug", in: "path", required: true }]
    },
    {
      name: "workbench_context_audit",
      method: "GET",
      path: "/api/workbench/{slug}/context/audit",
      description: "Audit summary for Workbench shared memory: records, sources, clients, sessions, tags, and risks.",
      params: [{ name: "slug", in: "path", required: true }]
    },
    {
      name: "workbench_context_audit_events",
      method: "GET",
      path: "/api/workbench/{slug}/context/audit/events",
      description: "Recent Workbench context ingest/import audit events.",
      params: [{ name: "slug", in: "path", required: true }]
    },
    {
      name: "workbench_context_recent",
      method: "GET",
      path: "/api/workbench/{slug}/context/recent",
      description: "Recent Workbench context records with optional source/session/tag filters.",
      params: [{ name: "slug", in: "path", required: true }]
    },
    {
      name: "workbench_context_messages",
      method: "GET",
      path: "/api/workbench/{slug}/context/messages",
      description: "List agent handoff messages persisted in the Workbench context mesh.",
      params: [{ name: "slug", in: "path", required: true }]
    },
    {
      name: "workbench_context_message_board",
      method: "GET",
      path: "/api/workbench/{slug}/context/messages/board",
      description: "Coordination board for agent handoffs: waiting, active, done, stale, per-client counts, and next actions.",
      params: [{ name: "slug", in: "path", required: true }]
    },
    {
      name: "workbench_context_presence",
      method: "GET",
      path: "/api/workbench/{slug}/context/presence",
      description: "Operational presence for MCP clients and agents: active, waiting, stale, idle, declared, plus handoff load.",
      params: [{ name: "slug", in: "path", required: true }]
    },
    {
      name: "workbench_context_client_heartbeat",
      method: "POST",
      path: "/api/workbench/{slug}/context/clients/{client_id}/heartbeat",
      description: "Mark a subscription/MCP client as live without creating a handoff reply. Keeps ChatGPT, Claude Desktop, Grok, Kimi, Codex, or local agents realtime-ready.",
      params: [
        { name: "slug", in: "path", required: true },
        { name: "client_id", in: "path", required: true }
      ],
      input_schema: {
        type: "object",
        properties: {
          provider: { type: "string" },
          session_id: { type: "string" },
          status: { type: "string" },
          note: { type: "string" },
          tags: { type: "array", items: { type: "string" } },
          metadata: { type: "object" }
        }
      }
    },
    {
      name: "workbench_context_continuity",
      method: "GET",
      path: "/api/workbench/{slug}/context/continuity",
      description: "Continuity packet for resuming agent work without losing context: status, presence, open handoffs, next actions, recent memories, and resume brief.",
      params: [{ name: "slug", in: "path", required: true }]
    },
    {
      name: "workbench_context_message_inbox",
      method: "GET",
      path: "/api/workbench/{slug}/context/messages/inbox/{client_id}",
      description: "List handoff messages for a specific client or agent.",
      params: [
        { name: "slug", in: "path", required: true },
        { name: "client_id", in: "path", required: true }
      ]
    },
    {
      name: "workbench_context_message_send",
      method: "POST",
      path: "/api/workbench/{slug}/context/messages/send",
      description: "Send a handoff message from one agent/client to another through the shared context mesh.",
      params: [{ name: "slug", in: "path", required: true }]
    },
    {
      name: "workbench_context_message_ack",
      method: "POST",
      path: "/api/workbench/{slug}/context/messages/{message_id}/ack",
      description: "Acknowledge a handoff message from an agent/client.",
      params: [
        { name: "slug", in: "path", required: true },
        { name: "message_id", in: "path", required: true }
      ]
    },
    {
      name: "workbench_context_message_compile",
      method: "POST",
      path: "/api/workbench/{slug}/context/messages/{message_id}/compile",
      description: "Compile a handoff message into an actionable context packet with thread, ACKs, RAG++ highlights, graph, and plain text context.",
      params: [
        { name: "slug", in: "path", required: true },
        { name: "message_id", in: "path", required: true }
      ]
    },
    {
      name: "workbench_context_message_claim",
      method: "POST",
      path: "/api/workbench/{slug}/context/messages/{message_id}/claim",
      description: "Claim a handoff message before starting work so other agents can see ownership.",
      params: [
        { name: "slug", in: "path", required: true },
        { name: "message_id", in: "path", required: true }
      ]
    },
    {
      name: "workbench_context_message_complete",
      method: "POST",
      path: "/api/workbench/{slug}/context/messages/{message_id}/complete",
      description: "Mark a handoff message complete with a result summary and optional artifact refs.",
      params: [
        { name: "slug", in: "path", required: true },
        { name: "message_id", in: "path", required: true }
      ]
    },
    {
      name: "workbench_context_message_release",
      method: "POST",
      path: "/api/workbench/{slug}/context/messages/{message_id}/release",
      description: "Release a claimed handoff so another agent can take it.",
      params: [
        { name: "slug", in: "path", required: true },
        { name: "message_id", in: "path", required: true }
      ]
    },
    {
      name: "workbench_context_message_cancel",
      method: "POST",
      path: "/api/workbench/{slug}/context/messages/{message_id}/cancel",
      description: "Cancel a handoff that should no longer be worked.",
      params: [
        { name: "slug", in: "path", required: true },
        { name: "message_id", in: "path", required: true }
      ]
    },
    {
      name: "workbench_context_message_reopen",
      method: "POST",
      path: "/api/workbench/{slug}/context/messages/{message_id}/reopen",
      description: "Reopen a completed or canceled handoff and return it to the waiting queue.",
      params: [
        { name: "slug", in: "path", required: true },
        { name: "message_id", in: "path", required: true }
      ]
    },
    {
      name: "workbench_context_message_heartbeat",
      method: "POST",
      path: "/api/workbench/{slug}/context/messages/{message_id}/heartbeat",
      description: "Record progress on a claimed handoff without completing it.",
      params: [
        { name: "slug", in: "path", required: true },
        { name: "message_id", in: "path", required: true }
      ]
    },
    {
      name: "workbench_context_mcp_tools",
      method: "GET",
      path: "/api/workbench/{slug}/context/mcp/tools",
      description: "Tool list for the Workbench Context HTTP MCP server.",
      params: [{ name: "slug", in: "path", required: true }]
    },
    {
      name: "workbench_context_http_mcp",
      method: "POST",
      path: "/api/workbench/{slug}/context/mcp",
      description: "HTTP JSON-RPC MCP endpoint for Workbench Context tools. Supports initialize, tools/list, tools/call, ping.",
      params: [{ name: "slug", in: "path", required: true }]
    },
    {
      name: "workbench_http_mcp",
      method: "POST",
      path: "/api/workbench/{slug}/mcp",
      description: "Short alias for the Workbench Context HTTP JSON-RPC MCP endpoint.",
      params: [{ name: "slug", in: "path", required: true }]
    },
    {
      name: "workbench_context_ingest",
      method: "POST",
      path: "/api/workbench/{slug}/context/ingest",
      description: "Ingest one MCP/chat turn batch into the Workbench shared memory overlay and write through to Beagle Core.",
      params: [{ name: "slug", in: "path", required: true }],
      idempotency: { header: "X-Request-ID", ttl_ms: 60000 },
      input_schema: {
        type: "object",
        properties: {
          source: { type: "string" },
          provider: { type: "string" },
          client_id: { type: "string" },
          session_id: { type: "string" },
          conversation_id: { type: "string" },
          turns: {
            type: "array",
            items: {
              type: "object",
              required: ["content"],
              properties: {
                role: { type: "string", enum: ["user", "assistant", "system", "tool"] },
                content: { type: "string" },
                external_id: { type: "string" }
              }
            }
          },
          tags: { type: "array", items: { type: "string" } },
          metadata: { type: "object", additionalProperties: true }
        }
      }
    },
    {
      name: "workbench_context_import",
      method: "POST",
      path: "/api/workbench/{slug}/context/import",
      description: "Bulk import MCP/chat conversation items into the Workbench context overlay with duplicate suppression.",
      params: [{ name: "slug", in: "path", required: true }],
      idempotency: { header: "X-Request-ID", ttl_ms: 60000 }
    },
    {
      name: "workbench_context_query",
      method: "POST",
      path: "/api/workbench/{slug}/context/query",
      description: "RAG++ readback over local read-after-write overlay plus Beagle Core memory.",
      params: [{ name: "slug", in: "path", required: true }]
    },
    {
      name: "workbench_context_graphrag_query",
      method: "POST",
      path: "/api/workbench/{slug}/context/graphrag/query",
      description: "Bounded GraphRAG projection from retrieved Workbench/Beagle memory.",
      params: [{ name: "slug", in: "path", required: true }]
    },
    {
      name: "workbench_context_compile",
      method: "POST",
      path: "/api/workbench/{slug}/context/compiler/compile",
      description: "Compile the retrieved context and bounded graph into an agent handoff packet.",
      params: [{ name: "slug", in: "path", required: true }]
    },
    {
      name: "workbench_context_export",
      method: "GET",
      path: "/api/workbench/{slug}/context/export",
      description: "Export recent Workbench context records for inspection or migration.",
      params: [{ name: "slug", in: "path", required: true }]
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

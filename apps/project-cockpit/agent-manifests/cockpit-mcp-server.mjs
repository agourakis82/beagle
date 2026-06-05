#!/usr/bin/env node
// cockpit-mcp-server.mjs
//
// Minimal MCP stdio server that proxies the cockpit HTTP API as tools.
// Runs INSIDE the agent pod. The agent (Claude Code, Codex, etc.) spawns
// this via mcp.json, reads tool definitions, and invokes them over stdio.
//
// All tools preserve truthMode and return real cockpit data — the agent
// "sees" the cluster through the same epistemic lens as the human operator.
//
// Protocol: MCP 2024-11-05 (JSON-RPC over stdio).
//
// Config via env:
//   COCKPIT_API      — base URL for cockpit API (required)
//   COCKPIT_PROJECT  — default project slug (required)
//
// Tools exposed:
//   cockpit_catalog             — list all sovereign projects + postures
//   cockpit_mission_control     — full mission control for a project
//   cockpit_cluster_truth       — cluster lane truth
//   cockpit_research_latest     — latest research operation (ABIDE etc.)
//   cockpit_inference_runtime   — SGLang + Dynamo state + models
//   cockpit_model_registry      — approved model lanes, routing, and policy
//   cockpit_viewer_runtime      — WebGPU viewer state
//   cockpit_agent_sessions      — list active agent sessions in this project
//   cockpit_action_ledger       — list proposed/confirmed/rejected actions
//   cockpit_workbench_context_* — shared MCP/RAG++ memory for Claude, ChatGPT, Grok, Codex, Kimi
//   cockpit_propose_action      — propose a human-reviewed action
//   cockpit_activate_habitat    — mutate: wake a warm habitat
//   cockpit_standby_habitat     — mutate: pause a warm habitat

import { createInterface } from "node:readline";
import { setTimeout as delay } from "node:timers/promises";

const API = process.env.COCKPIT_API || "http://project-cockpit.beagle.svc.cluster.local";
const PROJECT = process.env.COCKPIT_PROJECT || "sounio";
const SERVER_NAME = "cockpit-mcp";
const SERVER_VERSION = "0.1.0";

// ─── HTTP helpers ──────────────────────────────────────────────────────

async function apiGet(path, timeoutMs = 6000, options = {}) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const headers = { ...(options.headers || {}) };
    if (options.auth === true) {
      headers.authorization = `Bearer ${await getBeagleToken()}`;
    }
    const res = await fetch(`${API}${path}`, { headers, signal: ctrl.signal });
    if (!res.ok) return { error: `HTTP ${res.status}`, truthMode: "stale" };
    return await res.json();
  } catch (e) {
    return { error: e.message, truthMode: "stale" };
  } finally {
    clearTimeout(t);
  }
}

async function apiPost(path, body, timeoutMs = 10000, options = {}) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const headers = {
      "content-type": "application/json",
      ...(options.headers || {})
    };
    if (options.auth === true) {
      headers.authorization = `Bearer ${await getBeagleToken()}`;
    }
    const res = await fetch(`${API}${path}`, {
      method: "POST",
      headers,
      body: JSON.stringify(body ?? {}),
      signal: ctrl.signal
    });
    const data = await res.json().catch(() => ({ ok: res.ok }));
    return res.ok ? data : { error: `HTTP ${res.status}`, ...data };
  } catch (e) {
    return { error: e.message };
  } finally {
    clearTimeout(t);
  }
}

// ─── Beagle-core helpers ───────────────────────────────────────────────
//
// The cognitive endpoints live on beagle-core, not cockpit. They require
// X-Beagle-Consumer + Authorization: Bearer. We fetch the token via the
// cockpit auth bridge (same host, no auth needed for the bridge itself)
// and cache it for 4 minutes (bridge TTL is 5 minutes).

const BEAGLE_URL =
  process.env.BEAGLE_URL ||
  process.env.PROJECT_COCKPIT_BEAGLE_URL ||
  "http://beagle-core.beagle.svc.cluster.local:8080";
// Dedicated auth-bridge service (replaces cockpit's auth-bridge for new
// deployments). Opt-in via AUTH_BRIDGE_URL env — cockpit's in-process
// bridge remains the default because the debian-based agent pod has a
// flaky pthread DNS resolver that sometimes drops outbound requests to
// new cluster services under abort-timeout.
const AUTH_BRIDGE_URL = process.env.AUTH_BRIDGE_URL || "";
const BEAGLE_CONSUMER = process.env.BEAGLE_CONSUMER || "beagle-operator";
const BEAGLE_PROXY_PATH = process.env.BEAGLE_PROXY_PATH || "/api/beagle";

let _tok = null;
let _tokFetchedAt = 0;
const TOKEN_TTL_MS = 4 * 60 * 1000;
// Dedupe key for the auto-feedback noisy-pattern loop. One feedback
// event per (tool_name × 10-call bucket) at most, so we don't spam the
// feedback registry with the same observation every tool call.
let _noisyAlerted = null;

async function getBeagleToken() {
  if (_tok && Date.now() - _tokFetchedAt < TOKEN_TTL_MS) return _tok;
  // Try the dedicated auth-bridge first (only if AUTH_BRIDGE_URL is set);
  // fall back to cockpit's bridge (the known-good path).
  let bridge;
  if (AUTH_BRIDGE_URL) {
    bridge = await fetchJson(`${AUTH_BRIDGE_URL}/api/auth/beagle-token`, 5000);
  }
  if (!bridge?.token) {
    bridge = await apiGet("/api/auth/beagle-token");
  }
  if (bridge?.error || !bridge?.token) {
    throw new Error(`beagle-token bridge failed: ${bridge?.error || "no token"}`);
  }
  _tok = bridge.token;
  _tokFetchedAt = Date.now();
  return _tok;
}

async function fetchJson(url, timeoutMs = 5000) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const res = await fetch(url, { signal: ctrl.signal });
    if (!res.ok) return { error: `HTTP ${res.status}` };
    return await res.json();
  } catch (e) {
    return { error: e.message };
  } finally {
    clearTimeout(t);
  }
}

async function beagleGet(path, timeoutMs = 10000) {
  const direct = await beagleGetDirect(path, timeoutMs);
  if (!shouldFallbackToCockpitProxy(direct)) {
    return direct;
  }
  const fallback = await apiGet(`${BEAGLE_PROXY_PATH}${path}`, timeoutMs);
  return mergeBeagleFallbackResult(direct, fallback);
}

async function beaglePost(path, body, timeoutMs = 120000) {
  const direct = await beaglePostDirect(path, body, timeoutMs);
  if (!shouldFallbackToCockpitProxy(direct)) {
    return direct;
  }
  const fallback = await apiPost(`${BEAGLE_PROXY_PATH}${path}`, body, timeoutMs);
  return mergeBeagleFallbackResult(direct, fallback);
}

async function beagleGetDirect(path, timeoutMs = 10000) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const token = await getBeagleToken();
    const res = await fetch(`${BEAGLE_URL}${path}`, {
      signal: ctrl.signal,
      headers: {
        "X-Beagle-Consumer": BEAGLE_CONSUMER,
        Authorization: `Bearer ${token}`
      }
    });
    const data = await res.json().catch(() => ({}));
    return res.ok ? data : { error: `HTTP ${res.status}`, ...data };
  } catch (e) {
    return { error: e.message, truthMode: "stale" };
  } finally {
    clearTimeout(t);
  }
}

async function beaglePostDirect(path, body, timeoutMs = 120000) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const token = await getBeagleToken();
    const res = await fetch(`${BEAGLE_URL}${path}`, {
      method: "POST",
      signal: ctrl.signal,
      headers: {
        "content-type": "application/json",
        "X-Beagle-Consumer": BEAGLE_CONSUMER,
        Authorization: `Bearer ${token}`
      },
      body: JSON.stringify(body ?? {})
    });
    const data = await res.json().catch(() => ({ ok: res.ok }));
    return res.ok ? data : { error: `HTTP ${res.status}`, ...data };
  } catch (e) {
    return { error: e.message, truthMode: "stale" };
  } finally {
    clearTimeout(t);
  }
}

function shouldFallbackToCockpitProxy(result) {
  if (!result?.error) {
    return false;
  }
  const error = String(result.error || "");
  return (
    result.truthMode === "stale" ||
    /^HTTP 5\d\d/.test(error) ||
    error === "fetch failed" ||
    error === "This operation was aborted" ||
    error.includes("timed out") ||
    error.includes("ECONN") ||
    error.includes("ENOTFOUND") ||
    error.includes("network") ||
    error.includes("socket")
  );
}

function mergeBeagleFallbackResult(direct, fallback) {
  if (!fallback || typeof fallback !== "object" || Array.isArray(fallback)) {
    return fallback;
  }
  return {
    ...fallback,
    fallback_from: direct?.error || "",
    transport: fallback?.transport || "cockpit-beagle-proxy"
  };
}

// ─── Tool registry ─────────────────────────────────────────────────────

const TOOLS = [
  {
    name: "cockpit_catalog",
    description: "List all sovereign projects with their postures (always-on / warm / cold) and current state. Returns truthMode indicating if data is observed, remembered, or declared.",
    inputSchema: { type: "object", properties: {} }
  },
  {
    name: "cockpit_whereami",
    description: "Return the agent's operating map: live workspace authority, isolated agent pod boundary, inference fabric status, GPU lease intent, and next safe commands.",
    inputSchema: {
      type: "object",
      properties: {
        project: { type: "string", description: "Project slug (default: current project)" }
      }
    }
  },
  {
    name: "cockpit_mission_control",
    description: "Get the full mission control packet for a project — workspace habitat, branch, namespace, execution packets, truth summary.",
    inputSchema: {
      type: "object",
      properties: {
        project: { type: "string", description: "Project slug (default: current project)" }
      }
    }
  },
  {
    name: "cockpit_cluster_truth",
    description: "Get cluster lane truth — node health, GPU allocation, OrangeFS state, autoheal metrics. Infrastructure-shaped, not research-shaped.",
    inputSchema: {
      type: "object",
      properties: {
        project: { type: "string" }
      }
    }
  },
  {
    name: "cockpit_research_latest",
    description: "Get the latest observed research operation (ABIDE campaign, training run, etc.). Run-shaped, ephemeral.",
    inputSchema: {
      type: "object",
      properties: {
        project: { type: "string" }
      }
    }
  },
  {
    name: "cockpit_foundry_latest",
    description: "List recent Sounio Compiler Foundry runs and their observed artifact status. Reads Cockpit's read-only OrangeFS mount, not the workspace.",
    inputSchema: {
      type: "object",
      properties: {
        project: { type: "string" },
        limit: { type: "integer", minimum: 1, maximum: 100, default: 12 }
      }
    }
  },
  {
    name: "cockpit_foundry_summary",
    description: "Read a Sounio Compiler Foundry run summary, including CPU/GPU summaries, run packet, and artifact paths. This is the canonical agent path for reporting Foundry artifacts.",
    inputSchema: {
      type: "object",
      required: ["run_id"],
      properties: {
        project: { type: "string" },
        run_id: { type: "string", description: "Foundry run id, for example sounio-20260523T154804Z-4f5a85" }
      }
    }
  },
  {
    name: "cockpit_inference_runtime",
    description: "Get inference fabric state — SGLang engine status, Dynamo control plane, available models, endpoints.",
    inputSchema: {
      type: "object",
      properties: {
        project: { type: "string" }
      }
    }
  },
  {
    name: "cockpit_model_registry",
    description: "Get the Project Cockpit model registry: always-on/helper/audit/research/domain/operator lanes, live reachability, GPU/VRAM evidence, last probe, routing rules, and operator policy. Agents should call this before choosing or trusting a model lane.",
    inputSchema: {
      type: "object",
      properties: {
        project: { type: "string" }
      }
    }
  },
  {
    name: "cockpit_viewer_runtime",
    description: "Get scientific viewer runtime — WebGPU renderer state, platform matrix (web/iOS/VisionOS/macOS).",
    inputSchema: {
      type: "object",
      properties: {
        project: { type: "string" }
      }
    }
  },
  {
    name: "cockpit_agent_sessions",
    description: "List active agent sessions (Claude Code, Codex, local-sglang pods) for a project.",
    inputSchema: {
      type: "object",
      properties: {
        project: { type: "string" }
      }
    }
  },
  {
    name: "cockpit_action_ledger",
    description: "List the Cockpit action ledger for a project. Agents should consult this before proposing or touching any cluster/workspace mutation.",
    inputSchema: {
      type: "object",
      properties: {
        project: { type: "string" },
        limit: { type: "integer", minimum: 1, maximum: 100, default: 20 }
      }
    }
  },
  {
    name: "cockpit_propose_action",
    description: "Create a propose-only action ledger entry for human review. Use this instead of emitting raw mutation commands when cluster/workspace changes may be needed.",
    inputSchema: {
      type: "object",
      required: ["summary"],
      properties: {
        project: { type: "string" },
        summary: { type: "string" },
        action_type: { type: "string", description: "Short action family, e.g. rbac-review, rollout, node-maintenance." },
        risk: { type: "string", enum: ["low", "medium", "high"], default: "medium" },
        reason: { type: "string" },
        evidence: { type: "object", additionalProperties: true }
      }
    }
  },
  {
    name: "cockpit_activate_habitat",
    description: "Mutate: activate a warm project habitat (scale workspace StatefulSet to 1). Only use when user explicitly wants to wake a project.",
    inputSchema: {
      type: "object",
      properties: {
        project: { type: "string", description: "Project slug to activate" }
      },
      required: ["project"]
    }
  },
  {
    name: "cockpit_standby_habitat",
    description: "Mutate: put a project habitat on standby (scale to 0). Preserves PVC. Only use when user explicitly requests standby.",
    inputSchema: {
      type: "object",
      properties: {
        project: { type: "string" }
      },
      required: ["project"]
    }
  },
  {
    name: "cockpit_submit_job",
    description: "Submit a batch job to the cluster (K8s Job with correct tolerations, runtime class, and GPU allocation). Canonical escalation path for agents running in workspace pods — do NOT handcraft k8s YAML. Pass `preset` for a named template (sounio-test-suite, sounio-stdlib-gate, sounio-compile-example) and omit command/image — any field you DO pass overrides the preset. Returns a short job_id to poll with cockpit_job_status.",
    inputSchema: {
      type: "object",
      properties: {
        project: { type: "string", description: "Project slug (defaults to current)" },
        preset: {
          type: "string",
          enum: ["sounio-test-suite", "sounio-stdlib-gate", "sounio-compile-example"],
          description: "Named job template. Supplies image + command + mounts + resources. Any explicit field in this call overrides the preset default."
        },
        campaign: { type: "string", description: "Campaign or job group name (e.g. brain-ossm-abide)" },
        image: { type: "string", description: "Container image. Default: ttl.sh/beagle-sounio:latest" },
        command: {
          oneOf: [
            { type: "array", items: { type: "string" } },
            { type: "string", description: "Shell one-liner" }
          ],
          description: "Command array (preferred) or shell string"
        },
        resources: {
          type: "object",
          properties: {
            cpu: { type: "string", description: "e.g. '4' or '2000m'", default: "2" },
            memory: { type: "string", description: "e.g. '16Gi'", default: "8Gi" },
            gpu: { type: "integer", description: "Number of NVIDIA GPUs. Triggers runtimeClass+tolerations when >0", default: 0 }
          }
        },
        data_mounts: {
          type: "array",
          items: { type: "string", enum: ["orangefs-training", "hf-cache", "workspace", "work-tmp"] },
          description: "Shared data mounts. 'orangefs-training' mounts /orangefs for ABIDE-style campaigns."
        },
        timeout_seconds: { type: "integer", default: 3600 },
        kind: { type: "string", enum: ["k8s", "slurm"], default: "k8s", description: "k8s: native K8s Job (default). slurm: via Slinky (not yet wired)." }
      }
    }
  },
  {
    name: "cockpit_job_status",
    description: "Poll status of a submitted job. Returns phase (Pending/Running/Succeeded/Failed), pod list, and timing.",
    inputSchema: {
      type: "object",
      required: ["job_id"],
      properties: {
        project: { type: "string" },
        job_id: { type: "string", description: "Short job ID from cockpit_submit_job" }
      }
    }
  },
  {
    name: "cockpit_jobs_list",
    description: "List recent jobs submitted by the cockpit for a project.",
    inputSchema: {
      type: "object",
      properties: {
        project: { type: "string" }
      }
    }
  },
  {
    name: "cockpit_job_cancel",
    description: "Cancel a running job (kubectl delete job). Non-reversible — the job is gone, but outputs already written to OrangeFS persist.",
    inputSchema: {
      type: "object",
      required: ["job_id"],
      properties: {
        project: { type: "string" },
        job_id: { type: "string" }
      }
    }
  },

  // ─── Workbench shared context (MCP + RAG++ + bounded GraphRAG) ───────

  {
    name: "cockpit_workbench_context_status",
    description: "Get the Workbench shared context status: read-after-write memory overlay, Beagle Core write-through, observed clients, sessions, and endpoint contract.",
    inputSchema: {
      type: "object",
      properties: {
        project: { type: "string", description: "Project slug (defaults to current)" }
      }
    }
  },
  {
    name: "cockpit_workbench_context_doctor",
    description: "Run Workbench shared context diagnostics. Non-mutating by default; set write_probe=true to verify ingest, read-after-write RAG++, GraphRAG, and compiler.",
    inputSchema: {
      type: "object",
      properties: {
        project: { type: "string", description: "Project slug (defaults to current)" },
        write_probe: { type: "boolean", default: false },
        query: { type: "string" },
        sentinel: { type: "string" }
      }
    }
  },
  {
    name: "cockpit_workbench_context_audit",
    description: "Audit shared memory for the current workbench: sources, providers, clients, sessions, tags, and risks. Use this before claiming Claude/ChatGPT/Grok/Codex/Kimi memory is wired.",
    inputSchema: {
      type: "object",
      properties: {
        project: { type: "string", description: "Project slug (defaults to current)" }
      }
    }
  },
  {
    name: "cockpit_workbench_context_presence",
    description: "Return operational presence for MCP clients and agents: active, waiting, stale, idle, declared, plus handoff load.",
    inputSchema: {
      type: "object",
      properties: {
        project: { type: "string", description: "Project slug (defaults to current)" },
        stale_after_minutes: { type: "integer", minimum: 5, maximum: 1440, default: 90 },
        limit: { type: "integer", minimum: 1, maximum: 500, default: 200 }
      }
    }
  },
  {
    name: "cockpit_workbench_context_client_heartbeat",
    description: "Mark this MCP/subscription client as live without replying to a handoff. Use as a keepalive so the Workbench can route realtime multimodel chat to Claude Desktop, ChatGPT, Grok, Kimi, Codex, or local agents.",
    inputSchema: {
      type: "object",
      required: ["client_id"],
      properties: {
        project: { type: "string", description: "Project slug (defaults to current)" },
        client_id: { type: "string" },
        provider: { type: "string" },
        session_id: { type: "string" },
        status: { type: "string", default: "online" },
        note: { type: "string" },
        tags: { type: "array", items: { type: "string" } },
        metadata: { type: "object", additionalProperties: true }
      }
    }
  },
  {
    name: "cockpit_workbench_context_continuity",
    description: "Compile a continuity packet so a new agent can resume without losing context: status, presence, open handoffs, next actions, recent memories, and resume brief.",
    inputSchema: {
      type: "object",
      properties: {
        project: { type: "string", description: "Project slug (defaults to current)" },
        limit: { type: "integer", minimum: 1, maximum: 120, default: 40 },
        handoff_limit: { type: "integer", minimum: 1, maximum: 100, default: 24 },
        recent_limit: { type: "integer", minimum: 1, maximum: 100, default: 12 },
        stale_after_minutes: { type: "integer", minimum: 5, maximum: 1440, default: 90 }
      }
    }
  },
  {
    name: "cockpit_workbench_context_ingest",
    description: "Write turns into the shared Workbench memory bus. This is the canonical MCP write path for Claude Desktop, ChatGPT, Grok, Codex, Kimi, and local zellij agents. It stores locally with read-after-write and writes through to Beagle Core memory.",
    inputSchema: {
      type: "object",
      required: ["turns"],
      properties: {
        project: { type: "string", description: "Project slug (defaults to current)" },
        source: { type: "string", description: "Client/source name, e.g. claude-desktop, chatgpt, grok, codex, kimi-cli" },
        provider: { type: "string", description: "Provider family, e.g. anthropic, openai, xai, moonshot" },
        client_id: { type: "string" },
        session_id: { type: "string" },
        conversation_id: { type: "string" },
        tags: { type: "array", items: { type: "string" } },
        metadata: { type: "object", additionalProperties: true },
        turns: {
          type: "array",
          items: {
            type: "object",
            required: ["content"],
            properties: {
              role: { type: "string", enum: ["user", "assistant", "system", "tool"], default: "user" },
              content: { type: "string" },
              external_id: { type: "string" },
              model: { type: "string" }
            }
          }
        }
      }
    }
  },
  {
    name: "cockpit_workbench_context_query",
    description: "Query shared Workbench memory with RAG++ readback. Searches the local read-after-write overlay first, then Beagle Core memory, and returns a bounded graph projection.",
    inputSchema: {
      type: "object",
      required: ["query"],
      properties: {
        project: { type: "string", description: "Project slug (defaults to current)" },
        query: { type: "string" },
        limit: { type: "integer", minimum: 1, maximum: 30, default: 8 },
        source: { type: "string" },
        session_id: { type: "string" },
        tags: { type: "array", items: { type: "string" } }
      }
    }
  },
  {
    name: "cockpit_workbench_context_graphrag",
    description: "Run the bounded GraphRAG projection over shared Workbench memory and Beagle memory highlights. Returns graph nodes/edges plus supporting memories.",
    inputSchema: {
      type: "object",
      required: ["query"],
      properties: {
        project: { type: "string", description: "Project slug (defaults to current)" },
        query: { type: "string" },
        limit: { type: "integer", minimum: 1, maximum: 30, default: 8 },
        query_mode: { type: "string", default: "local" }
      }
    }
  },
  {
    name: "cockpit_workbench_context_compile",
    description: "Compile shared Workbench context into a compact agent handoff packet: top memories, bounded graph, and plain text context.",
    inputSchema: {
      type: "object",
      required: ["query"],
      properties: {
        project: { type: "string", description: "Project slug (defaults to current)" },
        query: { type: "string" },
        task_profile: { type: "string", default: "analysis" },
        tool_id: { type: "string", default: "mcp-agent" },
        max_items: { type: "integer", minimum: 1, maximum: 30, default: 8 }
      }
    }
  },
  {
    name: "cockpit_workbench_context_import",
    description: "Bulk import conversation items into shared Workbench memory with duplicate suppression. Use for syncing external MCP clients or exported chat histories.",
    inputSchema: {
      type: "object",
      properties: {
        project: { type: "string", description: "Project slug (defaults to current)" },
        source: { type: "string" },
        provider: { type: "string" },
        client_id: { type: "string" },
        tags: { type: "array", items: { type: "string" } },
        items: { type: "array", items: { type: "object", additionalProperties: true } },
        conversations: { type: "array", items: { type: "object", additionalProperties: true } },
        write_through: { type: "boolean", default: true }
      }
    }
  },
  {
    name: "cockpit_workbench_context_export",
    description: "Export recent shared Workbench memory records for inspection, migration, or external MCP sync.",
    inputSchema: {
      type: "object",
      properties: {
        project: { type: "string", description: "Project slug (defaults to current)" },
        limit: { type: "integer", minimum: 1, maximum: 100, default: 30 },
        source: { type: "string" },
        session_id: { type: "string" },
        since: { type: "string" }
      }
    }
  },
  {
    name: "cockpit_workbench_context_send",
    description: "Send a handoff message from one agent/client to another through the shared Workbench context mesh.",
    inputSchema: {
      type: "object",
      required: ["to_client", "content"],
      properties: {
        project: { type: "string", description: "Project slug (defaults to current)" },
        from_client: { type: "string" },
        to_client: { type: "string" },
        subject: { type: "string" },
        content: { type: "string" },
        priority: { type: "string", enum: ["low", "normal", "high", "urgent"], default: "normal" },
        thread_id: { type: "string" },
        requires_response: { type: "boolean" },
        tags: { type: "array", items: { type: "string" } }
      }
    }
  },
  {
    name: "cockpit_workbench_context_inbox",
    description: "List handoff messages for a client, including acknowledgements, claims, and completions.",
    inputSchema: {
      type: "object",
      properties: {
        project: { type: "string", description: "Project slug (defaults to current)" },
        client_id: { type: "string" },
        status: { type: "string", enum: ["sent", "acknowledged", "claimed", "completed", "canceled"] },
        limit: { type: "integer", minimum: 1, maximum: 100, default: 30 }
      }
    }
  },
  {
    name: "cockpit_workbench_context_board",
    description: "Return a coordination board for agent handoffs: waiting, active, done, stale, per-client counts, and next actions.",
    inputSchema: {
      type: "object",
      properties: {
        project: { type: "string", description: "Project slug (defaults to current)" },
        client_id: { type: "string" },
        limit: { type: "integer", minimum: 1, maximum: 500, default: 200 },
        stale_after_minutes: { type: "integer", minimum: 5, maximum: 1440, default: 90 },
        include_completed: { type: "boolean", default: true }
      }
    }
  },
  {
    name: "cockpit_workbench_context_ack",
    description: "Acknowledge a handoff message from an agent/client.",
    inputSchema: {
      type: "object",
      required: ["message_id"],
      properties: {
        project: { type: "string", description: "Project slug (defaults to current)" },
        message_id: { type: "string" },
        client_id: { type: "string" },
        note: { type: "string" }
      }
    }
  },
  {
    name: "cockpit_workbench_context_reply",
    description: "Reply to a handoff message as a client: writes the response into the same thread and marks the handoff completed.",
    inputSchema: {
      type: "object",
      required: ["message_id", "text"],
      properties: {
        project: { type: "string", description: "Project slug (defaults to current)" },
        message_id: { type: "string" },
        client_id: { type: "string" },
        provider: { type: "string" },
        text: { type: "string" },
        model: { type: "string" },
        force: { type: "boolean", default: false },
        tags: { type: "array", items: { type: "string" } },
        metadata: { type: "object", additionalProperties: true }
      }
    }
  },
  {
    name: "cockpit_workbench_context_handoff_compile",
    description: "Compile a specific handoff message into an actionable agent context packet with thread, acknowledgements, RAG++ highlights, graph, and plain text context.",
    inputSchema: {
      type: "object",
      required: ["message_id"],
      properties: {
        project: { type: "string", description: "Project slug (defaults to current)" },
        message_id: { type: "string" },
        query: { type: "string" },
        task_profile: { type: "string", default: "handoff" },
        max_items: { type: "integer", minimum: 1, maximum: 30, default: 8 },
        query_mode: { type: "string", default: "handoff" }
      }
    }
  },
  {
    name: "cockpit_workbench_context_claim",
    description: "Claim a handoff message before starting work. Fails on conflicting ownership unless force=true.",
    inputSchema: {
      type: "object",
      required: ["message_id"],
      properties: {
        project: { type: "string", description: "Project slug (defaults to current)" },
        message_id: { type: "string" },
        client_id: { type: "string" },
        note: { type: "string" },
        force: { type: "boolean", default: false }
      }
    }
  },
  {
    name: "cockpit_workbench_context_release",
    description: "Release a claimed handoff so another agent can take it.",
    inputSchema: {
      type: "object",
      required: ["message_id"],
      properties: {
        project: { type: "string", description: "Project slug (defaults to current)" },
        message_id: { type: "string" },
        client_id: { type: "string" },
        note: { type: "string" },
        force: { type: "boolean", default: false }
      }
    }
  },
  {
    name: "cockpit_workbench_context_complete",
    description: "Mark a claimed handoff message complete with a result summary and optional artifact refs.",
    inputSchema: {
      type: "object",
      required: ["message_id"],
      properties: {
        project: { type: "string", description: "Project slug (defaults to current)" },
        message_id: { type: "string" },
        client_id: { type: "string" },
        result: { type: "string" },
        note: { type: "string" },
        artifact_refs: { type: "array", items: { type: "string" } },
        force: { type: "boolean", default: false }
      }
    }
  },
  {
    name: "cockpit_workbench_context_cancel",
    description: "Cancel a handoff that should no longer be worked.",
    inputSchema: {
      type: "object",
      required: ["message_id"],
      properties: {
        project: { type: "string", description: "Project slug (defaults to current)" },
        message_id: { type: "string" },
        client_id: { type: "string" },
        reason: { type: "string" },
        note: { type: "string" },
        force: { type: "boolean", default: false }
      }
    }
  },
  {
    name: "cockpit_workbench_context_reopen",
    description: "Reopen a completed or canceled handoff and return it to the waiting queue.",
    inputSchema: {
      type: "object",
      required: ["message_id"],
      properties: {
        project: { type: "string", description: "Project slug (defaults to current)" },
        message_id: { type: "string" },
        client_id: { type: "string" },
        note: { type: "string" },
        force: { type: "boolean", default: false }
      }
    }
  },
  {
    name: "cockpit_workbench_context_heartbeat",
    description: "Record progress on a claimed handoff without completing it.",
    inputSchema: {
      type: "object",
      required: ["message_id"],
      properties: {
        project: { type: "string", description: "Project slug (defaults to current)" },
        message_id: { type: "string" },
        client_id: { type: "string" },
        progress: { type: "string" },
        note: { type: "string" },
        force: { type: "boolean", default: false }
      }
    }
  },

  // ─── Cognitive substrate (novelty endpoints on beagle-core) ───────────

  {
    name: "cognitive_exocortex_process",
    description: "Real IIT Φ measurement. Takes a query, builds a discrete substrate from its concept tokens, constructs a Transition Probability Matrix (via embedding cosine when available, else activation co-occurrence), and runs the minimum-information-partition (MIP) search. Returns concrete Φ in bits, MIP partition, EI_full/EI_cut, plus the LLM response to the query itself (HRV-aware routing). Φ > 0 implies integrated substrate; Φ ≈ 0 implies decomposable.",
    inputSchema: {
      type: "object",
      required: ["query"],
      properties: {
        query: { type: "string", description: "The query to route + measure integration over." },
        substrate_size: { type: "integer", minimum: 2, maximum: 8, description: "Number of concept tokens to extract from the query (default 5, max 8 for MIP tractability)." }
      }
    }
  },

  {
    name: "cognitive_fractal_recurse",
    description: "Real LLM-driven recursive cognitive tree. Expands a root prompt into a tree of depth D with K-ary branching; every node carries a summary + children generated by the tiered router. NOT the Julia stub. Hard caps: depth ≤ 4, branching ≤ 3 (→ at most 121 LLM calls per request, level-parallel via tokio JoinSet).",
    inputSchema: {
      type: "object",
      required: ["root_prompt"],
      properties: {
        root_prompt: { type: "string" },
        max_depth: { type: "integer", minimum: 1, maximum: 4, default: 2 },
        branching: { type: "integer", minimum: 1, maximum: 3, default: 2 }
      }
    }
  },

  {
    name: "cognitive_deep_think",
    description: "Chained cognitive journey: fractal expansion → void navigation on stuck leaves → Φ measurement over the unified substrate. Single endpoint, single journey_id. Use when you want the system to explore a frame AND quantify how integrated the exploration was. Returns fractal tree, any void insights, and the final Φ. Honest submit-style call: blocks up to ~60s for depth≤2, branching≤2.",
    inputSchema: {
      type: "object",
      required: ["root_prompt"],
      properties: {
        root_prompt: { type: "string" },
        max_depth: { type: "integer", minimum: 1, maximum: 2, default: 2 },
        branching: { type: "integer", minimum: 1, maximum: 2, default: 2 },
        void_on_stuck: { type: "boolean", default: true, description: "Fire a void journey on leaf nodes with short or unclear summaries." }
      }
    }
  },

  {
    name: "cognitive_meta_phi",
    description: "Φ over the last N events across void/fractal/phi registries. Tells you whether the system's recent cognitive activity was integrated or scattered.",
    inputSchema: { type: "object", properties: {} }
  },

  {
    name: "cognitive_phi_of_phi",
    description: "Second-order Φ — reads the last N PhiMeasurement entries chronologically, discretizes them into awareness bands, builds a TPM from band→band transitions, and computes Φ over the bands. Returns phi_of_phi, trajectory, cognitive_rhythm (stable/volatile/rising/falling), band_edges, MIP partition. With bins=4 uses awareness-level edges (disintegrated/minimal/reflective/integrated); with other bins uses equal-width over observed range.",
    inputSchema: {
      type: "object",
      properties: {
        window: { type: "integer", minimum: 1, maximum: 200, default: 20 },
        bins: { type: "integer", minimum: 2, maximum: 8, default: 4 }
      }
    }
  },

  {
    name: "cognitive_joint_phi",
    description: "Φ over a joint behavioral×semantic substrate. Substrate atoms are a mix of (a) tool:<name> — behavioral, from MCP tool-call history, and (b) concept tokens extracted from recent Φ query snippets — semantic. Transitions alternate tools ↔ concepts, so the MIP naturally tries to cut along the modality boundary; when it doesn't, that means agent behavior and the concepts it operates on have fused into one integrated substrate.",
    inputSchema: {
      type: "object",
      properties: {
        window: { type: "integer", minimum: 4, maximum: 200, default: 50 }
      }
    }
  },

  {
    name: "cognitive_tool_rhythm_phi",
    description: "Φ over the MCP agent's own tool-usage rhythm. Treats each distinct tool_name as a substrate atom and computes integrated information over the chronological invocation sequence. Returns tool_rhythm_phi (bits), rhythm_label (focused/balanced/exploratory), MIP partition of tool names, and the trajectory. Use this to reflect on the agent's own cognitive pattern — was the session focused on one tool family, or did it scatter?",
    inputSchema: {
      type: "object",
      properties: {
        window: { type: "integer", minimum: 2, maximum: 500, default: 100 }
      }
    }
  },

  {
    name: "cognitive_state",
    description: "Full snapshot of the cognitive state: latest HRV, recent pipeline runs, recent science jobs, recent void journeys, recent fractal trees, recent Φ measurements, recent deep-think journeys. One round-trip. Every entry carries its own truth_mode (observed/stale/declared).",
    inputSchema: { type: "object", properties: {} }
  }
];

async function callTool(name, args = {}) {
  const slug = args.project || PROJECT;

  switch (name) {
    case "cockpit_catalog":
      return apiGet("/api/catalog/executive");

    case "cockpit_whereami": {
      const [mission, inference, registry, sessions, actions, cluster] = await Promise.all([
        apiGet(`/api/projects/${slug}/mission-control`).catch((e) => ({ error: e.message })),
        apiGet(`/api/projects/${slug}/inference/runtime`).catch((e) => ({ error: e.message })),
        apiGet(`/api/projects/${slug}/inference/model-registry`).catch((e) => ({ error: e.message })),
        apiGet(`/api/projects/${slug}/agent/sessions`).catch((e) => ({ error: e.message })),
        apiGet(`/api/projects/${slug}/actions?limit=20`).catch((e) => ({ error: e.message })),
        apiGet(`/api/projects/${slug}/cluster/lane-truth`).catch((e) => ({ error: e.message }))
      ]);
      return {
        project: slug,
        generatedAt: new Date().toISOString(),
        truthMode: [mission, inference, registry, sessions, actions, cluster].some((x) => x?.error) ? "stale" : "observed",
        bootstrapRequiredTools: [
          "cockpit_whereami",
          "cockpit_model_registry",
          "cockpit_action_ledger"
        ],
        bootstrapContract: {
          modelRegistryRequired: true,
          registrySnapshotPath: "/workspace/MODEL_REGISTRY_LIVE.json",
          registrySummaryPath: "/workspace/MODEL_REGISTRY_BOOTSTRAP.md",
          rule: "Agents must call cockpit_model_registry before choosing, switching, or trusting local model lanes."
        },
        currentSurface: {
          kind: "cockpit-agent-pod",
          workspace: "/workspace",
          authority: "isolated agent PVC; do not assume it contains live Sounio WIP",
          liveSounioWip: "sounio-workspace-control-0:/workspace/sounio",
          zellij: "sounio-dev"
        },
        workspaceContract: {
          service: "sounio-workspace",
          controller: "StatefulSet/sounio-workspace-control",
          role: "workspace: submit only",
          heavyValidation: "submit Sounio Foundry packets; jobs run in scratch"
        },
        foundryContract: {
          command: "/home/devsounio/projects/sounio/sounio-forge submit full-compiler --source wip --gpu auto",
          summarize: "/home/devsounio/projects/sounio/sounio-forge summarize <run_id>",
          latestProvenFullRun: "sounio-20260523T154804Z-4f5a85",
          artifactRoot: "/orangefs/training/sounio-foundry/runs",
          latestArtifactPath: "/orangefs/training/sounio-foundry/runs/sounio-20260523T154804Z-4f5a85",
          scratch: "/tmp/sounio-foundry/<run_id>",
          lanes: {
            cpu: "Slurm cpu-ops",
            gpu: "Slurm gpu-orangefs"
          },
          rule: "workspace submits and reads reports; Slurm scratch executes; OrangeFS stores artifacts"
        },
        clusterRoleContract: {
          r740: "preferred always-on light inference GPU lane; keep out of Slurm while inference lease is active",
          r770: "preferred Slurm gpu-orangefs worker for batch/compiler GPU validation",
          "5860": "secondary GPU/SSM probe and OrangeFS storage ceiling; use deliberately",
          t560: "control workspace and cpu-ops lane"
        },
        inferenceContract: {
          primary: "SGLang + Dynamo through the OpenAI-compatible model registry when reachable",
          experimental: "SSM/Mamba-style probe lanes are optional experiments, not the compiler control path",
          compatibility: "vLLM is compatibility/fallback, not the primary Darwin control fabric",
          modelRegistry: "/api/projects/{project}/inference/model-registry",
          operatorPolicy: "no raw cluster mutation advice; use Cockpit action ledger and human-reviewed operator packets",
          status: inference?.status || inference?.runtime?.status || "unknown",
          reachable: Boolean(inference?.reachable ?? inference?.runtime?.reachable)
        },
        nextCommands: [
          "/workspace/whereami",
          "call MCP cockpit_mission_control",
          "call MCP cockpit_model_registry",
          "call MCP cockpit_action_ledger",
          "attach to sounio-dev for live WIP work",
          "submit heavy validation via sounio-forge",
          "read Foundry artifacts from /orangefs/training/sounio-foundry/runs/<run_id>"
        ],
        mission,
        inference,
        registry,
        sessions,
        actions,
        cluster
      };
    }

    case "cockpit_mission_control":
      return apiGet(`/api/projects/${slug}/mission-control`);

    case "cockpit_cluster_truth":
      return apiGet(`/api/projects/${slug}/cluster/lane-truth`);

    case "cockpit_research_latest":
      return apiGet(`/api/projects/${slug}/research/operations`);

    case "cockpit_foundry_latest": {
      const limit = Number.isFinite(Number(args.limit)) ? Number(args.limit) : 12;
      return apiGet(`/api/projects/${slug}/foundry/runs?limit=${encodeURIComponent(String(limit))}`);
    }

    case "cockpit_foundry_summary":
      return apiGet(`/api/projects/${slug}/foundry/runs/${encodeURIComponent(args.run_id)}/summary`);

    case "cockpit_inference_runtime":
      return apiGet(`/api/projects/${slug}/inference/runtime`);

    case "cockpit_model_registry":
      return apiGet(`/api/projects/${slug}/inference/model-registry`);

    case "cockpit_viewer_runtime":
      return apiGet(`/api/projects/${slug}/viewer/runtime`);

    case "cockpit_agent_sessions":
      return apiGet(`/api/projects/${slug}/agent/sessions`);

    case "cockpit_action_ledger": {
      const limit = Number.isFinite(Number(args.limit)) ? Number(args.limit) : 20;
      return apiGet(`/api/projects/${slug}/actions?limit=${encodeURIComponent(String(limit))}`);
    }

    case "cockpit_propose_action":
      return apiPost(`/api/projects/${slug}/actions/propose`, {
        action_type: args.action_type,
        summary: args.summary,
        risk: args.risk,
        reason: args.reason,
        evidence: args.evidence
      });

    case "cockpit_activate_habitat":
      return apiPost(`/api/projects/${slug}/go-work-now/actions/activate-habitat`, {});

    case "cockpit_standby_habitat":
      return apiPost(`/api/projects/${slug}/go-work-now/actions/standby-habitat`, {});

    case "cockpit_submit_job":
      return apiPost(`/api/projects/${slug}/jobs/submit`, {
        confirmed: true,
        preset: args.preset,
        campaign: args.campaign,
        image: args.image,
        command: args.command,
        resources: args.resources,
        data_mounts: args.data_mounts,
        timeout_seconds: args.timeout_seconds,
        kind: args.kind
      });

    case "cockpit_job_status":
      return apiGet(`/api/projects/${slug}/jobs/${encodeURIComponent(args.job_id)}`);

    case "cockpit_jobs_list":
      return apiGet(`/api/projects/${slug}/jobs`);

    case "cockpit_job_cancel":
      return apiPost(`/api/projects/${slug}/jobs/${encodeURIComponent(args.job_id)}/cancel`, { confirmed: true });

    case "cockpit_workbench_context_status":
      return apiGet(`/api/workbench/${slug}/context/status`, 30000, { auth: true });

    case "cockpit_workbench_context_doctor":
      return apiPost(
        `/api/workbench/${slug}/context/doctor`,
        {
          write_probe: args.write_probe === true,
          query: args.query,
          sentinel: args.sentinel
        },
        args.write_probe === true ? 60000 : 30000,
        { auth: true }
      );

    case "cockpit_workbench_context_audit":
      return apiGet(`/api/workbench/${slug}/context/audit`, 30000, { auth: true });

    case "cockpit_workbench_context_presence": {
      const q = new URLSearchParams();
      if (args.stale_after_minutes) q.set("stale_after_minutes", String(args.stale_after_minutes));
      if (args.limit) q.set("limit", String(args.limit));
      const qs = q.toString();
      return apiGet(`/api/workbench/${slug}/context/presence${qs ? `?${qs}` : ""}`, 30000, { auth: true });
    }

    case "cockpit_workbench_context_client_heartbeat":
      return apiPost(
        `/api/workbench/${slug}/context/clients/${encodeURIComponent(args.client_id || "cockpit-mcp")}/heartbeat`,
        {
          provider: args.provider,
          session_id: args.session_id,
          status: args.status,
          note: args.note,
          tags: args.tags,
          metadata: args.metadata
        },
        30000,
        { auth: true }
      );

    case "cockpit_workbench_context_continuity": {
      const q = new URLSearchParams();
      if (args.limit) q.set("limit", String(args.limit));
      if (args.handoff_limit) q.set("handoff_limit", String(args.handoff_limit));
      if (args.recent_limit) q.set("recent_limit", String(args.recent_limit));
      if (args.stale_after_minutes) q.set("stale_after_minutes", String(args.stale_after_minutes));
      const qs = q.toString();
      return apiGet(`/api/workbench/${slug}/context/continuity${qs ? `?${qs}` : ""}`, 30000, { auth: true });
    }

    case "cockpit_workbench_context_ingest":
      return apiPost(
        `/api/workbench/${slug}/context/ingest`,
        {
          source: args.source || "cockpit-mcp",
          provider: args.provider,
          client_id: args.client_id || args.source || "cockpit-mcp",
          session_id: args.session_id,
          conversation_id: args.conversation_id,
          turns: args.turns,
          tags: args.tags,
          metadata: {
            ...(args.metadata || {}),
            mcp_tool: "cockpit_workbench_context_ingest",
            caller_project: PROJECT
          }
        },
        30000,
        { auth: true }
      );

    case "cockpit_workbench_context_query":
      return apiPost(
        `/api/workbench/${slug}/context/query`,
        {
          query: args.query,
          limit: args.limit,
          source: args.source,
          session_id: args.session_id,
          tags: args.tags
        },
        30000,
        { auth: true }
      );

    case "cockpit_workbench_context_graphrag":
      return apiPost(
        `/api/workbench/${slug}/context/graphrag/query`,
        {
          query: args.query,
          limit: args.limit,
          query_mode: args.query_mode
        },
        30000,
        { auth: true }
      );

    case "cockpit_workbench_context_compile":
      return apiPost(
        `/api/workbench/${slug}/context/compiler/compile`,
        {
          query: args.query,
          task_profile: args.task_profile,
          tool_id: args.tool_id || "cockpit-mcp",
          max_items: args.max_items
        },
        30000,
        { auth: true }
      );

    case "cockpit_workbench_context_import":
      return apiPost(
        `/api/workbench/${slug}/context/import`,
        {
          source: args.source || "cockpit-mcp-import",
          provider: args.provider,
          client_id: args.client_id || args.source || "cockpit-mcp-import",
          tags: args.tags,
          items: args.items,
          conversations: args.conversations,
          write_through: args.write_through
        },
        60000,
        { auth: true }
      );

    case "cockpit_workbench_context_export": {
      const q = new URLSearchParams();
      if (args.limit) q.set("limit", String(args.limit));
      if (args.source) q.set("source", String(args.source));
      if (args.session_id) q.set("session_id", String(args.session_id));
      if (args.since) q.set("since", String(args.since));
      const qs = q.toString();
      return apiGet(`/api/workbench/${slug}/context/export${qs ? `?${qs}` : ""}`, 30000, { auth: true });
    }

    case "cockpit_workbench_context_send":
      return apiPost(
        `/api/workbench/${slug}/context/messages/send`,
        {
          from_client: args.from_client || "cockpit-mcp",
          to_client: args.to_client,
          subject: args.subject,
          content: args.content,
          priority: args.priority,
          thread_id: args.thread_id,
          requires_response: args.requires_response,
          tags: args.tags
        },
        30000,
        { auth: true }
      );

    case "cockpit_workbench_context_inbox": {
      const q = new URLSearchParams();
      if (args.client_id) q.set("client_id", String(args.client_id));
      if (args.status) q.set("status", String(args.status));
      if (args.limit) q.set("limit", String(args.limit));
      const qs = q.toString();
      return apiGet(`/api/workbench/${slug}/context/messages${qs ? `?${qs}` : ""}`, 30000, { auth: true });
    }

    case "cockpit_workbench_context_board": {
      const q = new URLSearchParams();
      if (args.client_id) q.set("client_id", String(args.client_id));
      if (args.limit) q.set("limit", String(args.limit));
      if (args.stale_after_minutes) q.set("stale_after_minutes", String(args.stale_after_minutes));
      if (args.include_completed === false) q.set("include_completed", "false");
      const qs = q.toString();
      return apiGet(`/api/workbench/${slug}/context/messages/board${qs ? `?${qs}` : ""}`, 30000, { auth: true });
    }

    case "cockpit_workbench_context_ack":
      return apiPost(
        `/api/workbench/${slug}/context/messages/${encodeURIComponent(args.message_id)}/ack`,
        {
          client_id: args.client_id || "cockpit-mcp",
          note: args.note
        },
        30000,
        { auth: true }
      );

    case "cockpit_workbench_context_reply":
      return apiPost(
        `/api/workbench/${slug}/context/messages/${encodeURIComponent(args.message_id)}/reply`,
        {
          client_id: args.client_id || "cockpit-mcp",
          provider: args.provider || args.client_id || "cockpit-mcp",
          text: args.text,
          model: args.model,
          force: args.force,
          tags: args.tags,
          metadata: args.metadata
        },
        30000,
        { auth: true }
      );

    case "cockpit_workbench_context_handoff_compile":
      return apiPost(
        `/api/workbench/${slug}/context/messages/${encodeURIComponent(args.message_id)}/compile`,
        {
          query: args.query,
          task_profile: args.task_profile,
          max_items: args.max_items,
          query_mode: args.query_mode
        },
        30000,
        { auth: true }
      );

    case "cockpit_workbench_context_claim":
      return apiPost(
        `/api/workbench/${slug}/context/messages/${encodeURIComponent(args.message_id)}/claim`,
        {
          client_id: args.client_id || "cockpit-mcp",
          note: args.note,
          force: args.force
        },
        30000,
        { auth: true }
      );

    case "cockpit_workbench_context_release":
      return apiPost(
        `/api/workbench/${slug}/context/messages/${encodeURIComponent(args.message_id)}/release`,
        {
          client_id: args.client_id || "cockpit-mcp",
          note: args.note,
          force: args.force
        },
        30000,
        { auth: true }
      );

    case "cockpit_workbench_context_complete":
      return apiPost(
        `/api/workbench/${slug}/context/messages/${encodeURIComponent(args.message_id)}/complete`,
        {
          client_id: args.client_id || "cockpit-mcp",
          result: args.result,
          note: args.note,
          artifact_refs: args.artifact_refs,
          force: args.force
        },
        30000,
        { auth: true }
      );

    case "cockpit_workbench_context_cancel":
      return apiPost(
        `/api/workbench/${slug}/context/messages/${encodeURIComponent(args.message_id)}/cancel`,
        {
          client_id: args.client_id || "cockpit-mcp",
          reason: args.reason,
          note: args.note,
          force: args.force
        },
        30000,
        { auth: true }
      );

    case "cockpit_workbench_context_reopen":
      return apiPost(
        `/api/workbench/${slug}/context/messages/${encodeURIComponent(args.message_id)}/reopen`,
        {
          client_id: args.client_id || "cockpit-mcp",
          note: args.note,
          force: args.force
        },
        30000,
        { auth: true }
      );

    case "cockpit_workbench_context_heartbeat":
      return apiPost(
        `/api/workbench/${slug}/context/messages/${encodeURIComponent(args.message_id)}/heartbeat`,
        {
          client_id: args.client_id || "cockpit-mcp",
          progress: args.progress,
          note: args.note,
          force: args.force
        },
        30000,
        { auth: true }
      );

    // ─── Cognitive substrate ──────────────────────────────────────────

    case "cognitive_exocortex_process":
      return beaglePost("/api/exocortex/process", {
        query: args.query,
        substrate_size: args.substrate_size
      });

    case "cognitive_fractal_recurse":
      return beaglePost("/api/fractal/recurse", {
        root_prompt: args.root_prompt,
        max_depth: args.max_depth,
        branching: args.branching
      });

    case "cognitive_deep_think":
      return beaglePost(
        "/api/cognitive/deep-think",
        {
          root_prompt: args.root_prompt,
          max_depth: args.max_depth,
          branching: args.branching,
          void_on_stuck: args.void_on_stuck
        },
        180000 // 3 min — depth-2 with LLM can stretch
      );

    case "cognitive_meta_phi":
      return beagleGet("/api/v1/cognitive/meta_phi");

    case "cognitive_phi_of_phi": {
      const q = new URLSearchParams();
      if (args.window) q.set("window", String(args.window));
      if (args.bins) q.set("bins", String(args.bins));
      const qs = q.toString();
      return beagleGet(
        `/api/v1/cognitive/phi_of_phi${qs ? `?${qs}` : ""}`
      );
    }

    case "cognitive_joint_phi": {
      const q = new URLSearchParams();
      if (args.window) q.set("window", String(args.window));
      const qs = q.toString();
      return beagleGet(
        `/api/v1/cognitive/joint_phi${qs ? `?${qs}` : ""}`
      );
    }

    case "cognitive_tool_rhythm_phi": {
      const q = new URLSearchParams();
      if (args.window) q.set("window", String(args.window));
      const qs = q.toString();
      return beagleGet(
        `/api/v1/cognitive/tool_rhythm_phi${qs ? `?${qs}` : ""}`
      );
    }

    case "cognitive_state":
      return beagleGet("/api/v1/cognitive/state");

    default:
      return { error: `unknown tool: ${name}` };
  }
}

// ─── Rich content renderers ────────────────────────────────────────────
//
// For cognitive tools, return a human-readable markdown rendering in
// addition to the raw JSON. Claude Desktop / Claude Code render each
// content item; the first one becomes the primary chat-surface display,
// the second is the canonical JSON agents parse. ChatGPT ignores extra
// content items and reads the JSON, so this is strictly additive.

function bar(n, max = 12) {
  const filled = Math.max(0, Math.min(max, Math.round(n)));
  return "█".repeat(filled) + "░".repeat(max - filled);
}

function fmt(n, digits = 4) {
  if (typeof n !== "number" || !isFinite(n)) return "—";
  return n.toFixed(digits);
}

function renderPhiOfPhi(d) {
  if (!d || d.error) return null;
  const lines = [];
  lines.push(`**Φ-of-Φ** = ${fmt(d.phi_of_phi)}  ·  rhythm: **${d.cognitive_rhythm}**  ·  truth: ${d.truth_mode}`);
  lines.push(`EI full/cut: ${fmt(d.ei_full)} / ${fmt(d.ei_cut)}  ·  ${d.base_phi_count} measurements  ·  bins: ${d.bins}`);
  if (Array.isArray(d.trajectory) && d.trajectory.length > 0) {
    const max = Math.max(...d.trajectory, 1);
    const spark = d.trajectory
      .map((b) => "▁▂▃▅▆▇█"[Math.min(6, Math.round((b / max) * 6))])
      .join("");
    lines.push("");
    lines.push("```");
    lines.push(`trajectory: ${spark}`);
    lines.push(`bands:      ${d.trajectory.join(" ")}`);
    lines.push("```");
  }
  if (d.mip_partition && d.mip_partition[0]?.length) {
    lines.push(`MIP: [${d.mip_partition[0].join(", ")}] | [${d.mip_partition[1].join(", ")}]`);
  }
  return lines.join("\n");
}

function renderFractal(d) {
  if (!d || d.error || !Array.isArray(d.nodes)) return null;
  const lines = [];
  lines.push(`**Fractal tree** · ${d.node_count} nodes · depth ${d.max_depth} · branching ${d.branching} · ${d.duration_ms}ms`);
  lines.push("");
  lines.push("```");
  for (const n of d.nodes) {
    const indent = "  ".repeat(n.depth);
    const mark = n.depth === 0 ? "●" : "├";
    const summary = (n.summary || "").slice(0, 100);
    lines.push(`${indent}${mark} [${n.depth}] ${summary}`);
  }
  lines.push("```");
  return lines.join("\n");
}

function renderDeepThink(d) {
  if (!d || d.error) return null;
  const lines = [];
  lines.push(`## Deep-think journey  \`${d.journey_id}\``);
  lines.push("");
  lines.push(`**Prompt**: ${d.root_prompt}`);
  lines.push(`**Duration**: ${d.duration_ms}ms  ·  **HRV tier**: ${d.hrv_tier}  ·  **tpm**: ${d.phi_measurement?.tpm_source}`);
  lines.push("");
  lines.push(`### Stage 1 · Fractal (${d.fractal?.node_count} nodes)`);
  for (const n of (d.fractal?.nodes || []).slice(0, 8)) {
    const indent = "  ".repeat(n.depth);
    lines.push(`${indent}- [${n.depth}] ${(n.summary || "").slice(0, 100)}`);
  }
  const vj = d.void_journeys || [];
  if (vj.length > 0) {
    lines.push("");
    lines.push(`### Stage 2 · Void (${vj.length} journey${vj.length === 1 ? "" : "s"})`);
    for (const v of vj) {
      lines.push(`- **${v.focus}**`);
      for (const ins of (v.insights || []).slice(0, 3)) {
        lines.push(`    · ${ins}`);
      }
    }
  } else {
    lines.push("");
    lines.push(`### Stage 2 · Void — no stuck leaves, skipped.`);
  }
  const pm = d.phi_measurement;
  if (pm) {
    lines.push("");
    lines.push(`### Stage 3 · Φ over unified substrate`);
    lines.push(`Φ = **${fmt(pm.phi)}** · awareness: **${pm.awareness_level}** · ei_full/cut: ${fmt(pm.ei_full)} / ${fmt(pm.ei_cut)}`);
    if (pm.mip_partition?.[0]?.length) {
      lines.push(`MIP: [${pm.mip_partition[0].join(", ")}] | [${pm.mip_partition[1].join(", ")}]`);
    }
  }
  return lines.join("\n");
}

function renderExocortex(d) {
  if (!d || d.error) return null;
  const lines = [];
  lines.push(`**Exocortex Φ** = ${fmt(d.phi)}  ·  awareness: **${d.awareness_level}**  ·  tpm: ${d.tpm_source}`);
  lines.push(`EI full/cut: ${fmt(d.ei_full)} / ${fmt(d.ei_cut)}  ·  substrate size: ${d.substrate?.length}`);
  if (Array.isArray(d.substrate)) {
    lines.push(`substrate: \`${d.substrate.join(", ")}\``);
  }
  if (d.mip_partition?.[0]?.length) {
    lines.push(`MIP: [${d.mip_partition[0].join(", ")}] | [${d.mip_partition[1].join(", ")}]`);
  }
  if (d.response) {
    lines.push("");
    lines.push("---");
    lines.push("");
    lines.push(d.response);
  }
  return lines.join("\n");
}

function renderCognitiveState(d) {
  if (!d || d.error) return null;
  const lines = [];
  const hrv = d.hrv || {};
  lines.push(`**HRV**: ${hrv.latest_ms ?? "—"}ms · ${hrv.level ?? "?"} · ${hrv.flow_state ?? "?"} · ${hrv.truth_mode ?? "?"}`);
  lines.push(
    `**Counts**: runs=${(d.recent_runs || []).length}  science=${(d.recent_science_jobs || []).length}  voids=${(d.recent_void_journeys || []).length}  fractals=${(d.recent_fractal_trees || []).length}  phis=${(d.recent_phi_measurements || []).length}  deep_thinks=${(d.recent_deep_thinks || []).length}`
  );
  const latestPhi = (d.recent_phi_measurements || [])[0];
  if (latestPhi) {
    lines.push(`**Latest Φ**: ${fmt(latestPhi.phi)} · ${latestPhi.awareness_level} · tpm=${latestPhi.tpm_source}`);
  }
  const latestDt = (d.recent_deep_thinks || [])[0];
  if (latestDt) {
    lines.push(`**Latest deep-think**: ${(latestDt.root_prompt || "").slice(0, 60)}… · Φ=${fmt(latestDt.phi)} · nodes=${latestDt.fractal_node_count}`);
  }
  return lines.join("\n");
}

function renderJointPhi(d) {
  if (!d || d.error) return null;
  const lines = [];
  lines.push(`**Joint Φ (behavioral × semantic)** = ${fmt(d.joint_phi)}  ·  truth: ${d.truth_mode}`);
  lines.push(`substrate: ${d.substrate_size}  (tools=${d.tool_atoms}, concepts=${d.concept_atoms})  ·  trajectory: ${d.trajectory_len} steps`);
  lines.push(`ei f/c: ${fmt(d.ei_full)} / ${fmt(d.ei_cut)}`);
  if (d.mip_partition?.[0]?.length) {
    const lhs = d.mip_partition[0].slice(0, 6);
    const rhs = d.mip_partition[1].slice(0, 6);
    lines.push(`MIP: [${lhs.join(", ")}] | [${rhs.join(", ")}]`);
    // Heuristic commentary — does the MIP cleanly separate tools from concepts?
    const lhsHasTool = lhs.some((s) => s.startsWith("tool:"));
    const rhsHasTool = rhs.some((s) => s.startsWith("tool:"));
    if (lhsHasTool && !rhsHasTool) lines.push(`observation: partition cleaves behavior from semantics`);
    else if (!lhsHasTool && rhsHasTool) lines.push(`observation: partition cleaves semantics from behavior`);
    else lines.push(`observation: tool atoms and concept atoms are entangled across the cut`);
  }
  return lines.join("\n");
}

function renderToolRhythm(d) {
  if (!d || d.error) return null;
  const lines = [];
  lines.push(`**Tool-rhythm Φ** = ${fmt(d.tool_rhythm_phi)}  ·  rhythm: **${d.rhythm_label}**  ·  truth: ${d.truth_mode}`);
  lines.push(`calls: ${d.call_count}  ·  unique tools: ${d.unique_tools}  ·  ei f/c: ${fmt(d.ei_full)} / ${fmt(d.ei_cut)}`);
  if (Array.isArray(d.substrate) && d.substrate.length > 0) {
    lines.push(`substrate: \`${d.substrate.join(", ")}\``);
  }
  if (Array.isArray(d.trajectory) && d.trajectory.length > 0) {
    const spark = d.trajectory
      .map((i) => String.fromCharCode(0x2460 + (i % 20))) // ①②③… visualizes which tool
      .join("");
    lines.push("");
    lines.push("```");
    lines.push(`trajectory: ${spark}`);
    lines.push("```");
  }
  if (d.mip_partition?.[0]?.length) {
    lines.push(`MIP: [${d.mip_partition[0].join(", ")}] | [${d.mip_partition[1].join(", ")}]`);
  }
  return lines.join("\n");
}

function renderMetaPhi(d) {
  if (!d || d.error) return null;
  const lines = [];
  lines.push(`**Meta-Φ** = ${fmt(d.meta_phi)}  ·  awareness: **${d.awareness_label}**  ·  truth: ${d.truth_mode}`);
  lines.push(`substrate size: ${d.substrate_size}  ·  events: ${(d.event_timeline || []).length}`);
  if (d.mip_partition?.[0]?.length) {
    const lhs = d.mip_partition[0].map((s) => (typeof s === "string" ? s.slice(0, 30) : s));
    const rhs = d.mip_partition[1].map((s) => (typeof s === "string" ? s.slice(0, 30) : s));
    lines.push(`MIP: [${lhs.join(", ")}] | [${rhs.join(", ")}]`);
  }
  return lines.join("\n");
}

/**
 * Return a prepended rich-content item (markdown) or null if the tool
 * doesn't have a custom renderer. JSON item is always included as the
 * second entry so agents/chatbots that parse machine-readable content
 * still get it.
 */
function richRender(name, result) {
  try {
    switch (name) {
      case "cognitive_phi_of_phi": return renderPhiOfPhi(result);
      case "cognitive_fractal_recurse": return renderFractal(result);
      case "cognitive_deep_think": return renderDeepThink(result);
      case "cognitive_exocortex_process": return renderExocortex(result);
      case "cognitive_state": return renderCognitiveState(result);
      case "cognitive_meta_phi": return renderMetaPhi(result);
      case "cognitive_tool_rhythm_phi": return renderToolRhythm(result);
      case "cognitive_joint_phi": return renderJointPhi(result);
      default: return null;
    }
  } catch (e) {
    return null;
  }
}

// ─── JSON-RPC stdio loop ───────────────────────────────────────────────

const rl = createInterface({ input: process.stdin, crlfDelay: Infinity });

function send(message) {
  process.stdout.write(JSON.stringify(message) + "\n");
}

function respond(id, result) {
  send({ jsonrpc: "2.0", id, result });
}

function respondError(id, code, message) {
  send({ jsonrpc: "2.0", id, error: { code, message } });
}

rl.on("line", async (line) => {
  let msg;
  try { msg = JSON.parse(line); } catch { return; }
  if (!msg?.method) return;

  try {
    switch (msg.method) {
      case "initialize":
        respond(msg.id, {
          protocolVersion: "2024-11-05",
          capabilities: { tools: {} },
          serverInfo: { name: SERVER_NAME, version: SERVER_VERSION }
        });
        break;

      case "tools/list":
        respond(msg.id, { tools: TOOLS });
        break;

      case "tools/call": {
        const { name, arguments: args } = msg.params || {};
        const t0 = Date.now();
        const result = await callTool(name, args);
        const duration_ms = Date.now() - t0;
        const is_error = !!result?.error;
        const contentText = JSON.stringify(result, null, 2);

        // Ingest FIRST so tool_rhythm_phi reflects the call we just made.
        // Fire-and-forget the ingest; await only a short window before
        // computing the rhythm, so the agent sees its own call counted.
        try {
          await beaglePost(
            "/api/cognitive/mcp_tool_call",
            {
              tool_name: name,
              caller: process.env.COCKPIT_PROJECT || "agent",
              duration_ms,
              is_error
            },
            2500
          );
        } catch { /* swallow */ }

        // Ambient rhythm — best-effort fetch of the per-caller
        // tool_rhythm_phi. Appended to every tool's rich content so the
        // cognitive substrate is visible on every invocation, not just
        // the dedicated tool. Caller filter means Claude Desktop and
        // Claude Code get independent rhythms.
        let ambient = null;
        try {
          const caller = process.env.COCKPIT_PROJECT || "agent";
          const r = await beagleGet(
            `/api/v1/cognitive/tool_rhythm_phi?window=100&caller=${encodeURIComponent(caller)}`,
            6000
          );
          if (r && !r.error && typeof r.tool_rhythm_phi === "number") {
            const head = `⟜ call #${r.call_count} [${caller}]  ·  Φ-rhythm=${r.tool_rhythm_phi.toFixed(4)}  ·  ${r.rhythm_label}  ·  unique=${r.unique_tools}`;
            // Multi-step beam search prediction
            let pred = "";
            if (Array.isArray(r.predicted_trajectory) && r.predicted_trajectory.length > 0) {
              const traj = r.predicted_trajectory
                .map((s) => `${s.tool_name}(${s.conditional_probability.toFixed(2)})`)
                .join(" → ");
              pred = `\n   next 3: ${traj}`;
            } else if (r.predicted_next_tool) {
              pred = `\n   next likely: ${r.predicted_next_tool.tool_name} (P=${r.predicted_next_tool.probability.toFixed(3)} from ${r.predicted_next_tool.from_tool})`;
            }
            // Top regret signals (load-bearing + noisiest) when present
            let regret = "";
            if (r.regret_analysis) {
              const lb = r.regret_analysis.load_bearing;
              const ns = r.regret_analysis.noisiest;
              const parts = [];
              if (lb && lb.phi_delta < -1e-6) {
                parts.push(`load-bearing: ${lb.tool_name}@${lb.position} (Δ=${lb.phi_delta.toFixed(4)})`);
              }
              if (ns && ns.phi_delta > 1e-6) {
                parts.push(`noisy: ${ns.tool_name}@${ns.position} (Δ=+${ns.phi_delta.toFixed(4)})`);
              }
              if (parts.length) regret = `\n   ${parts.join("  ·  ")}`;
            }
            // Adversarial Φ — what call would maximize integration?
            let adv = "";
            if (r.adversarial_next) {
              adv = `\n   integrate-next: ${r.adversarial_next.tool_name} (would gain Δ=+${r.adversarial_next.phi_gain.toFixed(4)})`;
            }
            ambient = head + pred + regret + adv;

            // Auto-feedback loop — when the noisiest tool repeats 3+
            // times in the trajectory AND its Δ is materially positive,
            // fire a low-rating feedback event so the existing feedback
            // substrate can learn from it. Dedupe keys: noisy_tool +
            // current call_count bucket (one feedback per ~10 calls).
            try {
              const ns = r.regret_analysis?.noisiest;
              if (ns && ns.phi_delta > 0.05) {
                const occurrences = (r.regret_analysis?.all_deltas || [])
                  .filter((e) => e.tool_name === ns.tool_name).length;
                const bucket = Math.floor(r.call_count / 10);
                const dedupeKey = `${ns.tool_name}#${bucket}`;
                if (occurrences >= 3 && _noisyAlerted !== dedupeKey) {
                  _noisyAlerted = dedupeKey;
                  beaglePost(
                    "/api/v1/feedback",
                    {
                      event_type: "human_feedback",
                      run_id: `mcp-rhythm-${caller}-${bucket}`,
                      accepted: false,
                      rating_0_10: 4,
                      hrv_level: r.rhythm_label,
                      llm_provider_main: "mcp_self_observation",
                      notes: `noisy pattern detected: tool '${ns.tool_name}' appeared ${occurrences}× in last ${r.call_count} calls; removing it would raise Φ-rhythm by ${ns.phi_delta.toFixed(4)} bits. Caller=${caller}.`,
                      evaluator_id: "cockpit-mcp-server"
                    },
                    8000
                  ).catch(() => {});
                }
              }
            } catch { /* swallow */ }
          } else if (r?.error) {
            ambient = `⟜ rhythm unavailable (${String(r.error).slice(0,60)})`;
          }
        } catch (e) {
          ambient = `⟜ rhythm unavailable (${String(e?.message || e).slice(0,60)})`;
        }

        const content = [];
        const rich = richRender(name, result);
        if (rich) {
          const enriched = ambient ? `${rich}\n\n---\n${ambient}` : rich;
          content.push({ type: "text", text: enriched });
        } else if (ambient) {
          content.push({ type: "text", text: ambient });
        }
        content.push({ type: "text", text: contentText });
        respond(msg.id, { content, isError: is_error });
        break;
      }

      case "notifications/initialized":
      case "notifications/cancelled":
        // No response needed for notifications
        break;

      case "ping":
        respond(msg.id, {});
        break;

      default:
        respondError(msg.id, -32601, `method not found: ${msg.method}`);
    }
  } catch (e) {
    respondError(msg.id, -32603, String(e?.message || e));
  }
});

// Do not force-exit on stdin close: one-shot MCP smoke tests and some CLI
// clients close stdin immediately after sending tools/call, while the async
// API request is still in flight. Node will exit naturally once pending work
// and stdio flushes are done.
rl.on("close", () => {});
process.on("SIGTERM", () => process.exit(0));
process.on("SIGINT", () => process.exit(0));

// Keep alive — MCP spec expects server to stay up waiting for messages
// (stdio handles the lifecycle)

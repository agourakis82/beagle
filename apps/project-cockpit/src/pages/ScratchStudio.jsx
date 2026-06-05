import { For, Show, createMemo, createSignal, onCleanup, onMount } from "solid-js";
import { useParams } from "@solidjs/router";
import { useTitle } from "../hooks/useTitle";
import AgentTerminal from "../components/AgentTerminal";
import Terminal from "../components/Terminal";
import "./ScratchStudio.css";

async function fetchJson(url, options = {}) {
  const res = await fetch(url, {
    method: options.method || "GET",
    headers: options.body ? { "content-type": "application/json" } : undefined,
    body: options.body ? JSON.stringify(options.body) : undefined,
    signal: AbortSignal.timeout(options.timeoutMs || 12000),
  });
  const payload = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(payload?.error || `${res.status}`);
  return payload;
}

function id() {
  return globalThis.crypto?.randomUUID?.() || `${Date.now()}-${Math.random()}`;
}

const DEFAULT_SUBSCRIPTION_CONNECTORS = [
  {
    id: "claude-desktop",
    provider: "claude-desktop",
    targetClient: "claude-desktop",
    label: "Claude Desktop",
    connectSurface: "Claude Desktop MCP",
    requiredToolFlow: ["cockpit_workbench_context", "cockpit_workbench_context_reply"]
  },
  {
    id: "chatgpt-mcp",
    provider: "chatgpt-mcp",
    targetClient: "chatgpt-mcp",
    label: "ChatGPT",
    connectSurface: "ChatGPT MCP",
    requiredToolFlow: ["workbench_context", "workbench_context_reply"]
  },
  {
    id: "grok-mcp",
    provider: "grok-mcp",
    targetClient: "grok-mcp",
    label: "Grok",
    connectSurface: "Grok MCP",
    requiredToolFlow: ["workbench_context", "workbench_context_reply"]
  }
];

function subscriptionClientViewModel(client = {}) {
  const targetClient = client.targetClient || client.provider || client.id;
  const status = client.status || client.clientPresence || "waiting";
  const isLive = status === "live" || client.realConnectionObserved === true;
  return {
    ...client,
    id: client.id || targetClient,
    provider: client.provider || targetClient,
    targetClient,
    label: client.label || targetClient,
    status,
    realConnectionObserved: isLive,
    liveProof: isLive ? "fresh real heartbeat observed" : "waiting for subscription app reply",
    url: client.url || client.mcpEndpoint || "",
    headers: client.headers || client.mcpHeaders || {},
    connect: {
      surface: client.connect?.surface || client.connectSurface || client.label || "MCP client",
      firstToolCalls: (client.connect?.firstToolCalls || client.requiredToolFlow || []).map((tool) =>
        typeof tool === "string" ? { tool, args: {} } : tool
      )
    },
    replyGate: client.replyGate || {
      status: isLive ? "ready-to-test" : "waiting-for-real-client",
      latestProof: null,
      proofRequired: "A real subscription client must call the MCP reply tool for this gate."
    },
    blockers: client.blockers || (isLive ? [] : [client.reason || "waiting for real subscription client"])
  };
}

function providerStateClass(status) {
  if (status === "available" || status === "streaming" || status === "done") return "replied";
  if (status === "starting" || status === "waiting") return "waiting";
  return "error";
}

function isMcpMailboxProvider(provider) {
  return provider?.transport === "workbench-context-mcp-inbox" && provider?.mailboxStatus === "available";
}

function providerSurfaceClass(provider) {
  if (isMcpMailboxProvider(provider)) {
    return provider.status === "available" ? "replied" : "waiting";
  }
  return isSelectableProvider(provider) ? "replied" : "error";
}

function providerSurfaceLabel(provider) {
  if (isMcpMailboxProvider(provider)) {
    return provider.status === "available" ? "MCP client live" : "waiting for MCP client";
  }
  return isSelectableProvider(provider) ? provider.transport : "unavailable";
}

function providerSubtitle(provider) {
  if (provider.terminalProvider) {
    return provider.status === "available"
      ? "live shared terminal"
      : provider.reason;
  }
  if (isMcpMailboxProvider(provider)) {
    const presence = provider.clientPresence || "unobserved";
    const latest = provider.clientLatestAt ? ` · ${new Date(provider.clientLatestAt).toLocaleTimeString()}` : "";
    return provider.status === "available"
      ? `mailbox ready · client recent${latest}`
      : `mailbox ready · client ${presence}${latest}`;
  }
  if (provider.status !== "available") return provider.reason;
  if (provider.id === "kimi" && provider.bridgeMode === "cross-project-zellij") {
    return provider.reason || `${provider.transport} · ${provider.model}`;
  }
  return [provider.transport, provider.model].filter(Boolean).join(" · ");
}

function isHiddenCrossProjectProvider(provider) {
  return false;
}

function isRealtimeVerifiableProvider(provider) {
  if (!provider || !isSelectableProvider(provider)) return false;
  return provider.terminalProvider === true
    || ["local-subscription-cli", "xai-api-stream", "remote-zellij-terminal", "shared-agent-pty", "local-desktop-pty"].includes(provider.transport);
}

function isSelectableProvider(provider) {
  if (!provider) return false;
  if (provider.selectable === true) return true;
  if (provider.transport === "workbench-context-mcp-inbox") return provider.mailboxStatus === "available";
  return provider.status === "available";
}

function responseMetaItems(response) {
  const meta = response.meta || {};
  const unsafeHistoricalKimiSession = response.provider === "kimi" && /sounio|sounio-dev|sounio-workspace/i.test(String(meta.session_id || ""));
  return [
    meta.transport ? ["transport", meta.transport] : null,
    meta.state ? ["state", meta.state] : null,
    meta.lifecycle_status ? ["lifecycle", meta.lifecycle_status] : null,
    meta.targetClient ? ["target", meta.targetClient] : null,
    meta.thread_id ? ["thread", meta.thread_id] : null,
    meta.message_id ? ["message", meta.message_id] : null,
    meta.acked_by ? ["ack", meta.acked_by] : null,
    meta.claimed_by ? ["claim", meta.claimed_by] : null,
    meta.completed_by ? ["complete", meta.completed_by] : null,
    meta.canceled_by ? ["cancel", meta.canceled_by] : null,
    meta.late_reply ? ["late reply", "reconciled"] : null,
    meta.reconciled_at ? ["reconciled", new Date(meta.reconciled_at).toLocaleTimeString()] : null,
    meta.reply_memory_id ? ["reply", meta.reply_memory_id] : null,
    meta.reply_source ? ["source", meta.reply_source] : null,
    meta.model ? ["model", meta.model] : null,
    meta.session_id && !unsafeHistoricalKimiSession ? ["session", meta.session_id] : null,
    meta.sourceProvider ? ["source", meta.sourceProvider] : null,
  ].filter(Boolean);
}

function mcpHandoffDetail(response, slug) {
  const meta = response?.meta || {};
  if (meta.transport !== "workbench-context-mcp-inbox" || !meta.message_id) return null;
  const state = meta.state || (response.status === "done" ? "handoff-replied" : "handoff-sent");
  const lifecycleStatus = meta.lifecycle_status || "";
  const lifecycle = [
    meta.acked_by ? `ack ${meta.acked_by}` : null,
    meta.claimed_by ? `claimed ${meta.claimed_by}` : null,
    meta.heartbeat_at ? `heartbeat ${new Date(meta.heartbeat_at).toLocaleTimeString()}` : null,
    meta.completed_by ? `complete ${meta.completed_by}` : null,
    meta.canceled_by ? `cancel ${meta.canceled_by}` : null
  ].filter(Boolean);
  return {
    state,
    target: meta.targetClient || "mcp-client",
    messageId: meta.message_id,
    threadId: meta.thread_id || "",
    replyEndpoint: `/api/workbench/${slug}/context/messages/${encodeURIComponent(meta.message_id)}/reply`,
    directReplyEndpoint: `/api/projects/${slug}/multimodel/mcp-inbox/${encodeURIComponent(meta.message_id)}/reply`,
    directCancelEndpoint: `/api/projects/${slug}/multimodel/mcp-inbox/${encodeURIComponent(meta.message_id)}/cancel`,
    tool: meta.targetClient === "claude-desktop" ? "cockpit_workbench_context_reply" : "workbench_context_reply",
    phase: mcpHandoffPhase({ state, lifecycleStatus, responseStatus: response.status, hasText: Boolean(response.text), hasError: Boolean(response.error) }),
    lifecycle
  };
}

function mcpReplyArgs(handoff) {
  return {
    message_id: handoff.messageId,
    client_id: handoff.target,
    text: "<your response>"
  };
}

function formatMcpHandoffPacket(packet, handoff) {
  const replyArgs = mcpReplyArgs(handoff);
  const handoffRecord = packet?.handoff || {};
  return [
    "Beagle Workbench MCP handoff",
    "",
    `Project: ${packet?.projectSlug || ""}`,
    `Target client: ${handoff.target}`,
    `Message ID: ${handoff.messageId}`,
    `Thread: ${handoff.threadId || handoffRecord.thread_id || ""}`,
    `Reply tool: ${handoffRecord.reply_tool || handoff.tool}`,
    `Reply args JSON: ${JSON.stringify(replyArgs)}`,
    "",
    "Instruction:",
    packet?.reply_instruction || `Use ${handoff.tool} with the message_id above.`,
    "",
    "Handoff text:",
    handoffRecord.text || "",
    "",
    "Retrieved context:",
    packet?.compiled_context_text || "",
    "",
    "Full packet JSON:",
    JSON.stringify(packet || {}, null, 2)
  ].join("\n");
}

function formatMcpActivationPrompt(handoff, slug) {
  const replyArgs = mcpReplyArgs(handoff);
  const joinArgs = {
    client_id: handoff.target,
    status: "online",
    note: "real subscription client connected to Beagle Workbench",
    tags: ["subscription-client", "beagle-workbench", slug]
  };
  return [
    `You are the real ${handoff.target} subscription client for Beagle Workbench project ${slug}.`,
    "Use MCP tools only for this handoff; do not answer in ordinary chat.",
    "",
    `1. Call workbench_context_join with: ${JSON.stringify(joinArgs)}`,
    `2. If you need context, call workbench_context_handoff_compile with: ${JSON.stringify({ message_id: handoff.messageId, client_id: handoff.target })}`,
    `3. Reply through ${handoff.tool} with: ${JSON.stringify(replyArgs)}`,
    "",
    `The message_id is ${handoff.messageId}.`,
    `The thread_id is ${handoff.threadId || ""}.`,
    "The reply must be written through the MCP reply tool so Beagle can mark this as real."
  ].join("\n");
}

function mcpHandoffPhase({ state, lifecycleStatus, responseStatus, hasText, hasError }) {
  if (hasText || responseStatus === "done" || lifecycleStatus === "completed") {
    return { className: "replied", label: "reply received", detail: "The subscription client wrote back through Workbench Context." };
  }
  if (hasError || responseStatus === "error" || lifecycleStatus === "canceled") {
    return { className: "error", label: "needs attention", detail: "The handoff stopped or returned an error." };
  }
  if (lifecycleStatus === "claimed" || state === "handoff-claimed") {
    return { className: "waiting", label: "client working", detail: "The subscription client claimed the message and has not replied yet." };
  }
  if (lifecycleStatus === "acknowledged" || state === "handoff-acknowledged") {
    return { className: "waiting", label: "client saw it", detail: "The client acknowledged the handoff. Waiting for reply." };
  }
  return { className: "waiting", label: "waiting for reply", detail: "Sent to the subscription client. It must call the MCP reply tool." };
}

function isPendingMcpHandoff(response) {
  const meta = response?.meta || {};
  if (meta.transport !== "workbench-context-mcp-inbox" || !meta.message_id) return false;
  if (response.text || response.error) return false;
  const state = String(meta.state || "").toLowerCase();
  const lifecycle = String(meta.lifecycle_status || "").toLowerCase();
  if (["handoff-completed", "handoff-replied", "handoff-canceled"].includes(state)) return false;
  if (["completed", "replied", "canceled"].includes(lifecycle)) return false;
  return ["waiting", "streaming"].includes(response.status) || state.startsWith("handoff-") || state === "awaiting-client-context-write";
}

function isOpenMcpInboxMessage(message) {
  const status = String(message?.status || "").toLowerCase();
  return Boolean(message?.message_id) && !["replied", "completed", "canceled"].includes(status);
}

function openMcpInboxMessages(provider) {
  return (provider?.messages || []).filter(isOpenMcpInboxMessage);
}

function providerTruthDetail(provider, sessions) {
  if (provider.transport === "workbench-context-mcp-inbox") {
    return [
      provider.nativeContinuity,
      provider.deliveryStatus,
      provider.clientPresence ? `client ${provider.clientPresence}` : "",
      provider.clientLatestAt ? `latest ${new Date(provider.clientLatestAt).toLocaleString()}` : "",
      provider.clientMemoryCount !== undefined ? `${provider.clientMemoryCount} context record(s)` : "",
    ].filter(Boolean).join(" · ");
  }
  if (provider.id === "kimi" && provider.bridgeMode === "cross-project-zellij") {
    return [
      `live ${provider.bridgeProjectSlug || "external"} zellij bridge`,
      provider.nativeSessionId,
      provider.model ? `model ${provider.model}` : "",
    ].filter(Boolean).join(" · ");
  }
  return [
    sessions[provider.id]?.nativeContinuity || provider.nativeContinuity || "session state pending",
    provider.model ? `model ${provider.model}` : "",
  ].filter(Boolean).join(" · ");
}

function stripTerminalAnsi(value = "") {
  return String(value)
    .replace(/\x1b\[[0-?]*[ -/]*[@-~]/g, "")
    .replace(/\x1b\][^\x07]*(\x07|\x1b\\)/g, "")
    .replace(/\r\n/g, "\n")
    .replace(/\r/g, "\n")
    .replace(/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/g, "");
}

function ageLabel(seconds) {
  const value = Number(seconds);
  if (!Number.isFinite(value)) return "";
  if (value < 60) return `${value}s`;
  const minutes = Math.round(value / 60);
  if (minutes < 60) return `${minutes}m`;
  const hours = Math.round(minutes / 60);
  return `${hours}h`;
}

function observedAgeLabel(iso) {
  const parsed = Date.parse(iso || "");
  if (!Number.isFinite(parsed)) return "";
  const seconds = Math.max(0, Math.round((Date.now() - parsed) / 1000));
  return ageLabel(seconds);
}

function providerProofLabel(provider) {
  const proof = provider.proof || {};
  if (isMcpMailboxProvider(provider) && provider.status !== "available") {
    return "real handoff path · not live until the client replies";
  }
  if (provider.status !== "available") {
    if (proof.lastSuccessAt) {
      const age = observedAgeLabel(proof.lastSuccessAt);
      return `last proof ${age || "recently"} ago · not ready now`;
    }
    return "not ready now";
  }
  if (proof.lastSuccessAt) {
    const age = observedAgeLabel(proof.lastSuccessAt);
    const chars = Number(proof.lastSuccessTextChars || proof.lastTextChars || 0);
    return `proved ${age || "recently"} ago${chars ? ` · ${chars} chars` : ""}`;
  }
  if (proof.lastObservedAt && proof.lastStatus) {
    const age = observedAgeLabel(proof.lastObservedAt);
    return `last ${proof.lastStatus} ${age || "recently"} ago`;
  }
  return "not proven in recent turns";
}

function isActiveTurnStatus(status) {
  return ["waiting", "streaming"].includes(status);
}

function turnRuntimeLabel(turn) {
  if (!isActiveTurnStatus(turn.status)) return turn.status;
  const seconds = Number(turn.activeForSeconds);
  return Number.isFinite(seconds) ? `live · ${ageLabel(seconds)}` : "live";
}

function durationLabel(ms) {
  const value = Number(ms);
  if (!Number.isFinite(value) || value < 0) return "";
  if (value < 1000) return `${Math.round(value)}ms`;
  if (value < 10_000) return `${(value / 1000).toFixed(1)}s`;
  return `${Math.round(value / 1000)}s`;
}

function responseTimingLabel(response) {
  const status = response.status || "waiting";
  const pieces = [status];
  const startedAt = Number(response.startedAtMs);
  const firstDeltaAt = Number(response.firstDeltaAtMs);
  const completedAt = Number(response.completedAtMs);
  const firstDeltaMs = Number(response.firstDeltaMs);
  const deltaCount = Number(response.deltaCount || 0);
  const streamedChars = Number(response.streamedChars || 0);
  if (Number.isFinite(startedAt) && Number.isFinite(firstDeltaAt) && firstDeltaAt >= startedAt) {
    pieces.push(`first ${durationLabel(firstDeltaAt - startedAt)}`);
  } else if (Number.isFinite(firstDeltaMs) && firstDeltaMs >= 0) {
    pieces.push(`first ${durationLabel(firstDeltaMs)}`);
  } else if (status === "streaming" && Number.isFinite(startedAt)) {
    pieces.push("waiting first delta");
  }
  if (deltaCount > 0) pieces.push(`${deltaCount} chunk${deltaCount === 1 ? "" : "s"}`);
  if (streamedChars > 0) pieces.push(`${streamedChars} chars`);
  if (response.durationMs !== undefined && response.durationMs !== null) {
    pieces.push(`total ${durationLabel(response.durationMs)}`);
  } else if (Number.isFinite(startedAt) && Number.isFinite(completedAt) && completedAt >= startedAt) {
    pieces.push(`total ${durationLabel(completedAt - startedAt)}`);
  }
  return pieces.filter(Boolean).join(" · ");
}

function responseEvidenceItems(response) {
  const meta = response?.meta || {};
  const firstDeltaMs = Number(response?.firstDeltaMs);
  const deltaCount = Number(response?.deltaCount || 0);
  const streamedChars = Number(response?.streamedChars || 0);
  const items = [
    meta.transport ? ["transport", meta.transport] : null,
    meta.sourceProvider && meta.sourceProvider !== response.provider ? ["source", meta.sourceProvider] : null,
    meta.model ? ["model", meta.model] : null,
    Number.isFinite(firstDeltaMs) && firstDeltaMs >= 0 ? ["first", durationLabel(firstDeltaMs)] : null,
    deltaCount > 0 ? ["chunks", deltaCount] : null,
    streamedChars > 0 ? ["chars", streamedChars] : null,
    response.durationMs !== undefined && response.durationMs !== null ? ["total", durationLabel(response.durationMs)] : null,
    response.status ? ["status", response.status] : null
  ];
  return items.filter(Boolean);
}

function responseEvidenceTitle(response) {
  return responseEvidenceItems(response)
    .map((item) => `${item[0]}=${item[1]}`)
    .join(" · ");
}

function traceTimeLabel(iso) {
  const parsed = Date.parse(iso || "");
  if (!Number.isFinite(parsed)) return "";
  return new Date(parsed).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" });
}

function traceEventDetail(message = {}) {
  if (message.type === "turn_started") {
    const providers = Array.isArray(message.availableProviders) ? message.availableProviders.length : 0;
    return `${providers} provider${providers === 1 ? "" : "s"}`;
  }
  if (message.type === "provider_started") return "started";
  if (message.type === "provider_meta") {
    return message.meta?.state || message.meta?.transport || "meta";
  }
  if (message.type === "delta") {
    const chars = String(message.text || "").length;
    return `${chars} char${chars === 1 ? "" : "s"}`;
  }
  if (message.type === "provider_done") {
    const chars = String(message.text || "").length;
    return ["done", message.durationMs ? durationLabel(message.durationMs) : "", chars ? `${chars} chars` : ""].filter(Boolean).join(" · ");
  }
  if (message.type === "provider_error") return message.error || "error";
  if (message.type === "provider_unavailable") return message.reason || "unavailable";
  if (message.type === "turn_stopped") return message.reason || "stopped";
  if (message.type === "turn_done") return "persisted";
  if (message.type === "turn_snapshot") return message.reason || "snapshot";
  return "";
}

function traceEntryFromMessage(message = {}) {
  if (!message.turnId || message.type === "turn_heartbeat") return null;
  const provider = message.provider || "";
  return {
    id: `${message.turnId}:${message.type}:${provider}:${Date.now()}:${Math.random().toString(16).slice(2, 8)}`,
    at: new Date().toISOString(),
    type: message.type,
    provider,
    label: message.label || provider || message.type,
    detail: traceEventDetail(message)
  };
}

function mergeTraceEvents(left = [], right = []) {
  const byId = new Map();
  for (const event of [...left, ...right]) {
    if (!event) continue;
    const key = event.id || [event.at, event.type, event.provider, event.detail].join(":");
    byId.set(key, { ...event, id: key });
  }
  return [...byId.values()]
    .sort((a, b) => String(a.at || "").localeCompare(String(b.at || "")))
    .slice(-80);
}

function traceFromPersistedTurn(record = {}) {
  const entries = [];
  const createdAt = record.createdAt || record.updatedAt || "";
  if (createdAt) {
    entries.push({
      id: `${record.turnId}:persisted-start`,
      at: createdAt,
      type: "persisted",
      provider: "beagle",
      label: "persisted",
      detail: record.status || "turn"
    });
  }
  for (const response of record.responses || []) {
    if (!response.completedAt && !record.completedAt) continue;
    entries.push({
      id: `${record.turnId}:${response.provider}:persisted-${response.status}`,
      at: response.completedAt || record.completedAt,
      type: `persisted_${response.status || "response"}`,
      provider: response.provider,
      label: response.label || response.provider,
      detail: [
        response.status || "response",
        response.deltaCount ? `${response.deltaCount} chunk${response.deltaCount === 1 ? "" : "s"}` : "",
        response.streamedChars ? `${response.streamedChars} chars` : ""
      ].filter(Boolean).join(" · ")
    });
  }
  return mergeTraceEvents(entries, []);
}

function providerRuntimeDetails(turn) {
  const runtimeByProvider = new Map((turn.providerStatuses || []).map((item) => [item.provider, item]));
  return (turn.responses || []).map((response) => {
    const runtime = runtimeByProvider.get(response.provider) || {};
    return {
      provider: response.provider,
      label: response.label || runtime.label || response.provider,
      status: runtime.status || response.status || "waiting",
      detail: responseTimingLabel(response),
      hasText: runtime.hasText ?? Boolean(response.text),
      hasError: runtime.hasError ?? Boolean(response.error)
    };
  });
}

function readinessProviderLabel(readiness, ids = []) {
  const byId = new Map((readiness?.providers || []).map((provider) => [provider.id, provider]));
  return ids
    .map((providerId) => byId.get(providerId)?.label || providerId)
    .filter(Boolean)
    .join(", ");
}

function readinessProviderDetails(readiness, ids = []) {
  const byId = new Map((readiness?.providers || []).map((provider) => [provider.id, provider]));
  return ids
    .map((providerId) => byId.get(providerId))
    .filter(Boolean)
    .map((provider) => ({
      id: provider.id,
      label: provider.label || provider.id,
      transport: provider.lastSuccessTransport || provider.transport || "",
      state: provider.state || "",
      reason: provider.reason || ""
    }));
}

function readinessVerificationLabel(item) {
  if (!item) return "not verified yet";
  const age = observedAgeLabel(item.verifiedAt || item.generatedAt);
  const providers = Array.isArray(item.providers) ? item.providers.join(", ") : "";
  return [age ? `${age} ago` : "recent", providers].filter(Boolean).join(" · ");
}

function readinessContextProofLabel(proof) {
  if (!proof?.expectedCount) return "context not verified yet";
  const age = observedAgeLabel(proof.verifiedAt);
  const count = `${proof.recalledCount || 0}/${proof.expectedCount} recalled`;
  return [count, age ? `${age} ago` : "recent"].filter(Boolean).join(" · ");
}

function readinessMcpContractLabel(proof) {
  if (!proof?.verifiedAt) return "MCP not verified yet";
  const age = observedAgeLabel(proof.verifiedAt);
  const status = proof.ok ? "contract ok" : "contract failed";
  const graph = proof.graphMatches ? `${proof.graphMatches} graph match(es)` : "";
  return [status, age ? `${age} ago` : "recent", graph].filter(Boolean).join(" · ");
}

function readinessMcpRealtimeLabel(proof) {
  if (!proof?.verifiedAt) return "MCP realtime not verified yet";
  const age = observedAgeLabel(proof.verifiedAt);
  const status = proof.ok ? "realtime ok" : "realtime failed";
  const provider = proof.provider ? `${proof.provider}` : "";
  return [status, age ? `${age} ago` : "recent", provider].filter(Boolean).join(" · ");
}

function readinessMcpCancelLabel(proof) {
  if (!proof?.verifiedAt) return "cancel not verified yet";
  const age = observedAgeLabel(proof.verifiedAt);
  const status = proof.ok ? "cancel ok" : "cancel failed";
  const provider = proof.provider ? `${proof.provider}` : "";
  return [status, age ? `${age} ago` : "recent", provider].filter(Boolean).join(" · ");
}

function readinessUiStopLabel(proof) {
  if (!proof?.verifiedAt) return "stop not verified yet";
  const age = observedAgeLabel(proof.verifiedAt);
  const status = proof.ok ? "stop ok" : "stop failed";
  const provider = proof.provider ? `${proof.provider}` : "";
  return [status, age ? `${age} ago` : "recent", provider].filter(Boolean).join(" · ");
}

function readinessMcpStdioLabel(proof) {
  if (!proof?.verifiedAt) return "STDIO bridge not verified yet";
  const age = observedAgeLabel(proof.verifiedAt);
  const status = proof.ok ? "stdio ok" : "stdio failed";
  const aliases = proof.aliasToolCount ? `${proof.aliasToolCount} alias tool(s)` : "";
  return [status, age ? `${age} ago` : "recent", aliases].filter(Boolean).join(" · ");
}

function readinessMcpClientKitLabel(proof) {
  if (!proof?.verifiedAt) return "client kit not verified yet";
  const age = observedAgeLabel(proof.verifiedAt);
  const status = proof.ok ? "kit ok" : "kit failed";
  const clients = [
    ...(proof.stdioClients || []),
    ...(proof.httpClients || [])
  ].filter(Boolean).length;
  return [status, age ? `${age} ago` : "recent", clients ? `${clients} client(s)` : ""].filter(Boolean).join(" · ");
}

function readinessMcpClientInstallLabel(proof) {
  if (!proof?.verifiedAt) return "client install not verified yet";
  const age = observedAgeLabel(proof.verifiedAt);
  const status = proof.ok ? "installed" : "install failed";
  const targets = (proof.configuredTargets || []).length;
  return [status, age ? `${age} ago` : "recent", targets ? `${targets} target(s)` : ""].filter(Boolean).join(" · ");
}

function readinessRemoteMcpTransportLabel(proof) {
  if (!proof?.verifiedAt) return "remote transport not verified yet";
  const age = observedAgeLabel(proof.verifiedAt);
  const status = proof.ok ? "remote ok" : "remote failed";
  const transports = (proof.transports || []).join(" + ");
  return [status, age ? `${age} ago` : "recent", transports].filter(Boolean).join(" · ");
}

function readinessFullGateLabel(proof) {
  if (!proof?.verifiedAt) return "full gate not verified yet";
  const age = observedAgeLabel(proof.verifiedAt);
  const status = proof.ok ? "full ok" : "full failed";
  const steps = proof.stepCount ? `${proof.stepCount} step(s)` : "";
  return [status, age ? `${age} ago` : "recent", steps].filter(Boolean).join(" · ");
}

function healthCheckItems(health) {
  const checks = health?.checks || {};
  return [
    ["turns", checks.activeTurnsClear],
    ["live", checks.minimumLiveNow],
    ["fresh context", checks.contextProofFresh],
    ["coverage", checks.contextCoversLiveNow],
    ["MCP separated", checks.subscriptionClientsSeparated],
    ["MCP contract", checks.mcpContractFresh],
    ["MCP realtime", checks.mcpRealtimeFresh],
    ["MCP cancel", checks.mcpCancelFresh],
    ["Browser send", checks.uiSendFresh],
    ["Stop", checks.uiStopFresh],
    ["MCP stdio", checks.mcpStdioFresh],
    ["MCP auth", checks.httpMcpAuthFresh],
    ["MCP remote", checks.remoteMcpTransportFresh],
    ["MCP kit", checks.mcpClientKitFresh],
    ["MCP install", checks.mcpClientInstallFresh]
  ];
}

function setupActionDetail(action) {
  if (!action) return "";
  if (Array.isArray(action.missing) && action.missing.length) {
    return `missing ${action.missing.join(", ")}`;
  }
  if (action.status === "waiting-for-client") {
    return action.targetClient
      ? `${action.targetClient} · ${action.heartbeatTool || "heartbeat"} -> ${action.inboxTool || "inbox"} -> ${action.replyTool || "reply"}`
      : action.replyTool ? `reply tool ${action.replyTool}` : "waiting for client";
  }
  return action.reason || action.summary || action.status;
}

function setupActionClass(action) {
  if (action?.status === "ready") return "ready";
  if (action?.status === "waiting-for-client") return "waiting";
  return "blocked";
}

function setupClientClass(client) {
  if (client?.status === "live") return "ready";
  if (client?.status === "stale" || String(client?.status || "").startsWith("waiting")) return "waiting";
  return "blocked";
}

function bringupClientClass(client) {
  if (client?.replyGate?.latestProof?.fresh) return "ready";
  if (client?.realConnectionObserved) return "waiting";
  if (client?.hostedHttpClient && !client?.url?.startsWith("https://")) return "blocked";
  return "waiting";
}

function publicEndpointClass(endpoint) {
  if (endpoint?.hostedClientReachable) return "ready";
  if (endpoint?.tailnet || endpoint?.https) return "waiting";
  return "blocked";
}

function publicEndpointLabel(endpoint) {
  if (!endpoint?.url) return "No public endpoint configured";
  if (endpoint.hostedClientReachable) return "Hosted clients can reach this endpoint";
  if (endpoint.tailnet) return "Tailnet only; hosted clients still need public HTTPS";
  if (!endpoint.https) return "Not HTTPS for hosted clients";
  return "Not reachable by hosted clients";
}

function subscriptionReplyGateLabel(bringup) {
  const clients = bringup?.clients || [];
  if (!clients.length) return "not configured";
  const proven = clients.filter((client) => client.replyGate?.latestProof?.fresh).length;
  if (proven === clients.length) return "real replies proven";
  const live = clients.filter((client) => client.realConnectionObserved).length;
  return `${proven}/${clients.length} replies proven · ${live}/${clients.length} connected`;
}

function subscriptionReplyProofLabel(proof) {
  if (!proof?.verifiedAt) return "real reply not proven yet";
  const age = observedAgeLabel(proof.verifiedAt);
  if (proof.fresh) {
    return `real reply proven ${age || "recently"} ago · ${proof.replyClientId || proof.targetClient}`;
  }
  if (proof.ok) {
    return `real reply proof is stale · ${age || "older"} ago`;
  }
  return "latest reply proof was rejected";
}

function providerListLabel(items = []) {
  return (Array.isArray(items) ? items : [])
    .map((item) => {
      if (typeof item === "string") return item;
      return item?.id || item?.label || item?.provider || "";
    })
    .filter(Boolean)
    .join(", ");
}

function agentProviderId(kind) {
  return `agent-terminal:${kind}`;
}

function turnHasRetryableGap(turn) {
  if (isActiveTurnStatus(turn.status)) return false;
  return (turn.responses || []).some((response) => ["error", "unavailable"].includes(response.status));
}

function statusRank(status) {
  return {
    waiting: 1,
    streaming: 2,
    interrupted: 3,
    stopped: 4,
    completed_with_errors: 5,
    done: 6
  }[status] || 0;
}

function versionMs(turn) {
  const parsed = Date.parse(turn?.updatedAt || turn?.lastRuntimeEventAt || turn?.completedAt || turn?.createdAt || "");
  return Number.isFinite(parsed) ? parsed : 0;
}

function mergeResponse(current = {}, incoming = {}) {
  const status = statusRank(incoming.status) >= statusRank(current.status)
    ? incoming.status || current.status
    : current.status || incoming.status;
  return {
    ...current,
    ...incoming,
    status,
    text: incoming.text || current.text || "",
    error: incoming.error || current.error || "",
    meta: { ...(current.meta || {}), ...(incoming.meta || {}) },
    durationMs: incoming.durationMs ?? current.durationMs,
    startedAtMs: incoming.startedAtMs ?? current.startedAtMs,
    firstDeltaAtMs: incoming.firstDeltaAtMs ?? current.firstDeltaAtMs,
    firstDeltaMs: incoming.firstDeltaMs ?? current.firstDeltaMs,
    lastDeltaAtMs: incoming.lastDeltaAtMs ?? current.lastDeltaAtMs,
    completedAtMs: incoming.completedAtMs ?? current.completedAtMs,
    deltaCount: incoming.deltaCount ?? current.deltaCount,
    streamedChars: incoming.streamedChars ?? current.streamedChars,
    stderr: incoming.stderr || current.stderr || ""
  };
}

function mergeTurn(current, incoming) {
  if (!current) return incoming;
  if (!incoming) return current;
  const incomingNewer = versionMs(incoming) >= versionMs(current);
  const status = statusRank(incoming.status) >= statusRank(current.status)
    ? incoming.status || current.status
    : current.status || incoming.status;
  const byProvider = new Map((current.responses || []).map((response) => [response.provider, response]));
  for (const response of incoming.responses || []) {
    byProvider.set(response.provider, mergeResponse(byProvider.get(response.provider), response));
  }
  return {
    ...(incomingNewer ? current : incoming),
    ...(incomingNewer ? incoming : current),
    status,
    active: isActiveTurnStatus(status) ? (incoming.active ?? current.active) === true : false,
    activeForSeconds: incoming.activeForSeconds ?? current.activeForSeconds,
    activeAgeMs: incoming.activeAgeMs ?? current.activeAgeMs,
    lastRuntimeEventAt: incoming.lastRuntimeEventAt || current.lastRuntimeEventAt || "",
    updatedAt: incoming.updatedAt || current.updatedAt || "",
    providerStatuses: incoming.providerStatuses?.length ? incoming.providerStatuses : current.providerStatuses || [],
    trace: mergeTraceEvents(current.trace || [], incoming.trace || []),
    responses: [...byProvider.values()]
  };
}

function sortTurns(items) {
  return [...items].sort((left, right) =>
    String(left.createdAt || "").localeCompare(String(right.createdAt || ""))
  );
}

function nextProviderSelection(providerList, current, serverDefault, touched) {
  const available = (providerList || [])
    .filter(isSelectableProvider)
    .map((provider) => provider.id);
  const serverDefaultAvailable = (serverDefault || []).filter((providerId) => available.includes(providerId));
  const stillValid = (current || []).filter((providerId) => available.includes(providerId));
  if (touched && stillValid.length) return stillValid;
  return serverDefaultAvailable.length ? serverDefaultAvailable : available.slice(0, 3);
}

export default function ScratchStudio() {
  const params = useParams();
  const slug = () => params.slug || "darwin-mfc";
  useTitle("Multimodel Chat");

  let chatSocket = null;
  let composerRef;
  let reconnectTimer = null;
  let reconnectAttempts = 0;
  let disposed = false;
  const agentTurnPersistTimers = new Map();

  const [providers, setProviders] = createSignal([]);
  const [nativeSessions, setNativeSessions] = createSignal({});
  const [mcpInbox, setMcpInbox] = createSignal({ providers: [] });
  const [readiness, setReadiness] = createSignal(null);
  const [health, setHealth] = createSignal(null);
  const [setup, setSetup] = createSignal(null);
  const [subscriptionBringup, setSubscriptionBringup] = createSignal(null);
  const [publicEndpointDraft, setPublicEndpointDraft] = createSignal("");
  const [publicEndpointTrusted, setPublicEndpointTrusted] = createSignal(false);
  const [publicEndpointTouched, setPublicEndpointTouched] = createSignal(false);
  const [publicEndpointStatus, setPublicEndpointStatus] = createSignal("");
  const [publicEndpointCandidates, setPublicEndpointCandidates] = createSignal(null);
  const [tailscaleFunnelPlan, setTailscaleFunnelPlan] = createSignal(null);
  const [tailscaleFunnelPathPlan, setTailscaleFunnelPathPlan] = createSignal(null);
  const [tailscaleFunnelStatus, setTailscaleFunnelStatus] = createSignal("");
  const [selectedProviders, setSelectedProviders] = createSignal([]);
  const [selectionTouched, setSelectionTouched] = createSignal(false);
  const [chatStatus, setChatStatus] = createSignal("connecting");
  const [chatConnected, setChatConnected] = createSignal(false);
  const [turns, setTurns] = createSignal([]);
  const [historyStatus, setHistoryStatus] = createSignal("loading history");
  const [draft, setDraft] = createSignal("");
  const [sending, setSending] = createSignal(false);
  const [sendNotice, setSendNotice] = createSignal("");
  const [copyStatus, setCopyStatus] = createSignal("");
  const [mcpReplyDrafts, setMcpReplyDrafts] = createSignal({});
  const [mcpReplyStatus, setMcpReplyStatus] = createSignal({});
  const [mcpCancelStatus, setMcpCancelStatus] = createSignal({});
  const [subscriptionDrillStatus, setSubscriptionDrillStatus] = createSignal({});
  const [subscriptionLiveDrills, setSubscriptionLiveDrills] = createSignal({});
  const [subscriptionRoomStatus, setSubscriptionRoomStatus] = createSignal("");
  const [subscriptionRoom, setSubscriptionRoom] = createSignal(null);
  const [realtimeVerify, setRealtimeVerify] = createSignal({ status: "idle", result: null, error: "" });
  const [conversationVerify, setConversationVerify] = createSignal({ status: "idle", result: null, error: "" });
  const [reconnectVerify, setReconnectVerify] = createSignal({ status: "idle", result: null, error: "" });

  const [agentSessions, setAgentSessions] = createSignal([]);
  const [selectedAgent, setSelectedAgent] = createSignal("");
  const [selectedTerminal, setSelectedTerminal] = createSignal("agent:codex");
  const [agentStatus, setAgentStatus] = createSignal("loading agents");
  const [syncStatus, setSyncStatus] = createSignal("");
  const [agentBridge, setAgentBridge] = createSignal(null);
  const [workspace, setWorkspace] = createSignal({ root: "", tmuxSession: "", status: "" });

  const agentTerminalProviders = createMemo(() => agentSessions().map((session) => ({
    id: agentProviderId(session.kind),
    label: session.label || `${session.kind} terminal`,
    transport: session.local ? "local-desktop-pty" : "shared-agent-pty",
    status: session.status === "running" ? "available" : "unavailable",
    command: session.command || "",
    model: "",
    nativeSessionId: session.name || "",
    nativeContinuity: session.local ? "local-desktop-subscription-cli" : "shared-agent-pty",
    repoRoot: session.workspaceAuthority || "",
    reason: session.status === "running" ? "" : `${session.kind} agent is ${session.status}`,
    agentKind: session.kind,
    terminalProvider: true
  })));
  const visibleProviders = createMemo(() => {
    const byId = new Map();
    for (const provider of [
      ...providers().filter((item) => !isHiddenCrossProjectProvider(item)),
      ...agentTerminalProviders()
    ]) {
      if (!byId.has(provider.id)) byId.set(provider.id, provider);
    }
    return [...byId.values()];
  });
  const availableProviders = createMemo(() => visibleProviders().filter(isSelectableProvider));
  const unavailableProviders = createMemo(() => visibleProviders().filter((provider) => !isSelectableProvider(provider)));
  const selectedAvailableProviderIds = createMemo(() => selectedProviders().filter((providerId) =>
    availableProviders().some((provider) => provider.id === providerId)
  ));
  const selectedProviderLabel = createMemo(() => selectedAvailableProviderIds().join(", ") || "none");
  const selectedVerifiableProviderIds = createMemo(() => selectedAvailableProviderIds().filter((providerId) =>
    visibleProviders().some((provider) => provider.id === providerId && isRealtimeVerifiableProvider(provider))
  ));
  const canSendChat = createMemo(() =>
    Boolean(draft().trim()) && selectedAvailableProviderIds().length > 0 && chatConnected() && !sending()
  );
  const subscriptionConnectorClients = createMemo(() => {
    const bringupClients = subscriptionBringup()?.clients || [];
    if (bringupClients.length) return bringupClients.map(subscriptionClientViewModel);

    const setupClients = setup()?.subscriptionClients || [];
    if (setupClients.length) return setupClients.map(subscriptionClientViewModel);

    const inboxClients = (mcpInbox().providers || []).map((provider) => subscriptionClientViewModel({
      id: provider.provider_id || provider.targetClient,
      provider: provider.provider_id || provider.targetClient,
      targetClient: provider.targetClient || provider.provider_id,
      label: provider.label,
      status: provider.clientPresence || "waiting",
      realConnectionObserved: provider.clientPresence === "live",
      reason: provider.counts?.open ? `${provider.counts.open} open MCP handoff(s)` : "waiting for MCP client heartbeat"
    }));
    if (inboxClients.length) return inboxClients;

    return DEFAULT_SUBSCRIPTION_CONNECTORS.map(subscriptionClientViewModel);
  });
  const sendBlockReason = createMemo(() => {
    if (!draft().trim()) return "Write a message first.";
    if (!chatConnected()) return "Chat socket is not connected yet.";
    if (selectedAvailableProviderIds().length === 0) return "Select at least one live provider.";
    if (sending()) return "Sending current turn.";
    return "";
  });
  const canVerifyRealtime = createMemo(() =>
    selectedVerifiableProviderIds().length > 0 && realtimeVerify().status !== "running"
  );
  const canVerifyConversation = createMemo(() =>
    selectedVerifiableProviderIds().length > 0 && conversationVerify().status !== "running"
  );
  const canVerifyReconnect = createMemo(() =>
    selectedVerifiableProviderIds().length > 0 && reconnectVerify().status !== "running"
  );
  const activeTurnIds = createMemo(() => turns().filter((turn) => isActiveTurnStatus(turn.status)).map((turn) => turn.id));
  const pendingMcpHandoffs = createMemo(() => turns().flatMap((turn) =>
    (turn.responses || [])
      .filter(isPendingMcpHandoff)
      .map((response) => ({
        turnId: turn.id,
        turnMessage: turn.message,
        provider: response.provider,
        label: response.label || response.provider,
        status: response.status,
        activeForSeconds: turn.activeForSeconds,
        handoff: mcpHandoffDetail(response, slug())
      }))
  ));
  const runningAgents = createMemo(() => agentSessions().filter((session) => session.status === "running"));
  const currentAgent = createMemo(() =>
    agentSessions().find((session) => session.kind === selectedAgent())
    || runningAgents()[0]
    || agentSessions()[0]
    || null
  );
  const canSendToAgentTerminal = createMemo(() =>
    Boolean(draft().trim()) && currentAgent()?.status === "running" && chatConnected() && !sending()
  );

  async function copyText(text, label = "Copied") {
    const value = String(text || "");
    if (!value) return;
    try {
      if (navigator.clipboard?.writeText) {
        await navigator.clipboard.writeText(value);
      } else {
        const textarea = document.createElement("textarea");
        textarea.value = value;
        textarea.setAttribute("readonly", "");
        textarea.style.position = "fixed";
        textarea.style.opacity = "0";
        document.body.appendChild(textarea);
        textarea.select();
        document.execCommand("copy");
        document.body.removeChild(textarea);
      }
      setCopyStatus(label);
      setSendNotice(label);
      setTimeout(() => setCopyStatus(""), 2400);
    } catch (error) {
      const message = `Copy failed: ${error.message}`;
      setCopyStatus(message);
      setSendNotice(message);
      setTimeout(() => setCopyStatus(""), 3200);
    }
  }

  function copyMcpReplyArgs(handoff) {
    copyText(JSON.stringify(mcpReplyArgs(handoff), null, 2), "MCP reply args copied.");
  }

  async function copyMcpPacket(handoff) {
    try {
      const packet = await fetchJson(`/api/workbench/${slug()}/context/messages/${encodeURIComponent(handoff.messageId)}/compile`, {
        timeoutMs: 12000
      });
      await copyText(formatMcpHandoffPacket(packet, handoff), "MCP handoff packet copied.");
    } catch (error) {
      const message = `Packet copy failed: ${error.message}`;
      setCopyStatus(message);
      setSendNotice(message);
      setTimeout(() => setCopyStatus(""), 3200);
    }
  }

  function copyMcpActivationPrompt(handoff) {
    copyText(formatMcpActivationPrompt(handoff, slug()), `${handoff?.target || "MCP client"} activation prompt copied.`);
  }

  function clientConnectPayload(client) {
    const connect = client?.connect || {};
    return JSON.stringify({
      client: {
        id: client?.id || "",
        targetClient: client?.targetClient || "",
        provider: client?.provider || "",
        surface: connect.surface || ""
      },
      mcp: connect.mcpServer || {
        url: client?.url || "",
        headers: client?.headers || {},
        tokenFile: client?.auth?.tokenFile || ""
      },
      registration: connect.registration || null,
      firstToolCalls: connect.firstToolCalls || [],
      liveCriteria: connect.liveCriteria || [],
      operatorPrompt: connect.operatorPrompt || ""
    }, null, 2);
  }

  function clientSetupText(client) {
    const connect = client?.connect || {};
    if (connect.setupText) return connect.setupText;
    const targetClient = client?.targetClient || client?.id || "subscription-client";
    const mcp = connect.mcpServer || {};
    const registration = connect.registration || {};
    const headers = mcp.headers || client?.headers || {};
    const toolCalls = connect.firstToolCalls || [];
    return [
      `Beagle Workbench MCP setup for ${connect.surface || client?.label || targetClient}`,
      "",
      "Register this MCP server in the real subscription client. This is not a model API route.",
      "",
      `Name: ${registration.name || `beagle-workbench-${slug()}`}`,
      `Transport: ${registration.transport || client?.preferredTransport || "streamable-http+sse"}`,
      `URL: ${mcp.url || client?.url || ""}`,
      "",
      "Headers:",
      ...Object.entries(headers)
        .filter(([, value]) => String(value || "").trim())
        .map(([key, value]) => `- ${key}: ${value}`),
      "",
      mcp.tokenInstruction || "Replace <workbench-context-token> with the local Workbench Context bearer token.",
      "",
      "After connecting, use MCP tools in this order:",
      ...toolCalls.map((call, index) => `${index + 1}. ${call.tool} ${JSON.stringify(call.args || {})}`),
      "",
      "Proof rules:",
      "- Beagle marks this live only after a fresh real client heartbeat or MCP reply.",
      "- Probe traffic, fixture replies, manual paste, and direct debug endpoints do not count.",
      "",
      client.verifyCommand || `CLIENT=${targetClient} npm run verify:multimodel:subscription-live ${slug()}`,
      client.replyGate?.verifyCommand || client.replyVerifyCommand || `CLIENT=${targetClient} npm run verify:multimodel:subscription-reply-live ${slug()}`
    ].join("\n");
  }

  async function copyClientConnectPlan(client) {
    await copyText(clientConnectPayload(client), `${client?.targetClient || client?.id || "client"} connection plan copied.`);
  }

  async function copyClientSetupText(client) {
    await copyText(clientSetupText(client), `${client?.targetClient || client?.id || "client"} setup text copied.`);
  }

  function subscriptionActivationPrompt(client, drill) {
    if (drill?.activation?.modelPrompt) return drill.activation.modelPrompt;
    const targetClient = client?.targetClient || client?.id || "subscription-client";
    const messageId = drill?.message?.message_id || "";
    const marker = drill?.message?.marker || "";
    const replyTool = targetClient === "claude-desktop" ? "cockpit_workbench_context_reply" : "workbench_context_reply";
    return [
      `You are the real ${targetClient} subscription client for Beagle Workbench project ${slug()}.`,
      "Use MCP tools only for the handoff; do not answer in ordinary chat.",
      "",
      `1. Call workbench_context_join with client_id=${targetClient}.`,
      `2. Read the handoff message_id=${messageId}.`,
      `3. Reply through ${replyTool} with message_id=${messageId}, client_id=${targetClient}, and text mentioning ${marker}.`,
      "",
      "The reply must be written through the MCP reply tool so Beagle can mark this as real."
    ].join("\n");
  }

  async function copySubscriptionActivationPrompt(client, drill) {
    await copyText(
      subscriptionActivationPrompt(client, drill),
      `${client?.targetClient || client?.id || "client"} activation prompt copied.`
    );
  }

  function mcpReplyDraft(messageId) {
    return mcpReplyDrafts()[messageId] || "";
  }

  function mcpReplyState(messageId) {
    return mcpReplyStatus()[messageId] || "";
  }

  function setMcpReplyDraft(messageId, value) {
    setMcpReplyDrafts((current) => ({
      ...current,
      [messageId]: value
    }));
  }

  function setMcpReplyState(messageId, value) {
    setMcpReplyStatus((current) => ({
      ...current,
      [messageId]: value
    }));
  }

  function mcpCancelState(messageId) {
    return mcpCancelStatus()[messageId] || "";
  }

  function setMcpCancelState(messageId, value) {
    setMcpCancelStatus((current) => ({
      ...current,
      [messageId]: value
    }));
  }

  async function submitMcpReply(handoff) {
    const text = mcpReplyDraft(handoff.messageId).trim();
    if (!text) {
      setMcpReplyState(handoff.messageId, "Paste a debug reply first.");
      return;
    }
    setMcpReplyState(handoff.messageId, "Sending developer paste...");
    try {
      await fetchJson(handoff.directReplyEndpoint, {
        method: "POST",
        timeoutMs: 15000,
        body: {
          client_id: handoff.target,
          text,
          metadata: {
            reply_path: "developer-mcp-paste-ui",
            operator_ui: true,
            truthMode: "observed-developer-mcp-paste-reply"
          }
        }
      });
      setMcpReplyDraft(handoff.messageId, "");
      setMcpReplyState(handoff.messageId, "Reply written to Workbench Context.");
      setSendNotice("Developer MCP paste written to Workbench Context.");
      refreshMcpInbox();
      refreshHistory();
    } catch (error) {
      const message = `Reply failed: ${error.message}`;
      setMcpReplyState(handoff.messageId, message);
      setSendNotice(message);
    }
  }

  async function cancelMcpInboxMessage(message) {
    const messageId = message?.message_id;
    if (!messageId) return;
    setMcpCancelState(messageId, "Canceling...");
    try {
      await fetchJson(`/api/projects/${slug()}/multimodel/mcp-inbox/${encodeURIComponent(messageId)}/cancel`, {
        method: "POST",
        timeoutMs: 12000,
        body: {
          client_id: "beagle-studio",
          providerId: message.provider_id || "",
          reason: "canceled from Beagle Studio",
          metadata: {
            operator_ui: true,
            truthMode: "observed-operator-cancel"
          }
        }
      });
      setMcpCancelState(messageId, "Canceled.");
      setSendNotice("MCP handoff canceled.");
      refreshMcpInbox();
      refreshHistory();
      refreshReadiness();
      refreshHealth();
    } catch (error) {
      const notice = `Cancel failed: ${error.message}`;
      setMcpCancelState(messageId, notice);
      setSendNotice(notice);
    }
  }
  const hasLiveWorkspace = createMemo(() => workspace().status === "live" && workspace().tmuxSession);

  function turnFromRecord(record) {
    return {
      id: record.turnId,
      message: record.message,
      createdAt: record.createdAt,
      updatedAt: record.updatedAt || record.lastRuntimeEventAt || record.completedAt || record.createdAt || "",
      completedAt: record.completedAt || "",
      status: record.status || "done",
      active: record.active === true,
      activeForSeconds: record.activeForSeconds,
      activeAgeMs: record.activeAgeMs,
      lastRuntimeEventAt: record.lastRuntimeEventAt || record.updatedAt || "",
      providerStatuses: record.providerStatuses || [],
      providers: record.providers || [],
      trace: Array.isArray(record.trace) && record.trace.length ? record.trace : traceFromPersistedTurn(record),
      persisted: true,
      responses: (record.responses || []).map((response) => ({
        provider: response.provider,
        label: response.label || response.provider,
        status: response.status || "done",
        text: response.text || "",
        error: response.error || "",
        meta: response.meta || {},
        durationMs: response.durationMs,
        firstDeltaMs: response.firstDeltaMs,
        deltaCount: response.deltaCount,
        streamedChars: response.streamedChars,
        stderr: response.stderr || ""
      }))
    };
  }

  function updateTurn(turnId, updater) {
    setTurns((items) => items.map((turn) => turn.id === turnId ? updater(turn) : turn));
  }

  function appendTurnTrace(turnId, entry) {
    if (!turnId || !entry) return;
    updateTurn(turnId, (turn) => ({
      ...turn,
      trace: mergeTraceEvents(turn.trace || [], [entry])
    }));
  }

  function upsertTurn(turn) {
    if (!turn?.id) return;
    setTurns((items) => {
      const next = new Map(items.map((item) => [item.id, item]));
      next.set(turn.id, mergeTurn(next.get(turn.id), turn));
      return sortTurns(next.values());
    });
  }

  function updateProvider(turnId, providerId, updater) {
    updateTurn(turnId, (turn) => ({
      ...turn,
      responses: turn.responses.some((response) => response.provider === providerId)
        ? turn.responses.map((response) =>
            response.provider === providerId ? updater(response) : response
          )
        : [
            ...turn.responses,
            updater({
              provider: providerId,
              label: providerId,
              status: "waiting",
              text: "",
              error: "",
              meta: {}
            })
          ]
    }));
  }

  function updateAgentTerminalResponse(turnId, providerId, updater, timestamp = new Date().toISOString()) {
    updateTurn(turnId, (turn) => {
      const responses = turn.responses.some((response) => response.provider === providerId)
        ? turn.responses.map((response) => response.provider === providerId ? updater(response) : response)
        : [
            ...turn.responses,
            updater({
              provider: providerId,
              label: providerId,
              status: "waiting",
              text: "",
              error: "",
              meta: {}
            })
          ];
      const finished = responses.every((response) => ["done", "error", "unavailable"].includes(response.status));
      const hasError = responses.some((response) => response.status === "error");
      return {
        ...turn,
        responses,
        status: finished ? (hasError ? "completed_with_errors" : "done") : "streaming",
        active: !finished,
        updatedAt: timestamp,
        completedAt: finished ? timestamp : turn.completedAt || "",
        lastRuntimeEventAt: timestamp
      };
    });
  }

  function connectChat() {
    if (reconnectTimer) {
      clearTimeout(reconnectTimer);
      reconnectTimer = null;
    }
    if (chatSocket) {
      chatSocket.onclose = null;
      chatSocket.onerror = null;
      chatSocket.onmessage = null;
      chatSocket.close();
    }
    setChatConnected(false);
    setChatStatus("connecting");
    const protocol = location.protocol === "https:" ? "wss:" : "ws:";
    chatSocket = new WebSocket(`${protocol}//${location.host}/ws/projects/${slug()}/multimodel-chat`);

    chatSocket.onopen = () => {
      reconnectAttempts = 0;
      setChatConnected(true);
      setChatStatus("connected");
      setSendNotice("");
    };
    chatSocket.onclose = () => {
      setChatConnected(false);
      setChatStatus("disconnected · reconnecting");
      setSending(false);
      setSendNotice("Chat socket disconnected; reconnecting.");
      refreshHistory();
      scheduleReconnect();
    };
    chatSocket.onerror = () => {
      setChatConnected(false);
      setChatStatus("connection failed");
      setSending(false);
      setSendNotice("Chat socket failed; reconnecting.");
      scheduleReconnect();
    };
    chatSocket.onmessage = (event) => {
      let message;
      try {
        message = JSON.parse(event.data);
      } catch {
        return;
      }
      handleChatEvent(message);
    };
  }

  function scheduleReconnect() {
    if (disposed || reconnectTimer) return;
    const delay = Math.min(8000, 1000 * (2 ** reconnectAttempts));
    reconnectAttempts += 1;
    reconnectTimer = setTimeout(() => {
      reconnectTimer = null;
      connectChat();
    }, delay);
  }

  function handleChatEvent(message) {
    if (message.type === "ready") {
      setProviders(message.providers || []);
      setSelectedProviders((current) => {
        return nextProviderSelection(message.providers || [], current, message.defaultProviders || [], selectionTouched());
      });
      setChatConnected(true);
      setChatStatus("connected");
      return;
    }

    if (message.type === "providers_snapshot") {
      setProviders(message.providers || []);
      setSelectedProviders((current) => {
        return nextProviderSelection(message.providers || [], current, message.defaultProviders || [], selectionTouched());
      });
      const client = message.clientId ? `${message.clientId} ` : "";
      setChatStatus(`${client}presence updated`);
      refreshMcpInbox();
      return;
    }

    if (message.type === "turn_started") {
      appendTurnTrace(message.turnId, traceEntryFromMessage(message));
      updateTurn(message.turnId, (turn) => ({
        ...turn,
        status: "streaming",
        providers: message.providers || turn.providers
      }));
      setSendNotice(`Streaming ${providerListLabel(message.providers) || "selected providers"}.`);
      for (const item of message.unavailableProviders || []) {
        updateProvider(message.turnId, item.id, (response) => ({
          ...response,
          status: "unavailable",
          error: item.reason || "unavailable"
        }));
      }
      return;
    }

    if (message.type === "turn_snapshot" && message.turn) {
      upsertTurn({ ...turnFromRecord(message.turn), persisted: false, detached: message.detached === true });
      appendTurnTrace(message.turnId, traceEntryFromMessage(message));
      return;
    }

    if (message.type === "mcp_reply_observed" || message.type === "mcp_lifecycle_observed") {
      const label = message.kind && message.kind !== "reply" ? `MCP ${message.kind}` : "MCP reply";
      setChatStatus(`${label} observed · ${message.status || "refreshing"}`);
      refreshMcpInbox();
      refreshHistory();
      return;
    }

    if (message.type === "turn_heartbeat") {
      updateTurn(message.turnId, (turn) => ({
        ...turn,
        status: message.status || turn.status,
        active: true,
        activeForSeconds: message.activeForSeconds,
        activeAgeMs: message.activeAgeMs,
        lastRuntimeEventAt: message.lastRuntimeEventAt || turn.lastRuntimeEventAt,
        providerStatuses: message.providerStatuses || turn.providerStatuses || []
      }));
      return;
    }

    if (message.type === "provider_started") {
      const now = Date.now();
      appendTurnTrace(message.turnId, traceEntryFromMessage(message));
      updateProvider(message.turnId, message.provider, (response) => ({
        ...response,
        label: message.label || response.label,
        status: "streaming",
        startedAt: now,
        startedAtMs: now,
        firstDeltaAtMs: response.firstDeltaAtMs,
        lastDeltaAtMs: response.lastDeltaAtMs,
        deltaCount: response.deltaCount || 0,
        streamedChars: response.streamedChars || 0,
        meta: {
          ...(response.meta || {}),
          ...(message.meta || {}),
          sourceProvider: message.sourceProvider || message.meta?.sourceProvider || response.meta?.sourceProvider || ""
        }
      }));
      return;
    }

    if (message.type === "provider_unavailable") {
      appendTurnTrace(message.turnId, traceEntryFromMessage(message));
      updateProvider(message.turnId, message.provider, (response) => ({
        ...response,
        label: message.label || response.label,
        status: "unavailable",
        error: message.reason || "unavailable"
      }));
      return;
    }

    if (message.type === "delta") {
      const now = Date.now();
      const text = message.text || "";
      appendTurnTrace(message.turnId, traceEntryFromMessage(message));
      updateProvider(message.turnId, message.provider, (response) => ({
        ...response,
        label: message.label || response.label,
        status: "streaming",
        text: `${response.text || ""}${text}`,
        firstDeltaAtMs: response.firstDeltaAtMs || now,
        lastDeltaAtMs: now,
        deltaCount: (response.deltaCount || 0) + 1,
        streamedChars: (response.streamedChars || 0) + text.length
      }));
      return;
    }

    if (message.type === "provider_meta") {
      appendTurnTrace(message.turnId, traceEntryFromMessage(message));
      updateProvider(message.turnId, message.provider, (response) => ({
        ...response,
        label: message.label || response.label,
        meta: { ...(response.meta || {}), ...(message.meta || {}) }
      }));
      return;
    }

    if (message.type === "provider_done") {
      const now = Date.now();
      appendTurnTrace(message.turnId, traceEntryFromMessage(message));
      updateProvider(message.turnId, message.provider, (response) => ({
        ...response,
        label: message.label || response.label,
        status: "done",
        text: message.text || response.text,
        durationMs: message.durationMs,
        completedAtMs: now,
        stderr: message.stderr || "",
        meta: { ...(response.meta || {}), ...(message.meta || {}) }
      }));
      return;
    }

    if (message.type === "provider_error") {
      const now = Date.now();
      appendTurnTrace(message.turnId, traceEntryFromMessage(message));
      updateProvider(message.turnId, message.provider, (response) => ({
        ...response,
        label: message.label || response.label,
        status: "error",
        text: message.text || response.text,
        error: message.error || message.stderr || "provider error",
        durationMs: message.durationMs,
        completedAtMs: now,
        meta: { ...(response.meta || {}), ...(message.meta || {}) }
      }));
      return;
    }

    if (message.type === "turn_stopped") {
      appendTurnTrace(message.turnId, traceEntryFromMessage(message));
      updateTurn(message.turnId, (turn) => ({
        ...turn,
        status: "stopped",
        responses: turn.responses.map((response) => (
          ["waiting", "streaming"].includes(response.status)
            ? { ...response, status: "error", error: response.error || message.reason || "stopped by user" }
            : response
        ))
      }));
      setSending(false);
      refreshNativeSessions();
      return;
    }

    if (message.type === "turn_done") {
      appendTurnTrace(message.turnId, traceEntryFromMessage(message));
      updateTurn(message.turnId, (turn) => {
        const inferredStatus = (turn.responses || []).some((response) => ["error", "unavailable"].includes(response.status))
          ? "completed_with_errors"
          : "done";
        const status = message.status || inferredStatus;
        return {
          ...turn,
          status,
          active: false,
          persisted: true,
          completedAt: turn.completedAt || new Date().toISOString()
        };
      });
      setSending(false);
      setSendNotice(message.status === "completed_with_errors" ? "Turn complete with provider errors." : "Turn complete.");
      refreshNativeSessions();
      refreshProviders();
      return;
    }

    if (message.type === "stopped") {
      const stoppedTurnIds = Array.isArray(message.turnIds) ? message.turnIds.filter(Boolean) : [];
      if (stoppedTurnIds.length) {
        for (const turnId of stoppedTurnIds) markTurnStopped(turnId);
      } else {
        markStreamingTurnsStopped();
      }
      setChatStatus("stopped");
      setSending(false);
      setSendNotice("Stopped.");
      refreshNativeSessions();
      return;
    }

    if (message.type === "error") {
      setChatStatus(message.error || "chat error");
      setSending(false);
      setSendNotice(message.error || "Chat error.");
    }
  }

  function toggleProvider(providerId) {
    setSelectionTouched(true);
    setSelectedProviders((current) =>
      current.includes(providerId)
        ? current.filter((item) => item !== providerId)
        : [...current, providerId]
    );
  }

  function selectReadyProviders() {
    setSelectionTouched(true);
    setSelectedProviders(availableProviders().map((provider) => provider.id));
  }

  function selectCoreProviders() {
    setSelectionTouched(true);
    const core = ["claude", "codex", "cursor"];
    setSelectedProviders(core.filter((providerId) =>
      availableProviders().some((provider) => provider.id === providerId)
    ));
  }

  function clearProviderSelection() {
    setSelectionTouched(true);
    setSelectedProviders([]);
  }

  function markStreamingTurnsStopped() {
    setTurns((items) => items.map((turn) => {
      if (!["waiting", "streaming"].includes(turn.status)) return turn;
      return {
        ...turn,
        status: "stopped",
        responses: turn.responses.map((response) => (
          ["waiting", "streaming"].includes(response.status)
            ? { ...response, status: "error", error: response.error || "stopped by user" }
            : response
        ))
      };
    }));
  }

  function markTurnStopped(turnId) {
    updateTurn(turnId, (turn) => ({
      ...turn,
      status: "stopped",
      active: false,
      responses: turn.responses.map((response) => (
        ["waiting", "streaming"].includes(response.status)
          ? { ...response, status: "error", error: response.error || "stopped by user" }
          : response
      ))
    }));
  }

  function chatHistory() {
    return turns().slice(-8).flatMap((turn) => [
      { role: "user", text: turn.message },
      ...turn.responses
        .filter((response) => response.status === "done" && response.text)
        .map((response) => ({ role: "assistant", provider: response.provider, text: `${response.label}: ${response.text}` }))
    ]);
  }

  function availableRetryProviderIds(turn) {
    const available = new Set(availableProviders().map((provider) => provider.id));
    const original = (turn.responses || [])
      .map((response) => response.provider)
      .filter((providerId) => available.has(providerId));
    return original.length ? [...new Set(original)] : selectedAvailableProviderIds();
  }

  function startChatTurn(text, providerIds, history = chatHistory()) {
    const messageText = text.trim();
    const selected = (providerIds || []).filter((providerId) =>
      availableProviders().some((provider) => provider.id === providerId)
    );
    if (!messageText) {
      setSendNotice("Write a message first.");
      return false;
    }
    if (selected.length === 0) {
      setSendNotice("No live provider is selected.");
      return false;
    }
    if (chatSocket?.readyState !== WebSocket.OPEN) {
      setSendNotice("Chat socket is reconnecting. Try again in a moment.");
      connectChat();
      return false;
    }

    const turnId = id();
    const selectedProviderModels = visibleProviders().filter((provider) => selected.includes(provider.id));
    setSending(true);
    setSendNotice(`Sent to ${selected.join(", ")}.`);
    setTurns((items) => [
      ...items,
      {
        id: turnId,
        message: messageText,
        createdAt: new Date().toISOString(),
        status: "waiting",
        providers: selectedProviderModels,
        trace: [{
          id: `${turnId}:queued`,
          at: new Date().toISOString(),
          type: "queued",
          provider: "beagle",
          label: "queued",
          detail: selected.join(", ")
        }],
        responses: selectedProviderModels.map((provider) => ({
          provider: provider.id,
          label: provider.label,
          status: "waiting",
          text: "",
          error: "",
          meta: provider.terminalProvider
            ? { transport: provider.transport || "shared-agent-pty", agentKind: provider.agentKind, state: "waiting-for-agent-chat" }
            : {}
        }))
      }
    ]);
    try {
      chatSocket.send(JSON.stringify({
        type: "chat",
        turnId,
        message: messageText,
        providers: selected,
        history,
        enableSynthesis: false
      }));
    } catch (error) {
      setSending(false);
      setSendNotice(`Send failed: ${error.message}`);
      updateTurn(turnId, (turn) => ({
        ...turn,
        status: "completed_with_errors",
        responses: turn.responses.map((response) => ({
          ...response,
          status: "error",
          error: response.error || error.message
        }))
      }));
      return false;
    }
    return true;
  }

  function sendChat() {
    const text = draft().trim();
    if (startChatTurn(text, selectedAvailableProviderIds())) setDraft("");
  }

  function startSubscriptionReplyDrill(client) {
    const providerId = client?.id || "";
    if (!providerId) return;
    if (sending()) {
      setSubscriptionDrillStatus((current) => ({ ...current, [providerId]: "Stop the current turn before starting another drill." }));
      return;
    }
    const marker = `subscription-reply-drill-${Date.now()}-${Math.random().toString(16).slice(2)}`;
    const text = [
      `Subscription reply drill ${marker}.`,
      `Target client: ${client.targetClient || providerId}.`,
      "Reply through Workbench Context with the marker above and one concrete sentence.",
      "Do not use the developer paste bridge."
    ].join("\n");
    const ok = startChatTurn(text, [providerId], chatHistory());
    setSubscriptionDrillStatus((current) => ({
      ...current,
      [providerId]: ok ? `waiting for ${client.targetClient || providerId} · ${marker}` : sendNotice()
    }));
  }

  function liveDrillFor(client) {
    const key = client?.id || client?.targetClient || "";
    const drill = subscriptionLiveDrills()[key] || null;
    if (drill) return drill;
    const messageId = activeSubscriptionLiveDrillMessageId();
    const target = client?.targetClient || client?.id || "";
    if (!messageId || !target) return null;
    const parts = messageId.split(":");
    const messageTarget = parts[2] || "";
    if (messageTarget !== target && messageTarget !== client?.id) return null;
    return {
      ok: true,
      status: "loading",
      phases: {
        connect: false,
        sent: true,
        acknowledged: false,
        claimed: false,
        heartbeat: false,
        replied: false,
        completed: false,
        canceled: false
      },
      message: {
        message_id: messageId,
        marker: parts.slice(3, -1).join(":") || ""
      },
      nextAction: "Loading live drill status from Workbench Context."
    };
  }

  async function refreshSubscriptionLiveDrill(client, messageId = "") {
    const key = client?.id || client?.targetClient || "";
    const target = client?.targetClient || client?.id || "";
    if (!key || !target) return null;
    try {
      const suffix = messageId ? `?message_id=${encodeURIComponent(messageId)}` : "";
      const data = await fetchJson(`/api/projects/${slug()}/multimodel/subscription-clients/${encodeURIComponent(target)}/live-drill${suffix}`, {
        timeoutMs: 10000
      });
      setSubscriptionLiveDrills((current) => ({ ...current, [key]: data }));
      return data;
    } catch (error) {
      const data = {
        ok: false,
        status: "error",
        error: error.message,
        generatedAt: new Date().toISOString()
      };
      setSubscriptionLiveDrills((current) => ({ ...current, [key]: data }));
      return data;
    }
  }

  async function startSubscriptionLiveDrill(client) {
    const key = client?.id || client?.targetClient || "";
    const target = client?.targetClient || client?.id || "";
    if (!key || !target) return;
    setSubscriptionLiveDrills((current) => ({
      ...current,
      [key]: {
        ...(current[key] || {}),
        status: "creating",
        nextAction: "Creating live drill handoff."
      }
    }));
    try {
      const result = await fetchJson(`/api/projects/${slug()}/multimodel/subscription-clients/${encodeURIComponent(target)}/live-drill`, {
        method: "POST",
        timeoutMs: 15000,
        body: {}
      });
      setSubscriptionLiveDrills((current) => ({ ...current, [key]: result.status || result }));
      setSendNotice(`Live drill opened for ${client.label || target}.`);
      refreshMcpInbox();
      refreshSubscriptionBringup();
    } catch (error) {
      setSubscriptionLiveDrills((current) => ({
        ...current,
        [key]: {
          ok: false,
          status: "error",
          error: error.message,
          nextAction: "Live drill failed to start."
        }
      }));
      setSendNotice(`Live drill failed: ${error.message}`);
    }
  }

  async function createSubscriptionRoomFile({ revealToken = false } = {}) {
    setSubscriptionRoomStatus(revealToken ? "Writing local subscription room with token..." : "Writing redacted subscription room...");
    try {
      const result = await fetchJson(`/api/projects/${slug()}/multimodel/subscription-clients/room`, {
        method: "POST",
        timeoutMs: 45000,
        body: {
          clients: "all",
          drill: true,
          revealToken
        }
      });
      setSubscriptionRoom(result);
      setSubscriptionRoomStatus(result.nextAction || "Subscription room written.");
      setSendNotice(`Subscription room written: ${result.roomFile}`);
      refreshMcpInbox();
      refreshSubscriptionBringup();
      for (const item of result.items || []) {
        const client = subscriptionConnectorClients().find((candidate) => (
          candidate.id === item.providerId ||
          candidate.id === item.clientId ||
          candidate.targetClient === item.clientId
        ));
        if (client && item.drill?.messageId) {
          refreshSubscriptionLiveDrill(client, item.drill.messageId);
        }
      }
    } catch (error) {
      setSubscriptionRoomStatus(`Subscription room failed: ${error.message}`);
      setSubscriptionRoom({ ok: false, error: error.message });
    }
  }

  function sendDraftToAgentTerminal() {
    const agent = currentAgent();
    const providerId = agent?.kind ? agentProviderId(agent.kind) : "";
    const text = draft().trim();
    if (!text) {
      setSendNotice("Write a message first.");
      return;
    }
    if (!providerId) {
      setSendNotice("No running agent terminal is selected.");
      return;
    }
    if (text && startChatTurn(text, [providerId])) setDraft("");
  }

  async function refreshAgentTerminalSnapshot(kind = currentAgent()?.kind) {
    if (!kind) return;
    try {
      const snapshot = await fetchJson(`/api/projects/${slug()}/agent/session/${kind}/terminal?tailBytes=2200`, { timeoutMs: 8000 });
      setAgentBridge((current) => ({
        ...(current || {}),
        kind,
        status: snapshot.status || current?.status || "observed",
        podName: snapshot.podName || current?.podName || "",
        attachedSockets: snapshot.attachedSockets ?? current?.attachedSockets ?? 0,
        startedAt: snapshot.startedAt || current?.startedAt || "",
        lastInputAt: snapshot.lastInputAt || current?.lastInputAt || "",
        lastOutputAt: snapshot.lastOutputAt || current?.lastOutputAt || "",
        plainTail: snapshot.plainTail || "",
        terminalState: snapshot.terminalState || null
      }));
    } catch (error) {
      setAgentBridge((current) => ({
        ...(current || {}),
        kind,
        status: "stale",
        error: error.message
      }));
    }
  }

  async function continueAgentTrustPrompt(kind = currentAgent()?.kind) {
    if (!kind) {
      setSyncStatus("no agent selected");
      return;
    }
    setSyncStatus(`continuing ${kind} trust prompt`);
    try {
      await fetchJson(`/api/projects/${slug()}/agent/session/${kind}/input`, {
        method: "POST",
        timeoutMs: 8000,
        body: { data: "\r", confirmed: true },
      });
      await refreshAgentTerminalSnapshot(kind);
      setSyncStatus(`${kind} trust prompt continued`);
    } catch (error) {
      setSyncStatus(`trust prompt failed: ${error.message}`);
    }
  }

  async function persistAgentTerminalTurn(payload) {
    if (!payload?.turnId) return;
    try {
      await fetchJson(`/api/projects/${slug()}/multimodel/turns/agent-terminal`, {
        method: "POST",
        timeoutMs: 10000,
        body: payload,
      });
    } catch (error) {
      setSyncStatus(`agent history failed: ${error.message}`);
    }
  }

  function scheduleAgentTerminalTurnPersist(current, overrides = {}) {
    if (!current?.turnId) return;
    if (agentTurnPersistTimers.has(current.turnId)) {
      clearTimeout(agentTurnPersistTimers.get(current.turnId));
    }
    const payload = {
      turnId: current.turnId,
      message: turns().find((turn) => turn.id === current.turnId)?.message || "",
      kind: current.kind,
      providerId: current.providerId || agentProviderId(current.kind),
      status: "done",
      responseStatus: "done",
      text: current.plainTail || "",
      meta: {
        podName: current.podName || "",
        attachedSockets: current.attachedSockets || 0,
        lastInputAt: current.lastInputAt || "",
        lastOutputAt: current.lastOutputAt || "",
        state: "terminal-output-observed"
      },
      ...overrides
    };
    const timer = setTimeout(() => {
      agentTurnPersistTimers.delete(current.turnId);
      persistAgentTerminalTurn(payload);
    }, 500);
    agentTurnPersistTimers.set(current.turnId, timer);
  }

  function mergeAgentTerminalSnapshot(snapshot = {}) {
    if (!snapshot.kind) return;
    setAgentBridge((current) => {
      if (!current) return current;
      if (current?.kind && current.kind !== snapshot.kind) return current;
      const providerId = current.providerId || agentProviderId(snapshot.kind);
      if (current.turnId && snapshot.plainTail) {
        updateAgentTerminalResponse(current.turnId, providerId, (response) => ({
          ...response,
          status: "done",
          text: snapshot.plainTail,
          meta: {
            ...(response.meta || {}),
            podName: snapshot.podName || response.meta?.podName || "",
            attachedSockets: snapshot.attachedSockets ?? response.meta?.attachedSockets,
            lastInputAt: snapshot.lastInputAt || response.meta?.lastInputAt || "",
            lastOutputAt: snapshot.lastOutputAt || response.meta?.lastOutputAt || "",
            state: "terminal-output-observed"
          }
        }));
      }
      const next = {
        ...(current || {}),
        kind: snapshot.kind,
        status: snapshot.status || current?.status || "observed",
        podName: snapshot.podName || current?.podName || "",
        attachedSockets: snapshot.attachedSockets ?? current?.attachedSockets ?? 0,
        startedAt: snapshot.startedAt || current?.startedAt || "",
        lastInputAt: snapshot.lastInputAt || current?.lastInputAt || "",
        lastOutputAt: snapshot.lastOutputAt || current?.lastOutputAt || "",
        plainTail: snapshot.plainTail || current?.plainTail || "",
        terminalState: snapshot.terminalState || current?.terminalState || null
      };
      if (snapshot.plainTail) scheduleAgentTerminalTurnPersist(next);
      return next;
    });
  }

  function mergeAgentTerminalOutput(detail = {}) {
    if (!detail.kind || detail.slug !== slug()) return;
    const plain = stripTerminalAnsi(detail.data || "");
    if (!plain) return;
    setAgentBridge((current) => {
      if (!current) return current;
      if (current?.kind && current.kind !== detail.kind) return current;
      const nextTail = `${current?.plainTail || ""}${plain}`.slice(-2200);
      const providerId = current.providerId || agentProviderId(detail.kind);
      if (current.turnId) {
        updateAgentTerminalResponse(current.turnId, providerId, (response) => ({
          ...response,
          status: "done",
          text: nextTail,
          meta: {
            ...(response.meta || {}),
            lastOutputAt: new Date().toISOString(),
            state: "terminal-output-streaming"
          }
        }));
      }
      const next = {
        ...(current || {}),
        kind: detail.kind,
        status: current?.status || "running",
        lastOutputAt: new Date().toISOString(),
        plainTail: nextTail
      };
      scheduleAgentTerminalTurnPersist(next);
      return next;
    });
  }

  function retryTurn(turn) {
    if (!turn?.message) return;
    const retryProviders = availableRetryProviderIds(turn);
    if (!retryProviders.length) return;
    startChatTurn(turn.message, retryProviders, chatHistory());
  }

  function stopChat() {
    if (chatSocket?.readyState === WebSocket.OPEN) {
      chatSocket.send(JSON.stringify({ type: "stop" }));
    }
    markStreamingTurnsStopped();
    setChatStatus("stopping");
    setSending(false);
  }

  function stopTurn(turnId) {
    if (chatSocket?.readyState === WebSocket.OPEN) {
      chatSocket.send(JSON.stringify({ type: "stop", turnId }));
    }
    markTurnStopped(turnId);
  }

  async function refreshProviders() {
    try {
      const data = await fetchJson(`/api/projects/${slug()}/multimodel/providers`, { timeoutMs: 8000 });
      setProviders(data.providers || []);
      setSelectedProviders((current) =>
        nextProviderSelection(data.providers || [], current, data.defaultProviders || [], selectionTouched())
      );
      if (!chatConnected()) setChatStatus("provider status loaded");
    } catch (error) {
      setChatStatus(`providers unavailable: ${error.message}`);
    }
  }

  async function refreshHistory() {
    try {
      const data = await fetchJson(`/api/projects/${slug()}/multimodel/turns?limit=18&includeActive=1`, { timeoutMs: 8000 });
      const records = (data.turns || []).slice().reverse();
      const restored = records.map(turnFromRecord);
      setTurns((current) => {
        const byId = new Map(current.map((turn) => [turn.id, turn]));
        for (const turn of restored) byId.set(turn.id, mergeTurn(byId.get(turn.id), turn));
        return sortTurns(byId.values());
      });
      setHistoryStatus(`${data.count || 0} turn(s) · ${data.activeCount || 0} active`);
    } catch (error) {
      setHistoryStatus(`history unavailable: ${error.message}`);
    }
  }

  async function refreshNativeSessions() {
    try {
      const data = await fetchJson(`/api/projects/${slug()}/multimodel/sessions`, { timeoutMs: 8000 });
      setNativeSessions(data.sessions || {});
    } catch {
      setNativeSessions({});
    }
  }

  async function refreshMcpInbox() {
    try {
      const data = await fetchJson(`/api/projects/${slug()}/multimodel/mcp-inbox?limit=12`, { timeoutMs: 8000 });
      setMcpInbox(data || { providers: [] });
    } catch {
      setMcpInbox({ providers: [] });
    }
  }

  async function refreshReadiness() {
    try {
      const data = await fetchJson(`/api/projects/${slug()}/multimodel/readiness`, { timeoutMs: 8000 });
      setReadiness(data);
    } catch {
      setReadiness(null);
    }
  }

  async function refreshHealth() {
    try {
      const data = await fetchJson(`/api/projects/${slug()}/multimodel/health`, { timeoutMs: 8000 });
      setHealth(data);
    } catch (error) {
      setHealth({ ok: false, error: error.message, checks: {} });
    }
  }

  async function refreshSetup() {
    try {
      const data = await fetchJson(`/api/projects/${slug()}/multimodel/setup`, { timeoutMs: 8000 });
      setSetup(data);
      if (!publicEndpointTouched()) {
        setPublicEndpointDraft(data.publicEndpoint?.url || "");
        setPublicEndpointTrusted(Boolean(data.publicEndpoint?.trustedHosted));
      }
    } catch (error) {
      setSetup({ actions: [], error: error.message, truthMode: "stale" });
    }
  }

  async function refreshSubscriptionBringup() {
    try {
      const data = await fetchJson(`/api/projects/${slug()}/multimodel/subscription-clients/bringup`, { timeoutMs: 8000 });
      setSubscriptionBringup(data);
      const liveDrillMessageId = activeSubscriptionLiveDrillMessageId();
      for (const client of data.clients || []) {
        refreshSubscriptionLiveDrill(client, liveDrillMessageId);
      }
    } catch (error) {
      setSubscriptionBringup({ clients: [], error: error.message, truthMode: "stale" });
    }
  }

  function activeSubscriptionLiveDrillMessageId() {
    if (typeof window === "undefined") return "";
    return new URLSearchParams(window.location.search).get("live_drill") || "";
  }

  async function refreshPublicEndpointCandidates() {
    try {
      const data = await fetchJson(`/api/projects/${slug()}/multimodel/public-endpoint/candidates`, { timeoutMs: 12000 });
      setPublicEndpointCandidates(data);
    } catch (error) {
      setPublicEndpointCandidates({
        candidates: [],
        error: error.message,
        truthMode: "stale"
      });
    }
  }

  async function refreshTailscaleFunnelPlan() {
    setTailscaleFunnelStatus("");
    try {
      const data = await fetchJson(`/api/projects/${slug()}/multimodel/public-endpoint/tailscale-funnel`, {
        method: "POST",
        timeoutMs: 16000,
        body: { dryRun: true }
      });
      setTailscaleFunnelPlan(data);
    } catch (error) {
      setTailscaleFunnelPlan({
        safeToApply: false,
        blockers: [error.message],
        truthMode: "stale"
      });
    }
  }

  async function refreshTailscaleFunnelPathPlan() {
    try {
      const data = await fetchJson(`/api/projects/${slug()}/multimodel/public-endpoint/tailscale-funnel-path`, {
        method: "POST",
        timeoutMs: 16000,
        body: { dryRun: true, pathPrefix: "/api/workbench" }
      });
      setTailscaleFunnelPathPlan(data);
    } catch (error) {
      setTailscaleFunnelPathPlan({
        safeToApply: false,
        blockers: [error.message],
        truthMode: "stale"
      });
    }
  }

  async function savePublicEndpoint(event) {
    event?.preventDefault?.();
    const publicBase = publicEndpointDraft().trim();
    if (!publicBase) {
      setPublicEndpointStatus("Enter a public HTTPS endpoint first.");
      return;
    }
    setPublicEndpointStatus("Saving endpoint...");
    try {
      const data = await fetchJson(`/api/projects/${slug()}/multimodel/public-endpoint`, {
        method: "POST",
        timeoutMs: 12000,
        body: {
          publicBase,
          trustedHosted: publicEndpointTrusted(),
          note: publicEndpointTrusted()
            ? "Operator marked this endpoint hosted-client reachable after external tunnel/Funnel verification."
            : ""
        }
      });
      setPublicEndpointTouched(false);
      setPublicEndpointDraft(data.publicEndpoint?.url || publicBase);
      setPublicEndpointTrusted(Boolean(data.publicEndpoint?.trustedHosted));
      setPublicEndpointStatus(data.publicEndpoint?.hostedClientReachable
        ? "Endpoint saved as hosted-client reachable."
        : data.publicEndpoint?.reason || "Endpoint saved; hosted clients still blocked.");
      await Promise.all([refreshSetup(), refreshPublicEndpointCandidates(), refreshTailscaleFunnelPlan(), refreshTailscaleFunnelPathPlan(), refreshHealth(), refreshProviders()]);
    } catch (error) {
      setPublicEndpointStatus(`Endpoint save failed: ${error.message}`);
    }
  }

  async function refreshRealtimeVerification() {
    try {
      const data = await fetchJson(`/api/projects/${slug()}/multimodel/verify/realtime?limit=1`, { timeoutMs: 8000 });
      if (data.latest) {
        setRealtimeVerify({ status: "last verified", result: data.latest, error: "" });
      }
    } catch {
      // Verification history is optional; live chat can still work without it.
    }
  }

  async function refreshConversationVerification() {
    try {
      const data = await fetchJson(`/api/projects/${slug()}/multimodel/verify/conversation?limit=1`, { timeoutMs: 8000 });
      if (data.latest) {
        setConversationVerify({ status: "last verified", result: data.latest, error: "" });
      }
    } catch {
      // Verification history is optional; live chat can still work without it.
    }
  }

  async function refreshReconnectVerification() {
    try {
      const data = await fetchJson(`/api/projects/${slug()}/multimodel/verify/reconnect?limit=1`, { timeoutMs: 8000 });
      if (data.latest) {
        setReconnectVerify({ status: "last verified", result: data.latest, error: "" });
      }
    } catch {
      // Verification history is optional; live chat can still work without it.
    }
  }

  async function verifyRealtimeNow() {
    const providersToVerify = selectedVerifiableProviderIds();
    if (!providersToVerify.length) {
      setRealtimeVerify({ status: "error", result: null, error: "select at least one realtime provider" });
      return;
    }
    setRealtimeVerify({ status: "running", result: null, error: "" });
    try {
      const result = await fetchJson(`/api/projects/${slug()}/multimodel/verify/realtime`, {
        method: "POST",
        timeoutMs: 300000,
        body: {
          providers: providersToVerify,
          timeoutMs: 180000
        }
      });
      setRealtimeVerify({ status: "done", result, error: "" });
      refreshHistory();
      refreshProviders();
      refreshRealtimeVerification();
    } catch (error) {
      setRealtimeVerify({ status: "error", result: null, error: error.message });
    }
  }

  async function verifyConversationNow() {
    const providersToVerify = selectedVerifiableProviderIds();
    if (!providersToVerify.length) {
      setConversationVerify({ status: "error", result: null, error: "select at least one realtime provider" });
      return;
    }
    setConversationVerify({ status: "running", result: null, error: "" });
    try {
      const result = await fetchJson(`/api/projects/${slug()}/multimodel/verify/conversation`, {
        method: "POST",
        timeoutMs: 300000,
        body: {
          providers: providersToVerify,
          message: "Responda em uma palavra: vivo",
          minChars: 2,
          timeoutMs: 180000
        }
      });
      setConversationVerify({ status: "done", result, error: "" });
      refreshHistory();
      refreshProviders();
      refreshReadiness();
      refreshConversationVerification();
    } catch (error) {
      setConversationVerify({ status: "error", result: null, error: error.message });
    }
  }

  async function verifyReconnectNow() {
    const providersToVerify = selectedVerifiableProviderIds();
    if (!providersToVerify.length) {
      setReconnectVerify({ status: "error", result: null, error: "select at least one realtime provider" });
      return;
    }
    setReconnectVerify({ status: "running", result: null, error: "" });
    try {
      const result = await fetchJson(`/api/projects/${slug()}/multimodel/verify/reconnect`, {
        method: "POST",
        timeoutMs: 300000,
        body: {
          providers: providersToVerify,
          timeoutMs: 180000
        }
      });
      setReconnectVerify({ status: "done", result, error: "" });
      refreshHistory();
      refreshProviders();
      refreshReconnectVerification();
    } catch (error) {
      setReconnectVerify({ status: "error", result: null, error: error.message });
    }
  }

  async function refreshState() {
    try {
      const data = await fetchJson(`/api/projects/${slug()}/go-work-now?depth=deep`, { timeoutMs: 8000 });
      const goWork = data.goWorkNow || {};
      const workspaceData = goWork.workspace || {};
      const workspaceState = goWork.workspaceState || {};
      setWorkspace({
        root: workspaceData.root || "/home/devsounio/darwin-MFC",
        tmuxSession: workspaceData.tmuxSession || "",
        status: workspaceState.status || "unknown",
      });
    } catch {
      setWorkspace({ root: "/home/devsounio/darwin-MFC", tmuxSession: "", status: "unavailable" });
    }
  }

  async function refreshAgents() {
    try {
      const data = await fetchJson(`/api/projects/${slug()}/agent/sessions`, { timeoutMs: 10000 });
      const sessions = data.sessions || [];
      setAgentSessions(sessions);
      const running = sessions.find((session) => session.status === "running");
      const preferred = sessions.find((session) => session.kind === "codex") || running || sessions[0];
      if (preferred) {
        setSelectedAgent(preferred.kind);
        if (preferred.status === "running" && selectedTerminal() === "workspace") {
          setSelectedTerminal(`agent:${preferred.kind}`);
        }
      }
      setAgentStatus(sessions.length ? `${sessions.length} real agent session(s)` : "no agent sessions");
    } catch (error) {
      setAgentStatus(`agent sessions unavailable: ${error.message}`);
    }
  }

  async function startAgent(kind = "codex") {
    setSyncStatus(`starting ${kind}`);
    try {
      const result = await fetchJson(`/api/projects/${slug()}/agent/session/start`, {
        method: "POST",
        timeoutMs: 120000,
        body: { kind, confirmed: true },
      });
      setSelectedAgent(result.kind || kind);
      setSelectedTerminal(`agent:${result.kind || kind}`);
      setSyncStatus(`${kind} ${result.status || "started"}`);
      await refreshAgents();
    } catch (error) {
      setSyncStatus(`start failed: ${error.message}`);
    }
  }

  async function syncAgent(direction = "to-agent") {
    const agent = currentAgent();
    if (!agent?.kind) {
      setSyncStatus("no agent selected");
      return;
    }
    if (agent.status !== "running") {
      setSyncStatus(`${agent.kind} is ${agent.status}`);
      return;
    }
    if (agent.local) {
      setSyncStatus(`${agent.kind} is already attached to the local checkout`);
      return;
    }
    const endpoint = direction === "from-agent" ? "sync-from-agent" : "sync-local";
    setSyncStatus(direction === "from-agent" ? `pulling from ${agent.kind}` : `pushing to ${agent.kind}`);
    try {
      const result = await fetchJson(`/api/projects/${slug()}/agent/session/${agent.kind}/${endpoint}`, {
        method: "POST",
        timeoutMs: 120000,
        body: { confirmed: true },
      });
      setSelectedAgent(agent.kind);
      setSelectedTerminal(`agent:${agent.kind}`);
      setSyncStatus(`${direction === "from-agent" ? "pulled" : "pushed"} ${result.changedCount || 0} changed, ${result.deletedCount || 0} deleted`);
      await refreshAgents();
    } catch (error) {
      setSyncStatus(`sync failed: ${error.message}`);
    }
  }

  onMount(() => {
    const onAgentSnapshot = (event) => mergeAgentTerminalSnapshot(event.detail || {});
    const onAgentOutput = (event) => mergeAgentTerminalOutput(event.detail || {});
    window.addEventListener("beagle-agent-terminal-snapshot", onAgentSnapshot);
    window.addEventListener("beagle-agent-terminal-output", onAgentOutput);
    connectChat();
    refreshProviders();
    refreshNativeSessions();
    refreshMcpInbox();
    refreshReadiness();
    refreshHealth();
    refreshSetup();
    refreshSubscriptionBringup();
    for (const client of subscriptionConnectorClients()) refreshSubscriptionLiveDrill(client, activeSubscriptionLiveDrillMessageId());
    refreshPublicEndpointCandidates();
    refreshTailscaleFunnelPlan();
    refreshTailscaleFunnelPathPlan();
    refreshRealtimeVerification();
    refreshConversationVerification();
    refreshReconnectVerification();
    refreshHistory();
    refreshState();
    refreshAgents();
    const timer = setInterval(() => {
      refreshProviders();
      refreshNativeSessions();
      refreshMcpInbox();
      refreshReadiness();
      refreshHealth();
      refreshSetup();
      refreshSubscriptionBringup();
      for (const client of subscriptionConnectorClients()) refreshSubscriptionLiveDrill(client, activeSubscriptionLiveDrillMessageId());
      refreshPublicEndpointCandidates();
      refreshTailscaleFunnelPlan();
      refreshTailscaleFunnelPathPlan();
      refreshHistory();
      refreshState();
      refreshAgents();
    }, 8000);
    onCleanup(() => {
      window.removeEventListener("beagle-agent-terminal-snapshot", onAgentSnapshot);
      window.removeEventListener("beagle-agent-terminal-output", onAgentOutput);
      disposed = true;
      clearInterval(timer);
      if (reconnectTimer) clearTimeout(reconnectTimer);
      for (const timer of agentTurnPersistTimers.values()) clearTimeout(timer);
      agentTurnPersistTimers.clear();
      if (chatSocket) chatSocket.close();
    });
  });

  return (
    <main class="scratch-shell multimodel-studio" aria-label="Multimodel chat studio">
      <header class="scratch-top">
        <div>
          <strong>Multimodel Chat</strong>
          <span>{slug()} · real streams only</span>
        </div>
        <div class="scratch-top-actions">
          <button type="button" onClick={() => startAgent("desktop-claude")}>Open Claude</button>
          <button type="button" onClick={() => startAgent("desktop-codex")}>Open Codex</button>
          <button type="button" onClick={() => startAgent("desktop-cursor")}>Open Cursor</button>
          <button type="button" onClick={() => { connectChat(); refreshProviders(); }}>Reconnect</button>
        </div>
      </header>

      <section class="scratch-room multimodel-room">
        <div class="scratch-intro">
          <p>Real model room</p>
          <h1>One chat, several real agents.</h1>
          <span>Claude Code, Codex, Cursor Agent, and MCP subscription clients share one realtime thread. Desktop clients reply by writing back through Workbench Context.</span>
        </div>

        <Show when={readiness()}>
          {(item) => (
            <section class="readiness-card" aria-label="Multimodel readiness">
              <header>
                <strong>{health()?.ok ? "healthy" : `${item().summary.liveNow} live now`}</strong>
                <span>{item().truthMode}</span>
              </header>
              <p>
                {readinessProviderLabel(item(), item().liveNow) || "No provider is live right now."}
              </p>
              <Show when={readinessProviderDetails(item(), item().liveNow).length}>
                <div class="readiness-provider-strip" aria-label="Live realtime providers">
                  <For each={readinessProviderDetails(item(), item().liveNow)}>
                    {(provider) => (
                      <span title={provider.transport}>
                        {provider.label} · {provider.transport}
                      </span>
                    )}
                  </For>
                </div>
              </Show>
              <div class="readiness-grid">
                <span>realtime {readinessVerificationLabel(item().latestRealtimeVerification)}</span>
                <span>chat {readinessVerificationLabel(item().latestConversationVerification)}</span>
                <span>browser {readinessVerificationLabel(item().latestUiSendVerification)}</span>
                <span>full gate {readinessFullGateLabel(item().fullProof)}</span>
                <span>context {readinessContextProofLabel(item().contextProof)}</span>
                <span>MCP {readinessMcpContractLabel(item().mcpContractProof)}</span>
                <span>MCP WS {readinessMcpRealtimeLabel(item().mcpRealtimeProof)}</span>
                <span>MCP cancel {readinessMcpCancelLabel(item().mcpCancelProof)}</span>
                <span>stop {readinessUiStopLabel(item().uiStopProof)}</span>
                <span>MCP STDIO {readinessMcpStdioLabel(item().mcpStdioProof)}</span>
                <span>MCP auth {item().httpMcpAuthProof?.ok ? "auth ok" : "auth not verified"}</span>
                <span>MCP remote {readinessRemoteMcpTransportLabel(item().remoteMcpTransportProof)}</span>
                <span>MCP kit {readinessMcpClientKitLabel(item().mcpClientKitProof)}</span>
                <span>MCP install {readinessMcpClientInstallLabel(item().mcpClientInstallProof)}</span>
                <span>reconnect {readinessVerificationLabel(item().latestReconnectVerification)}</span>
                <span>{item().summary.handoffStale} stale MCP</span>
                <span>{item().summary.blocked} blocked</span>
              </div>
              <Show when={health()}>
                {(gate) => (
                  <div class={`health-check-strip ${gate().ok ? "ok" : "error"}`} aria-label="Multimodel health checks">
                    <For each={healthCheckItems(gate())}>
                      {(check) => (
                        <span class={check[1] ? "ok" : "error"}>
                          {check[0]} {check[1] ? "ok" : "fail"}
                        </span>
                      )}
                    </For>
                  </div>
                )}
              </Show>
              <Show when={item().contextProof?.ok}>
                <small>
                  Context proof covers {(item().contextProof?.recalledProviders || []).join(", ")}
                </small>
              </Show>
              <Show when={item().fullProof?.ok}>
                <small>
                  Full gate completed {item().fullProof?.stepCount || 0} steps for {(item().fullProof?.providers || []).join(", ")}
                </small>
              </Show>
              <Show when={item().mcpContractProof?.ok}>
                <small>
                  MCP contract completed {item().mcpContractProof?.messageId} · GraphRAG {item().mcpContractProof?.graphMatches || 0}
                </small>
              </Show>
              <Show when={item().mcpRealtimeProof?.ok}>
                <small>
                  MCP realtime completed {item().mcpRealtimeProof?.messageId} · {item().mcpRealtimeProof?.provider}
                </small>
              </Show>
              <Show when={item().mcpCancelProof?.ok}>
                <small>
                  MCP cancel closed {item().mcpCancelProof?.messageId} · {item().mcpCancelProof?.canceledBy}
                </small>
              </Show>
              <Show when={item().uiStopProof?.ok}>
                <small>
                  Stop closed {item().uiStopProof?.messageId} · {item().uiStopProof?.canceledBy}
                </small>
              </Show>
              <Show when={item().mcpStdioProof?.ok}>
                <small>
                  MCP STDIO bridge completed {item().mcpStdioProof?.messageId} · {item().mcpStdioProof?.aliasToolCount || 0} alias tool(s)
                </small>
              </Show>
              <Show when={item().httpMcpAuthProof?.ok}>
                <small>
                  HTTP MCP auth rejects missing/wrong bearer tokens and accepts the local token.
                </small>
              </Show>
              <Show when={item().mcpClientKitProof?.ok}>
                <small>
                  MCP client kit ready at {item().mcpClientKitProof?.kitDir}
                </small>
              </Show>
              <Show when={item().mcpClientInstallProof?.ok}>
                <small>
                  MCP install ready at {item().mcpClientInstallProof?.installDir}
                </small>
              </Show>
              <Show when={item().handoffStale.length || item().blocked.length}>
                <small>
                  Not live now: {[readinessProviderLabel(item(), item().handoffStale), readinessProviderLabel(item(), item().blocked)].filter(Boolean).join(", ")}
                </small>
              </Show>
              <Show when={readinessProviderDetails(item(), item().handoffStale).length}>
                <div class="readiness-provider-strip stale" aria-label="Stale subscription MCP providers">
                  <For each={readinessProviderDetails(item(), item().handoffStale)}>
                    {(provider) => (
                      <span title={provider.reason}>
                        {provider.label} · subscription inbox stale
                      </span>
                    )}
                  </For>
                </div>
              </Show>
            </section>
          )}
        </Show>

        <Show when={subscriptionConnectorClients().length}>
          <section class="provider-setup-card subscription-reply-gate" aria-label="Real subscription reply gate" data-testid="subscription-reply-gate">
            <header>
              <strong>Real client connectors</strong>
              <span>{subscriptionReplyGateLabel(subscriptionBringup() || { clients: subscriptionConnectorClients() })}</span>
            </header>
            <p class="subscription-plain-status">
              A client is live only after the actual subscription app writes a fresh heartbeat or replies through MCP. Probe traffic, fixtures, manual paste, and direct debug endpoints are rejected as proof.
            </p>
            <div class="subscription-room-actions" data-testid="subscription-room">
              <button
                type="button"
                data-testid="subscription-room-redacted"
                onClick={() => createSubscriptionRoomFile({ revealToken: false })}
              >
                Write room file
              </button>
              <button
                type="button"
                data-testid="subscription-room-local-token"
                onClick={() => createSubscriptionRoomFile({ revealToken: true })}
              >
                Write local token room
              </button>
              <span>{subscriptionRoomStatus() || "One file for ChatGPT, Grok, and Claude Desktop."}</span>
            </div>
            <Show when={subscriptionRoom()}>
              {(room) => (
                <div class={`subscription-live-drill-status ${room().ok ? "waiting-for-real-client" : "error"}`} data-testid="subscription-room-status">
                  <div>
                    <strong>{room().ok ? "room ready" : "room failed"}</strong>
                    <span>{room().roomFile || room().error}</span>
                  </div>
                  <Show when={room().ok}>
                    <div class="subscription-tool-flow">
                      <span class={room().redacted ? "missing" : "ok"}>{room().redacted ? "redacted" : "token file"}</span>
                      <span class="ok">{(room().items || []).length} client(s)</span>
                      <span class="missing">not live proof</span>
                    </div>
                    <For each={room().items || []}>
                      {(item) => (
                        <small>
                          {item.label || item.clientId}: {item.readyFile}{item.drill?.messageId ? ` · ${item.drill.messageId}` : ""}
                        </small>
                      )}
                    </For>
                  </Show>
                </div>
              )}
            </Show>
            <div class="provider-setup-grid" aria-label="Real subscription client bring-up" data-testid="subscription-bringup">
              <For each={subscriptionConnectorClients()}>
                {(client) => (
                  <article class={`subscription-connect-card ${bringupClientClass(client)}`} data-client-id={client.id} data-testid="subscription-connect-card">
                    <div>
                      <strong>{client.label}</strong>
                      <span>{client.replyGate?.status || (client.realConnectionObserved ? "ready-to-test" : client.clientPresence || "waiting")}</span>
                    </div>
                    <p>{client.connect?.surface || "MCP client"} · {client.liveProof}</p>
                    <small class={client.replyGate?.latestProof?.fresh ? "ok" : "missing"}>
                      {subscriptionReplyProofLabel(client.replyGate?.latestProof)}
                    </small>
                    <div class="subscription-connect-actions">
                      <button
                        type="button"
                        data-testid="subscription-copy-connect"
                        data-client-id={client.id}
                        onClick={() => copyClientConnectPlan(client)}
                      >
                        Copy connect plan
                      </button>
                      <button
                        type="button"
                        data-testid="subscription-copy-setup-text"
                        data-client-id={client.id}
                        onClick={() => copyClientSetupText(client)}
                      >
                        Copy setup text
                      </button>
                      <button
                        type="button"
                        data-testid="subscription-live-drill"
                        data-client-id={client.id}
                        onClick={() => startSubscriptionLiveDrill(client)}
                      >
                        Open live drill
                      </button>
                      <button
                        type="button"
                        class="subscription-drill-button"
                        data-testid="subscription-reply-drill"
                        data-client-id={client.id}
                        disabled={!chatConnected() || sending()}
                        onClick={() => startSubscriptionReplyDrill(client)}
                      >
                        Start reply drill
                      </button>
                    </div>
                    <Show when={client.replyGate?.latestProof?.messageId}>
                      <small>reply proof message: {client.replyGate.latestProof.messageId}</small>
                    </Show>
                    <Show when={subscriptionDrillStatus()[client.id]}>
                      <small>{subscriptionDrillStatus()[client.id]}</small>
                    </Show>
                    <Show when={liveDrillFor(client)}>
                      {(drill) => (
                        <div class={`subscription-live-drill-status ${drill().status || "waiting"}`} data-testid="subscription-live-drill-status" data-client-id={client.id}>
                          <div>
                            <strong>{drill().status || "not-started"}</strong>
                            <span>{drill().message?.message_id || drill().error || ""}</span>
                          </div>
                          <div class="subscription-tool-flow">
                            <span class={drill().phases?.connect ? "ok" : "missing"}>connect</span>
                            <span class={drill().phases?.sent ? "ok" : "missing"}>sent</span>
                            <span class={drill().phases?.acknowledged ? "ok" : "missing"}>ack</span>
                            <span class={drill().phases?.claimed ? "ok" : "missing"}>claim</span>
                            <span class={drill().phases?.replied ? "ok" : "missing"}>reply</span>
                          </div>
                          <small>{drill().nextAction || drill().error || "No live drill started."}</small>
                          <Show when={drill().message?.marker}>
                            <small>marker: {drill().message.marker}</small>
                          </Show>
                          <Show when={drill().reply?.text}>
                            <small class="ok">reply: {drill().reply.text}</small>
                          </Show>
                          <button
                            type="button"
                            data-testid="subscription-refresh-live-drill"
                            data-client-id={client.id}
                            onClick={() => refreshSubscriptionLiveDrill(client, drill().message?.message_id || "")}
                          >
                            Refresh drill
                          </button>
                          <button
                            type="button"
                            data-testid="subscription-copy-activation-prompt"
                            data-client-id={client.id}
                            onClick={() => copySubscriptionActivationPrompt(client, drill())}
                          >
                            Copy activation prompt
                          </button>
                        </div>
                      )}
                    </Show>
                    <details class="subscription-connect-details" open={!client.realConnectionObserved}>
                      <summary>Connection details</summary>
                      <code title={client.url}>{client.url}</code>
                      <small>{JSON.stringify(client.headers)}</small>
                      <Show when={client.connect?.mcpServer?.tokenInstruction}>
                        <small>{client.connect.mcpServer.tokenInstruction}</small>
                      </Show>
                      <Show when={(client.connect?.firstToolCalls || []).length}>
                        <div class="subscription-tool-flow">
                          <For each={client.connect.firstToolCalls || []}>
                            {(call) => (
                              <span title={JSON.stringify(call.args)}>
                                {call.tool}
                              </span>
                            )}
                          </For>
                        </div>
                      </Show>
                    </details>
                    <small>
                      {client.clientLatestAt
                        ? `last real heartbeat ${observedAgeLabel(client.clientLatestAt) || "now"} ago`
                        : "no real heartbeat yet"}
                    </small>
                    <small>{client.verifyCommand}</small>
                    <small>{client.replyGate?.verifyCommand || client.replyVerifyCommand}</small>
                    <Show when={client.replyGate?.latestOpenMessageId}>
                      <small>open handoff: {client.replyGate.latestOpenMessageId}</small>
                    </Show>
                    <Show when={client.replyGate?.openCount}>
                      <small>{client.replyGate.openCount} open handoff(s)</small>
                    </Show>
                    <For each={client.replyGate?.rejectedEvidence || []}>
                      {(item) => <small class="missing">rejects {item}</small>}
                    </For>
                    <For each={client.blockers || []}>
                      {(blocker) => <small class="missing">{blocker}</small>}
                    </For>
                  </article>
                )}
              </For>
              <Show when={subscriptionBringup()?.auth?.tokenFile}>
                <small>token source: {subscriptionBringup().auth.tokenFile}</small>
              </Show>
              <Show when={subscriptionBringup()?.connectionPacket?.exists}>
                <small>connection packet: {subscriptionBringup().connectionPacket.path}</small>
              </Show>
              <Show when={subscriptionBringup()?.connectionPacket?.redactedExists}>
                <small>redacted packet: {subscriptionBringup().connectionPacket.redactedPath}</small>
              </Show>
              <Show when={subscriptionBringup()?.nextAction}>
                <small>{subscriptionBringup().nextAction}</small>
              </Show>
            </div>
          </section>
        </Show>

        <Show when={setup()}>
          {(item) => (
            <section class="provider-setup-card" aria-label="Provider setup" data-testid="multimodel-setup">
              <header>
                <strong>Provider setup</strong>
                <span>{item().truthMode}</span>
              </header>
              <Show when={item().publicEndpoint}>
                {(endpoint) => (
                  <article class={`provider-public-endpoint ${publicEndpointClass(endpoint())}`} data-testid="multimodel-public-endpoint">
                    <div>
                      <strong>Hosted MCP endpoint</strong>
                      <span>{publicEndpointLabel(endpoint())}</span>
                    </div>
                    <p>{endpoint().reason}</p>
                    <code title={endpoint().url}>{endpoint().url}</code>
                    <div class="provider-kit-files">
                      <span class={endpoint().https ? "ok" : "missing"}>https {endpoint().https ? "ok" : "missing"}</span>
                      <span class={!endpoint().loopback ? "ok" : "missing"}>loopback {endpoint().loopback ? "yes" : "no"}</span>
                      <span class={!endpoint().privateLan ? "ok" : "missing"}>private LAN {endpoint().privateLan ? "yes" : "no"}</span>
                      <span class={!endpoint().tailnet || endpoint().trustedHosted ? "ok" : "missing"}>tailnet {endpoint().tailnet ? "yes" : "no"}</span>
                    </div>
                    <Show when={(item().hostedNetworkBlocked || []).length}>
                      <small>blocked hosted clients: {(item().hostedNetworkBlocked || []).join(", ")}</small>
                    </Show>
                    <form class="public-endpoint-form" onSubmit={savePublicEndpoint}>
                      <input
                        type="url"
                        value={publicEndpointDraft()}
                        onInput={(event) => {
                          setPublicEndpointTouched(true);
                          setPublicEndpointDraft(event.currentTarget.value);
                        }}
                        placeholder="https://your-public-mcp.example.com"
                        aria-label="Public MCP endpoint"
                      />
                      <label>
                        <input
                          type="checkbox"
                          checked={publicEndpointTrusted()}
                          onChange={(event) => {
                            setPublicEndpointTouched(true);
                            setPublicEndpointTrusted(event.currentTarget.checked);
                          }}
                        />
                        Hosted verified
                      </label>
                      <button type="submit">Save endpoint</button>
                    </form>
                    <small>
                      This only records the endpoint. It does not change Tailscale, Cloudflare, or DNS.
                    </small>
                    <Show when={publicEndpointStatus()}>
                      <small>{publicEndpointStatus()}</small>
                    </Show>
                    <Show when={publicEndpointCandidates()}>
                      {(candidateSet) => (
                        <div class="public-endpoint-candidates" data-testid="public-endpoint-candidates">
                          <div>
                            <strong>Endpoint candidates</strong>
                            <span>{candidateSet().truthMode || "observed"}</span>
                          </div>
                          <For each={candidateSet().candidates || []}>
                            {(candidate) => (
                              <div class={`public-endpoint-candidate ${candidate.status || "waiting"}`}>
                                <div>
                                  <strong>{candidate.label}</strong>
                                  <span>{candidate.status}</span>
                                </div>
                                <Show when={candidate.url}>
                                  <code title={candidate.url}>{candidate.url}</code>
                                </Show>
                                <Show when={(candidate.routes || []).length}>
                                  <div class="public-endpoint-routes">
                                    <For each={candidate.routes || []}>
                                      {(route) => (
                                        <span title={`${route.hostPort}${route.path || ""} -> ${route.target}`}>
                                          {route.hostPort}{route.path || ""} -> {route.target || "no target"}
                                        </span>
                                      )}
                                    </For>
                                  </div>
                                </Show>
                                <For each={candidate.blockers || []}>
                                  {(blocker) => <small>{blocker}</small>}
                                </For>
                              </div>
                            )}
                          </For>
                          <Show when={candidateSet().observations?.tailscale?.dnsName}>
                            <small>Tailscale: {candidateSet().observations.tailscale.dnsName}</small>
                          </Show>
                        </div>
                      )}
                    </Show>
                    <Show when={tailscaleFunnelPlan()}>
                      {(plan) => (
                        <div class={`tailscale-funnel-plan ${plan().safeToApply ? "ready" : "blocked"}`} data-testid="tailscale-funnel-plan">
                          <div>
                            <strong>Tailscale Funnel guard</strong>
                            <span>{plan().safeToApply ? "ready" : "blocked"}</span>
                          </div>
                          <Show when={plan().publicBase}>
                            <code title={plan().publicBase}>{plan().publicBase}</code>
                          </Show>
                          <Show when={(plan().command || []).length}>
                            <code title={(plan().command || []).join(" ")}>{(plan().command || []).join(" ")}</code>
                          </Show>
                          <For each={plan().blockers || []}>
                            {(blocker) => <small>{blocker}</small>}
                          </For>
                          <Show when={(plan().rootConflictRoutes || []).length}>
                            <div class="public-endpoint-routes">
                              <For each={plan().rootConflictRoutes || []}>
                                {(route) => (
                                  <span title={`${route.hostPort}${route.path || ""} -> ${route.target}`}>
                                    {route.hostPort}{route.path || ""} -> {route.target || "no target"}
                                  </span>
                                )}
                              </For>
                            </div>
                          </Show>
                          <button
                            type="button"
                            onClick={async () => {
                              setTailscaleFunnelStatus("Checking Funnel guard...");
                              await refreshTailscaleFunnelPlan();
                              setTailscaleFunnelStatus("Funnel guard refreshed.");
                            }}
                          >
                            Check Funnel
                          </button>
                          <Show when={tailscaleFunnelStatus()}>
                            <small>{tailscaleFunnelStatus()}</small>
                          </Show>
                        </div>
                      )}
                    </Show>
                    <Show when={tailscaleFunnelPathPlan()}>
                      {(plan) => (
                        <div class={`tailscale-funnel-plan ${plan().safeToApply ? "ready" : "blocked"}`} data-testid="tailscale-funnel-path-plan">
                          <div>
                            <strong>Tailscale MCP path</strong>
                            <span>{plan().safeToApply ? "ready" : "blocked"}</span>
                          </div>
                          <Show when={plan().publicMcpBase}>
                            <code title={plan().publicMcpBase}>{plan().publicMcpBase}</code>
                          </Show>
                          <Show when={(plan().command || []).length}>
                            <code title={(plan().command || []).join(" ")}>{(plan().command || []).join(" ")}</code>
                          </Show>
                          <For each={plan().warnings || []}>
                            {(warning) => <small>{warning}</small>}
                          </For>
                          <For each={plan().blockers || []}>
                            {(blocker) => <small>{blocker}</small>}
                          </For>
                          <Show when={(plan().pathConflictRoutes || []).length}>
                            <div class="public-endpoint-routes">
                              <For each={plan().pathConflictRoutes || []}>
                                {(route) => (
                                  <span title={`${route.hostPort}${route.path || ""} -> ${route.target}`}>
                                    {route.hostPort}{route.path || ""} -> {route.target || "no target"}
                                  </span>
                                )}
                              </For>
                            </div>
                          </Show>
                          <button
                            type="button"
                            onClick={async () => {
                              setTailscaleFunnelStatus("Checking MCP path...");
                              await refreshTailscaleFunnelPathPlan();
                              setTailscaleFunnelStatus("MCP path guard refreshed.");
                            }}
                          >
                            Check MCP path
                          </button>
                        </div>
                      )}
                    </Show>
                  </article>
                )}
              </Show>
              <Show when={item().clientKit}>
                {(kit) => (
                  <article class={`provider-kit ${kit().status === "ready" ? "ready" : "waiting"}`} data-testid="mcp-client-kit">
                    <div>
                      <strong>MCP client kit</strong>
                      <span>{kit().status}</span>
                    </div>
                    <p>{kit().kitDir}</p>
                    <code title={kit().stdioBridgePath}>{kit().stdioBridgePath}</code>
                    <div class="provider-kit-files">
                      <For each={kit().files || []}>
                        {(file) => (
                          <span class={file.exists ? "ok" : "missing"} title={file.path}>
                            {file.name}
                          </span>
                        )}
                      </For>
                    </div>
                    <small>{kit().connectionPackEndpoint}</small>
                    <Show when={kit().publicEndpoint?.reason}>
                      <small>{kit().publicEndpoint.reason}</small>
                    </Show>
                    <small>{kit().generateCommand} · {kit().verifyCommand}</small>
                    <Show when={kit().installProof?.ok}>
                      <small>installed: {kit().installProof?.installDir}</small>
                    </Show>
                  </article>
                )}
              </Show>
              <Show when={(item().subscriptionClients || []).length}>
                <div class="subscription-client-strip" aria-label="Subscription MCP clients">
                  <For each={item().subscriptionClients || []}>
                    {(client) => (
                      <span class={setupClientClass(client)} title={[client.reason, client.mcpEndpoint].filter(Boolean).join(" · ")}>
                        {client.label} · {client.status}
                      </span>
                    )}
                  </For>
                </div>
              </Show>
              <div class="provider-setup-grid">
                <For each={item().actions || []}>
                  {(action) => (
                    <article class={setupActionClass(action)} data-provider-id={action.id}>
                      <div>
                        <strong>{action.label}</strong>
                        <span>{action.status}</span>
                      </div>
                      <p>{action.summary}</p>
                      <code title={setupActionDetail(action)}>{setupActionDetail(action)}</code>
                      <Show when={action.mcpEndpoint}>
                        <small>{action.mcpEndpoint}</small>
                      </Show>
                      <Show when={action.mcpHeaders}>
                        <small>{JSON.stringify(action.mcpHeaders)}</small>
                      </Show>
                      <Show when={action.clientInboxEndpoint}>
                        <small>{action.clientInboxEndpoint}</small>
                      </Show>
                      <Show when={action.verifyCommand}>
                        <small>{action.verifyCommand}</small>
                      </Show>
                      <For each={action.forbiddenBridgeValues || []}>
                        {(offender) => (
                          <small class="missing">
                            blocked bridge: {offender.name}
                          </small>
                        )}
                      </For>
                    </article>
                  )}
                </For>
              </div>
              <Show when={item().guards}>
                <small>
                  Kimi guard: {item().guards.noImplicitKimiBridge ? "no implicit bridge" : "check bridge config"}
                  {item().guards.kimiBridgeProjectSlug ? ` · ${item().guards.kimiBridgeProjectSlug}` : ""}
                </small>
              </Show>
            </section>
          )}
        </Show>

        <div class="scratch-provider-toolbar" aria-label="Provider selection actions">
          <span>{selectedAvailableProviderIds().length}/{availableProviders().length} ready selected</span>
          <button type="button" onClick={selectReadyProviders} disabled={!availableProviders().length}>All ready</button>
          <button type="button" onClick={selectCoreProviders} disabled={!availableProviders().some((provider) => ["claude", "codex", "cursor"].includes(provider.id))}>Core</button>
          <button type="button" onClick={clearProviderSelection} disabled={!selectedAvailableProviderIds().length}>Clear</button>
          <button type="button" onClick={verifyRealtimeNow} disabled={!canVerifyRealtime()}>
            {realtimeVerify().status === "running" ? "Verifying" : "Verify realtime"}
          </button>
          <button type="button" onClick={verifyConversationNow} disabled={!canVerifyConversation()}>
            {conversationVerify().status === "running" ? "Talking" : "Verify chat"}
          </button>
          <button type="button" onClick={verifyReconnectNow} disabled={!canVerifyReconnect()}>
            {reconnectVerify().status === "running" ? "Reconnecting" : "Verify reconnect"}
          </button>
        </div>

        <Show when={realtimeVerify().status !== "idle"}>
          <section class={`realtime-verify-card ${realtimeVerify().status === "error" ? "error" : ""}`} aria-label="Realtime verification">
            <header>
              <strong>Realtime verification</strong>
              <span>{realtimeVerify().status}</span>
            </header>
            <Show when={realtimeVerify().result} fallback={<p>{realtimeVerify().error || "Opening real WebSocket turn and checking persisted stream metrics."}</p>}>
              {(item) => (
                <>
                  <p>{item().truthMode} · {item().turnId}</p>
                  <div>
                    <For each={item().persisted || []}>
                      {(provider) => (
                        <span class="runtime-chip replied">
                          {provider.provider}: first {durationLabel(provider.firstDeltaMs)} · {provider.deltaCount} chunk{provider.deltaCount === 1 ? "" : "s"} · {provider.streamedChars} chars
                        </span>
                      )}
                    </For>
                  </div>
                </>
              )}
            </Show>
          </section>
        </Show>

        <Show when={conversationVerify().status !== "idle"}>
          <section class={`realtime-verify-card ${conversationVerify().status === "error" ? "error" : ""}`} aria-label="Conversation verification">
            <header>
              <strong>Conversation verification</strong>
              <span>{conversationVerify().status}</span>
            </header>
            <Show when={conversationVerify().result} fallback={<p>{conversationVerify().error || "Opening a normal chat turn and checking provider text plus persisted stream metrics."}</p>}>
              {(item) => (
                <>
                  <p>{item().truthMode} · {item().turnId}</p>
                  <div>
                    <For each={item().persisted || []}>
                      {(provider) => (
                        <span class="runtime-chip replied" title={provider.text}>
                          {provider.provider}: {provider.text} · first {durationLabel(provider.firstDeltaMs)}
                        </span>
                      )}
                    </For>
                  </div>
                </>
              )}
            </Show>
          </section>
        </Show>

        <Show when={reconnectVerify().status !== "idle"}>
          <section class={`realtime-verify-card ${reconnectVerify().status === "error" ? "error" : ""}`} aria-label="Reconnect verification">
            <header>
              <strong>Reconnect verification</strong>
              <span>{reconnectVerify().status}</span>
            </header>
            <Show when={reconnectVerify().result} fallback={<p>{reconnectVerify().error || "Detaching a real WebSocket turn, reconnecting, and checking persisted stream metrics."}</p>}>
              {(item) => (
                <>
                  <p>{item().truthMode} · {item().turnId}</p>
                  <Show when={item().reconnected}>
                    <p>snapshot {item().reconnected?.sawSnapshot ? "active-reconnect" : "missing"} · done {item().reconnected?.sawDone ? "observed" : "missing"} · active turns {item().activeTurns}</p>
                  </Show>
                  <div>
                    <For each={item().persisted || []}>
                      {(provider) => (
                        <span class="runtime-chip replied">
                          {provider.provider}: first {durationLabel(provider.firstDeltaMs)} · {provider.deltaCount} chunk{provider.deltaCount === 1 ? "" : "s"} · {provider.streamedChars} chars
                        </span>
                      )}
                    </For>
                  </div>
                </>
              )}
            </Show>
          </section>
        </Show>

        <div class="scratch-client-toggle" aria-label="Model selection">
          <For each={visibleProviders()} fallback={<p class="scratch-empty">Detecting providers.</p>}>
            {(provider) => (
              <button
                type="button"
                data-testid="multimodel-provider-toggle"
                data-provider-id={provider.id}
                data-provider-status={provider.status}
                data-provider-transport={provider.transport || ""}
                data-provider-surface={providerSurfaceLabel(provider)}
                data-selected={selectedAvailableProviderIds().includes(provider.id) ? "true" : "false"}
                class={`${selectedAvailableProviderIds().includes(provider.id) ? "selected" : ""} ${providerSurfaceClass(provider)}`}
                disabled={!isSelectableProvider(provider)}
                onClick={() => toggleProvider(provider.id)}
                >
                  <strong>{provider.label}</strong>
                  <small>{providerSubtitle(provider)}</small>
                  <small class="provider-proof">{providerProofLabel(provider)}</small>
                </button>
              )}
          </For>
        </div>

        <Show when={pendingMcpHandoffs().length}>
          <section class="mcp-handoff-queue" aria-label="Active MCP handoffs">
            <header>
              <strong>{pendingMcpHandoffs().length} MCP handoff(s) waiting</strong>
              <span>{copyStatus() || "subscription clients reply through Workbench Context"}</span>
            </header>
            <div>
              <For each={pendingMcpHandoffs()}>
                {(item) => (
                  <article>
                    <strong>{item.label} -> {item.handoff.target}</strong>
                    <code title={item.handoff.messageId}>{item.handoff.messageId}</code>
                    <div class="mcp-copy-actions">
                      <button type="button" data-testid="mcp-copy-message-id" onClick={() => copyText(item.handoff.messageId, "MCP message id copied.")}>Copy id</button>
                      <button type="button" data-testid="mcp-copy-reply-args" onClick={() => copyMcpReplyArgs(item.handoff)}>Copy args</button>
                      <button type="button" data-testid="mcp-copy-packet" onClick={() => copyMcpPacket(item.handoff)}>Copy packet</button>
                      <button type="button" data-testid="mcp-copy-activation-prompt" onClick={() => copyMcpActivationPrompt(item.handoff)}>Copy activation prompt</button>
                    </div>
                    <span>{item.handoff.phase.label} · {item.status}{item.activeForSeconds ? ` · ${ageLabel(item.activeForSeconds)}` : ""}</span>
                    <Show when={item.handoff.lifecycle.length}>
                      <small>{item.handoff.lifecycle.join(" · ")}</small>
                    </Show>
                  </article>
                )}
              </For>
            </div>
          </section>
        </Show>

        <section class="scratch-thread multimodel-thread" aria-label="Multimodel conversation" data-testid="multimodel-thread">
          <Show when={turns().length} fallback={<p class="scratch-empty">Escreve aqui como você falaria comigo. A próxima mensagem vai para os modelos reais selecionados.</p>}>
            <For each={turns()}>
              {(turn) => (
                <article class="multimodel-turn" data-testid="multimodel-turn" data-turn-id={turn.id} data-turn-status={turn.status}>
                  <div class="multimodel-user">
                    <div class="multimodel-user-head">
                      <span>You · {turnRuntimeLabel(turn)}</span>
                      <Show when={isActiveTurnStatus(turn.status)}>
                        <button type="button" onClick={() => stopTurn(turn.id)}>Stop</button>
                      </Show>
                      <Show when={turnHasRetryableGap(turn) && availableRetryProviderIds(turn).length}>
                        <button type="button" onClick={() => retryTurn(turn)}>
                          Retry available
                        </button>
                      </Show>
                    </div>
                    <Show when={isActiveTurnStatus(turn.status) && providerRuntimeDetails(turn).length}>
                      <div class="multimodel-runtime-strip" aria-label="Live provider status">
                        <For each={providerRuntimeDetails(turn)}>
                          {(item) => (
                            <span class={`runtime-chip ${providerStateClass(item.status)}`}>
                              {item.label}: {item.detail}{item.hasText ? " · text" : ""}{item.hasError ? " · error" : ""}
                            </span>
                          )}
                        </For>
                      </div>
                    </Show>
                    <Show when={(turn.trace || []).length}>
                      <div class="turn-live-trace" data-testid="turn-live-trace" aria-label="Turn live event trace">
                        <For each={(turn.trace || []).slice(-14)}>
                          {(event) => (
                            <span
                              data-event-type={event.type}
                              data-event-provider={event.provider || ""}
                              title={[event.type, event.provider, event.detail, event.at].filter(Boolean).join(" · ")}
                            >
                              <time>{traceTimeLabel(event.at)}</time>
                              <strong>{event.label || event.type}</strong>
                              <em>{event.detail || event.type}</em>
                            </span>
                          )}
                        </For>
                      </div>
                    </Show>
                    <p>{turn.message}</p>
                  </div>
                  <div class="multimodel-responses">
                    <For each={turn.responses}>
                      {(response) => (
                        <section
                          class={`multimodel-response ${providerStateClass(response.status)}`}
                          data-testid="multimodel-response"
                          data-provider={response.provider}
                          data-response-status={response.status}
                          data-provider-transport={response.meta?.transport || ""}
                          data-provider-source={response.meta?.sourceProvider || response.provider}
                          data-delta-count={response.deltaCount || 0}
                          data-streamed-chars={response.streamedChars || 0}
                          data-has-text={response.text ? "true" : "false"}
                        >
                          {(() => {
                            const handoff = mcpHandoffDetail(response, slug());
                            return (
                              <>
                          <header>
                            <strong>{response.label}</strong>
                            <span>{responseTimingLabel(response)}</span>
                          </header>
                          <Show when={responseEvidenceItems(response).length}>
                            <div
                              class="response-evidence-strip"
                              data-testid="response-evidence"
                              title={responseEvidenceTitle(response)}
                              aria-label={`${response.label} runtime evidence`}
                            >
                              <For each={responseEvidenceItems(response)}>
                                {(item) => (
                                  <span>
                                    {item[0]} <strong>{item[1]}</strong>
                                  </span>
                                )}
                              </For>
                            </div>
                          </Show>
                          <Show when={handoff}>
                            {(item) => (
                              <div class={`mcp-handoff-card ${item().phase.className}`} aria-label={`${response.label} MCP handoff`}>
                                <div>
                                  <strong>{item().target}</strong>
                                  <span>{item().phase.label}</span>
                                </div>
                                <p>{item().phase.detail}</p>
                                <code title={item().messageId}>{item().messageId}</code>
                                <div class="mcp-copy-actions">
                                  <button type="button" data-testid="mcp-card-copy-message-id" onClick={() => copyText(item().messageId, "MCP message id copied.")}>Copy id</button>
                                  <button type="button" data-testid="mcp-card-copy-reply-args" onClick={() => copyMcpReplyArgs(item())}>Copy args</button>
                                  <button type="button" data-testid="mcp-card-copy-packet" onClick={() => copyMcpPacket(item())}>Copy packet</button>
                                  <button type="button" data-testid="mcp-card-copy-activation-prompt" onClick={() => copyMcpActivationPrompt(item())}>Copy activation prompt</button>
                                </div>
                                <small>{item().tool}</small>
                                <small>{item().replyEndpoint}</small>
                                <Show when={item().phase.className !== "replied"}>
                                  <details class="mcp-dev-reply" data-testid="mcp-manual-reply-panel">
                                    <summary>Developer paste bridge</summary>
                                    <form
                                      class="mcp-manual-reply"
                                      data-testid="mcp-manual-reply-form"
                                      onSubmit={(event) => {
                                        event.preventDefault();
                                        submitMcpReply(item());
                                      }}
                                    >
                                      <textarea
                                        data-testid="mcp-manual-reply-input"
                                        value={mcpReplyDraft(item().messageId)}
                                        onInput={(event) => setMcpReplyDraft(item().messageId, event.currentTarget.value)}
                                        placeholder={`Paste a debug reply for ${item().target}`}
                                        rows="3"
                                      />
                                      <div>
                                        <button
                                          type="submit"
                                          data-testid="mcp-manual-reply-submit"
                                          disabled={!mcpReplyDraft(item().messageId).trim()}
                                        >
                                          Write debug reply
                                        </button>
                                        <small>{mcpReplyState(item().messageId) || "Debug bridge only. Real subscription proof must come from the client MCP tool."}</small>
                                      </div>
                                    </form>
                                  </details>
                                </Show>
                                <Show when={item().lifecycle.length}>
                                  <small>{item().lifecycle.join(" · ")}</small>
                                </Show>
                              </div>
                            )}
                          </Show>
                          <Show when={response.text} fallback={<p class="scratch-empty">{response.error || "waiting for stream"}</p>}>
                            <p>{response.text}</p>
                          </Show>
                          <Show when={response.error}>
                            <small>{response.error}</small>
                          </Show>
                          <Show when={responseMetaItems(response).length}>
                            <dl class="multimodel-meta" aria-label={`${response.label} response transport details`}>
                              <For each={responseMetaItems(response)}>
                                {(item) => (
                                  <div class="multimodel-meta-row">
                                    <dt>{item[0]}</dt>
                                    <dd title={String(item[1])}>{String(item[1])}</dd>
                                  </div>
                                )}
                              </For>
                            </dl>
                          </Show>
                              </>
                            );
                          })()}
                        </section>
                      )}
                    </For>
                  </div>
                </article>
              )}
            </For>
          </Show>
        </section>

        <form
          class="scratch-composer multimodel-composer"
          data-testid="multimodel-composer"
          onSubmit={(event) => {
            event.preventDefault();
            sendChat();
          }}
        >
          <textarea
            ref={composerRef}
            value={draft()}
            data-testid="multimodel-composer-input"
            placeholder="Fala com os modelos reais..."
            onInput={(event) => {
              setDraft(event.currentTarget.value);
              if (sendNotice() && event.currentTarget.value.trim()) setSendNotice("");
            }}
            onKeyDown={(event) => {
              if ((event.metaKey || event.ctrlKey) && event.key === "Enter") {
                event.preventDefault();
                sendChat();
              }
            }}
          />
          <button type="submit" disabled={!canSendChat()} data-testid="multimodel-send">
            Send
          </button>
          <button
            type="button"
            class="secondary"
            disabled={!canSendToAgentTerminal()}
            title={currentAgent()?.kind ? `Send to ${currentAgent().kind} terminal` : "No running agent terminal"}
            onClick={sendDraftToAgentTerminal}
          >
            Agent
          </button>
          <Show when={activeTurnIds().length}>
            <button type="button" class="secondary" data-testid="multimodel-stop" onClick={stopChat}>
              {activeTurnIds().length > 1 ? "Stop all" : "Stop"}
            </button>
          </Show>
        </form>

        <p class={`scratch-send-notice ${sendBlockReason() && !canSendChat() ? "muted" : ""}`} aria-live="polite" data-testid="multimodel-send-notice">
          {sendNotice() || sendBlockReason() || `Ready to send to ${selectedProviderLabel()}.`}
        </p>
        <p class="scratch-status">{chatStatus()} · {historyStatus()} · sending to: {selectedProviderLabel()}</p>

        <Show when={agentBridge()}>
          {(bridge) => (
            <section class={`agent-bridge-card ${bridge().status === "error" ? "error" : ""}`} aria-label="Agent terminal bridge">
              <header>
                <strong>{bridge().kind} terminal</strong>
                <span>{bridge().status}{bridge().bytes ? ` · ${bridge().bytes} bytes` : ""}{bridge().attachedSockets !== undefined ? ` · ${bridge().attachedSockets} viewer(s)` : ""}</span>
              </header>
              <Show when={bridge().error}>
                <p>{bridge().error}</p>
              </Show>
              <Show when={bridge().terminalState?.blockedByTrustPrompt}>
                <div class="agent-bridge-actions">
                  <span>This CLI is waiting for repo trust confirmation.</span>
                  <button type="button" onClick={() => continueAgentTrustPrompt(bridge().kind)}>
                    Continue trust prompt
                  </button>
                </div>
              </Show>
              <Show when={bridge().plainTail}>
                <pre>{bridge().plainTail}</pre>
              </Show>
              <button type="button" onClick={() => refreshAgentTerminalSnapshot(bridge().kind)}>
                Refresh terminal output
              </button>
            </section>
          )}
        </Show>

        <section class="scratch-terminal-dock real-terminal-dock compact-terminal" aria-label="Agent terminals">
          <div class="scratch-terminal-head">
            <div>
              <strong>Agent terminal</strong>
              <span>{syncStatus() || agentStatus()}</span>
            </div>
            <div class="scratch-terminal-actions">
              <Show when={currentAgent()?.local}>
                <button type="button" onClick={() => continueAgentTrustPrompt(currentAgent()?.kind)}>Continue trust prompt</button>
              </Show>
              <button type="button" disabled={currentAgent()?.local} onClick={() => syncAgent("to-agent")}>Push local</button>
              <button type="button" disabled={currentAgent()?.local} onClick={() => syncAgent("from-agent")}>Pull agent</button>
              <button type="button" onClick={refreshAgents}>Refresh</button>
            </div>
          </div>

          <div class="scratch-terminal-tabs" role="tablist" aria-label="Real terminals">
            <For each={agentSessions()}>
              {(session) => (
                <button
                  type="button"
                  class={selectedTerminal() === `agent:${session.kind}` ? "selected" : ""}
                  onClick={() => {
                    setSelectedAgent(session.kind);
                    setSelectedTerminal(`agent:${session.kind}`);
                    refreshAgentTerminalSnapshot(session.kind);
                  }}
                >
                  {session.kind}
                  <small>{session.status}</small>
                </button>
              )}
            </For>
            <Show when={hasLiveWorkspace()}>
              <button
                type="button"
                class={selectedTerminal() === "workspace" ? "selected" : ""}
                onClick={() => setSelectedTerminal("workspace")}
              >
                workspace
                <small>{workspace().tmuxSession}</small>
              </button>
            </Show>
          </div>

          <div class="scratch-terminal-frame">
            <div class="scratch-terminal-meta">
              <span>
                {selectedTerminal() === "workspace"
                  ? workspace().root
                  : (currentAgent()?.workspaceAuthority || "/workspace/darwin-mfc")}
              </span>
              <span>
                {selectedTerminal() === "workspace"
                  ? workspace().tmuxSession
                  : currentAgent()?.local
                    ? (currentAgent()?.command || "local shell")
                    : `${currentAgent()?.readyReplicas || 0}/${currentAgent()?.replicas || 0} ready`}
              </span>
            </div>

            <Show when={selectedTerminal() === "workspace"} fallback={
              <Show when={currentAgent()} fallback={<p class="scratch-terminal-empty">No real agent session is registered yet.</p>}>
                {(session) => (
                  <Show
                    when={session().status === "running"}
                    fallback={
                      <div class="scratch-terminal-pending">
                        <strong>{session().kind} is {session().status}</strong>
                        <span>Start or refresh the agent before attaching.</span>
                      </div>
                    }
                  >
                    <AgentTerminal slug={slug()} kind={session().kind} />
                  </Show>
                )}
              </Show>
            }>
              <Terminal slug={slug()} height="100%" />
            </Show>
          </div>
        </section>
      </section>

      <aside class="scratch-side real-side">
        <h2>Provider truth</h2>
        <div class="scratch-lanes">
          <For each={availableProviders()} fallback={<p class="scratch-empty">No available providers.</p>}>
            {(provider) => (
              <article class={`scratch-lane ${providerSurfaceClass(provider)}`}>
                <div>
                  <strong>{provider.label}</strong>
                  <span>{providerSurfaceLabel(provider)}</span>
                </div>
                <p>{provider.repoRoot}</p>
                <small>{providerTruthDetail(provider, nativeSessions())}</small>
              </article>
            )}
          </For>
          <For each={unavailableProviders()}>
            {(provider) => (
              <article class="scratch-lane error">
                <div>
                  <strong>{provider.label}</strong>
                  <span>unavailable</span>
                </div>
                <p>{provider.reason}</p>
              </article>
            )}
          </For>
        </div>

        <h2>MCP inbox</h2>
        <div class="scratch-lanes multimodel-inbox">
          <For each={mcpInbox().providers || []} fallback={<p class="scratch-empty">No MCP inbox status yet.</p>}>
            {(provider) => (
              <article class={`scratch-lane ${provider.counts?.open ? "waiting" : "replied"}`}>
                <div>
                  <strong>{provider.label}</strong>
                  <span>{provider.clientPresence || "unobserved"}</span>
                </div>
                <p>{provider.counts?.open || 0} open · {(provider.counts?.replied || 0) + (provider.counts?.completed || 0)} done · {provider.counts?.canceled || 0} canceled</p>
                <button
                  type="button"
                  class="subscription-drill-button"
                  data-testid="subscription-reply-drill"
                  data-client-id={provider.provider_id}
                  disabled={!chatConnected() || sending()}
                  onClick={() => startSubscriptionReplyDrill({
                    id: provider.provider_id,
                    targetClient: provider.targetClient,
                    label: provider.label
                  })}
                >
                  Start reply drill
                </button>
                <Show when={subscriptionDrillStatus()[provider.provider_id]}>
                  <small>{subscriptionDrillStatus()[provider.provider_id]}</small>
                </Show>
                <Show when={provider.latest} fallback={<small>no handoffs observed</small>}>
                  {(latest) => (
                    <dl class="multimodel-inbox-meta">
                      <div>
                        <dt>latest</dt>
                        <dd>{latest().status}{latest().age_seconds !== null ? ` · ${ageLabel(latest().age_seconds)}` : ""}</dd>
                      </div>
                      <div>
                        <dt>thread</dt>
                        <dd title={latest().thread_id}>{latest().thread_id}</dd>
                      </div>
                      <div>
                        <dt>message</dt>
                        <dd title={latest().message_id}>{latest().message_id}</dd>
                      </div>
                      <Show when={latest().reply_endpoint}>
                        <div>
                          <dt>reply</dt>
                          <dd title={latest().reply_endpoint}>{latest().reply_endpoint}</dd>
                        </div>
                      </Show>
                      <Show when={latest().reply_memory_id}>
                        <div>
                          <dt>memory</dt>
                          <dd title={latest().reply_memory_id}>{latest().reply_source || latest().reply_client_id} · {latest().reply_memory_id}</dd>
                        </div>
                      </Show>
                      <Show when={latest().cancel_reason}>
                        <div>
                          <dt>cancel</dt>
                          <dd>{latest().cancel_reason}</dd>
                        </div>
                      </Show>
                    </dl>
                  )}
                </Show>
                <Show when={openMcpInboxMessages(provider).length}>
                  <div class="mcp-open-list" aria-label={`${provider.label} open MCP handoffs`}>
                    <For each={openMcpInboxMessages(provider)}>
                      {(message) => (
                        <div class="mcp-open-item">
                          <div>
                            <strong>{message.status || "open"}</strong>
                            <span>{message.age_seconds !== null ? ageLabel(message.age_seconds) : "age unknown"}</span>
                          </div>
                          <code title={message.message_id}>{message.message_id}</code>
                          <button
                            type="button"
                            data-testid="mcp-inbox-cancel"
                            data-message-id={message.message_id}
                            onClick={() => cancelMcpInboxMessage(message)}
                          >
                            Cancel
                          </button>
                          <Show when={mcpCancelState(message.message_id)}>
                            <small>{mcpCancelState(message.message_id)}</small>
                          </Show>
                        </div>
                      )}
                    </For>
                  </div>
                </Show>
              </article>
            )}
          </For>
        </div>

        <h2>Agents</h2>
        <div class="scratch-lanes">
          <For each={agentSessions()} fallback={<p class="scratch-empty">No agents yet.</p>}>
            {(session) => (
              <article class={`scratch-lane ${session.status === "running" ? "replied" : session.status}`}>
                <div>
                  <strong>{session.label || session.kind}</strong>
                  <span>{session.status}</span>
                </div>
                <p>{session.local ? session.workspaceAuthority : session.name}</p>
              </article>
            )}
          </For>
        </div>
      </aside>
    </main>
  );
}

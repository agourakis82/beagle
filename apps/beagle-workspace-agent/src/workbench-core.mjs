import fs from "node:fs/promises";
import path from "node:path";
import { createHash, randomUUID } from "node:crypto";

export const WORKBENCH_PROTOCOL = "beagle-terminal-v1";
export const WORKBENCH_BRIDGE_VERSION = "beagle-warp-bridge-v0.2";

export const AGENT_KINDS = new Set([
  "human",
  "claude-code",
  "codex",
  "cursor",
  "opencode",
  "kimi",
  "minimax",
  "qwen-coder",
  "glm-air",
  "palmyra-x5",
  "jamba",
  "pegasus",
  "lfm2",
  "custom",
]);

export const AGENT_ROLE_REGISTRY = [
  {
    role: "primary_builder",
    kind: "codex",
    title: "Claude / Codex",
    subtitle: "High-stakes implementation and review",
    roleSummary: "Main builder lane for complex edits, synthesis, and careful execution.",
    visible: true,
    arousalRole: "phasic_focus",
    icon: "sparkles.rectangle.stack",
    accent: "truth_observed",
    launchCommand: "codex",
    readinessProbe: { type: "command", command: "codex" },
    memoryPolicy: "auto_curated",
    riskLevel: "write",
    providerSlots: [
      {
        id: "codex-cli",
        title: "Codex",
        modelId: "codex",
        command: "codex",
        runtime: "cli",
        costTier: "premium",
        latencyTier: "interactive",
        privacyTier: "workspace",
        licenseNote: "Hosted/local Codex CLI policy applies.",
        enabled: true,
      },
      {
        id: "claude-code-cli",
        title: "Claude Code",
        modelId: "claude-code",
        command: "claude",
        runtime: "cli",
        costTier: "premium",
        latencyTier: "interactive",
        privacyTier: "workspace",
        licenseNote: "Claude Code CLI and Anthropic account policy apply.",
        enabled: true,
      },
    ],
  },
  {
    role: "code_worker",
    kind: "minimax",
    title: "MiniMax Worker",
    subtitle: "Refactors, tests, compiler bugs",
    roleSummary: "Experimental code worker for multi-file edits and shell-driven iteration.",
    visible: true,
    arousalRole: "phasic_focus",
    icon: "hammer",
    accent: "truth_remembered",
    launchCommand: "",
    readinessProbe: { type: "provider_slot", env: "MINIMAX_API_KEY" },
    memoryPolicy: "auto_curated",
    riskLevel: "write",
    providerSlots: [
      {
        id: "minimax-m2",
        title: "MiniMax-M2",
        modelId: "MiniMax-M2",
        baseUrl: "https://api.minimax.io/v1",
        command: "",
        runtime: "openai_compatible",
        costTier: "efficient",
        latencyTier: "interactive",
        privacyTier: "external_api",
        licenseNote: "Use through approved MiniMax/API provider slot; do not assume local runtime.",
        enabled: true,
      },
    ],
  },
  {
    role: "long_thought_architect",
    kind: "kimi",
    title: "Kimi Architect",
    subtitle: "Long reasoning, semantics, language design",
    roleSummary: "Explores Sounio type semantics, effects, Claim<T>, and architecture choices.",
    visible: true,
    arousalRole: "tonic_explore",
    icon: "brain.head.profile",
    accent: "posture_cool",
    launchCommand: "kimi",
    readinessProbe: { type: "command", command: "kimi" },
    memoryPolicy: "manual_or_summary",
    riskLevel: "write",
    providerSlots: [
      {
        id: "kimi-k2-thinking",
        title: "Kimi K2 Thinking",
        modelId: "moonshotai/Kimi-K2-Thinking",
        baseUrl: "https://api.moonshot.ai/v1",
        command: "kimi",
        runtime: "cli_or_openai_compatible",
        costTier: "premium",
        latencyTier: "long_horizon",
        privacyTier: "external_api",
        licenseNote: "Moonshot/Kimi terms apply; use for exploration, not canonical claims.",
        enabled: true,
      },
    ],
  },
  {
    role: "maintenance_agent",
    kind: "qwen-coder",
    title: "Qwen Maintainer",
    subtitle: "Cheap lint, small patches, test loops",
    roleSummary: "Fast maintenance lane for low-risk changes and continuous repair loops.",
    visible: true,
    arousalRole: "phasic_focus",
    icon: "wrench.adjustable",
    accent: "truth_declared",
    launchCommand: "",
    readinessProbe: { type: "provider_slot", env: "QWEN_PROVIDER_URL" },
    memoryPolicy: "auto_curated",
    riskLevel: "write",
    providerSlots: [
      {
        id: "qwen3-coder-next",
        title: "Qwen3-Coder-Next",
        modelId: "Qwen/Qwen3-Coder-Next",
        command: "",
        runtime: "openai_compatible_or_local",
        costTier: "low",
        latencyTier: "fast",
        privacyTier: "provider_or_local",
        licenseNote: "Apache-2.0 model; deployment/provider policy decides data boundary.",
        enabled: true,
      },
    ],
  },
  {
    role: "platform_operator",
    kind: "glm-air",
    title: "GLM Operator",
    subtitle: "Kubernetes, runbooks, incidents",
    roleSummary: "Infrastructure operator for Beagle cluster, deploys, logs, and runbooks.",
    visible: true,
    arousalRole: "recovering",
    icon: "server.rack",
    accent: "posture_warm",
    launchCommand: "",
    readinessProbe: { type: "provider_slot", env: "GLM_PROVIDER_URL" },
    memoryPolicy: "auto_curated",
    riskLevel: "write",
    providerSlots: [
      {
        id: "glm-4.5-air",
        title: "GLM-4.5-Air",
        modelId: "zai-org/GLM-4.5-Air",
        command: "",
        runtime: "openai_compatible_or_local",
        costTier: "medium",
        latencyTier: "interactive",
        privacyTier: "provider_or_local",
        licenseNote: "Use for operational reasoning; approvals still gate destructive commands.",
        enabled: true,
      },
    ],
  },
  {
    role: "global_reader",
    kind: "palmyra-x5",
    title: "Palmyra Reader",
    subtitle: "Huge docs, logs, global state",
    roleSummary: "Long-context reader for repository, manifests, reports, logs, and state synthesis.",
    visible: false,
    arousalRole: "tonic_explore",
    icon: "doc.text.magnifyingglass",
    accent: "truth_observed",
    launchCommand: "",
    readinessProbe: { type: "provider_slot", env: "PALMYRA_API_KEY" },
    memoryPolicy: "summary_only",
    riskLevel: "read",
    providerSlots: [
      {
        id: "palmyra-x5",
        title: "Palmyra X5",
        modelId: "palmyra-x5",
        command: "",
        runtime: "writer_api",
        costTier: "premium",
        latencyTier: "long_context",
        privacyTier: "external_api",
        licenseNote: "Use only on approved docs/logs; never send restricted artifacts.",
        enabled: true,
      },
    ],
  },
  {
    role: "memory_experimenter",
    kind: "jamba",
    title: "Jamba Memory",
    subtitle: "RAG, sequence, compression experiments",
    roleSummary: "Hybrid Transformer/Mamba/MoE scout for long-context and memory experiments.",
    visible: false,
    arousalRole: "tonic_explore",
    icon: "waveform.path.ecg",
    accent: "posture_cool",
    launchCommand: "",
    readinessProbe: { type: "provider_slot", env: "AI21_API_KEY" },
    memoryPolicy: "manual_or_summary",
    riskLevel: "read",
    providerSlots: [
      {
        id: "jamba-1.6",
        title: "AI21 Jamba 1.6",
        modelId: "jamba-1.6",
        command: "",
        runtime: "ai21_api_or_private_deploy",
        costTier: "medium",
        latencyTier: "long_context",
        privacyTier: "provider_or_private",
        licenseNote: "Experimental memory/runtime comparison lane.",
        enabled: true,
      },
    ],
  },
  {
    role: "video_memory",
    kind: "pegasus",
    title: "Pegasus Video",
    subtitle: "Session video, demos, audiovisual memory",
    roleSummary: "Video-first memory lane for walkthroughs, demos, recordings, and screen sessions.",
    visible: false,
    arousalRole: "tonic_explore",
    icon: "video.badge.waveform",
    accent: "truth_remembered",
    launchCommand: "",
    readinessProbe: { type: "provider_slot", env: "AWS_BEDROCK_PEGASUS_PROFILE" },
    memoryPolicy: "artifact_summary_only",
    riskLevel: "read",
    providerSlots: [
      {
        id: "twelvelabs-pegasus-1.2",
        title: "TwelveLabs Pegasus 1.2",
        modelId: "pegasus-1.2",
        command: "",
        runtime: "aws_bedrock",
        costTier: "premium",
        latencyTier: "batch",
        privacyTier: "external_api",
        licenseNote: "Only for explicitly approved private video artifacts.",
        enabled: true,
      },
    ],
  },
  {
    role: "local_sensor",
    kind: "lfm2",
    title: "LFM Sensor",
    subtitle: "Small always-on classifiers",
    roleSummary: "Small local sensor for log classification, anomaly hints, and cheap summaries.",
    visible: false,
    arousalRole: "recovering",
    icon: "sensor",
    accent: "truth_declared",
    launchCommand: "",
    readinessProbe: { type: "local_model", model: "LiquidAI/LFM2.5-1.2B-Instruct" },
    memoryPolicy: "signals_only",
    riskLevel: "read",
    providerSlots: [
      {
        id: "liquid-lfm2",
        title: "Liquid LFM2/LFM2.5",
        modelId: "LiquidAI/LFM2.5-1.2B-Instruct",
        command: "",
        runtime: "local_transformers_or_mlx",
        costTier: "low",
        latencyTier: "fast",
        privacyTier: "local",
        licenseNote: "Use for low-risk local signals; not a reasoning authority.",
        enabled: true,
      },
    ],
  },
  {
    role: "coding_ui",
    kind: "cursor",
    title: "Cursor / OpenCode",
    subtitle: "Coding UI and alternate agent harness",
    roleSummary: "Editor/terminal-native coding harness lane for comparison and focused UI workflows.",
    visible: false,
    arousalRole: "phasic_focus",
    icon: "cursorarrow.motionlines",
    accent: "truth_observed",
    launchCommand: "cursor-agent",
    readinessProbe: { type: "command", command: "cursor-agent" },
    memoryPolicy: "auto_curated",
    riskLevel: "write",
    providerSlots: [
      {
        id: "cursor-agent",
        title: "Cursor Agent CLI",
        modelId: "cursor-agent",
        command: "cursor-agent",
        runtime: "cli",
        costTier: "premium",
        latencyTier: "interactive",
        privacyTier: "workspace",
        licenseNote: "Cursor account and CLI policy apply.",
        enabled: true,
      },
      {
        id: "opencode",
        title: "OpenCode",
        modelId: "opencode",
        command: "opencode",
        runtime: "cli",
        costTier: "variable",
        latencyTier: "interactive",
        privacyTier: "workspace",
        licenseNote: "OpenCode/provider policy applies.",
        enabled: true,
      },
    ],
  },
  {
    role: "shell",
    kind: "human",
    title: "Shell",
    subtitle: "Human terminal",
    roleSummary: "Direct operator lane for shell commands and manual inspection.",
    visible: true,
    arousalRole: "phasic_focus",
    icon: "terminal",
    accent: "text_secondary",
    launchCommand: "",
    readinessProbe: { type: "builtin" },
    memoryPolicy: "manual_or_auto_safe",
    riskLevel: "write",
    providerSlots: [
      {
        id: "shell-pty",
        title: "Workspace Shell",
        modelId: "human",
        command: "",
        runtime: "pty",
        costTier: "none",
        latencyTier: "instant",
        privacyTier: "workspace",
        licenseNote: "Human operator; commands still pass through block/redaction memory policy.",
        enabled: true,
      },
    ],
  },
];

export const SECRET_PATTERNS = [
  /(?:api[_-]?key|client[_-]?secret|refresh[_-]?token|access[_-]?token|password|passwd)\s*[:=]/i,
  /bearer\s+[a-z0-9._~+/=-]{16,}/i,
  /-----BEGIN [A-Z ]*PRIVATE KEY-----/,
  /\bsk-[a-zA-Z0-9]{20,}/,
  /\bghp_[a-zA-Z0-9]{20,}/,
  /\bxox[baprs]-[a-zA-Z0-9-]{20,}/,
];

const AUTO_MEMORY_COMMAND_PATTERNS = [
  /\b(codex|claude|claude-code|cursor|opencode|kimi)\b/i,
  /\b(swift test|xcodebuild|cargo test|npm test|pytest|pnpm test|bun test|build)\b/i,
  /\b(git diff|git show|git commit|git status|git log|diffstat)\b/i,
  /\b(kubectl|helm|terraform|rollout|deploy|apply)\b/i,
  /\b(plan|decision|summary|next action|sounio|beagle|paperrun)\b/i,
];

const AUTO_MEMORY_OUTPUT_PATTERNS = [
  /\b(BUILD SUCCEEDED|BUILD FAILED|tests? passed|tests? failed|FAILED|error|warning)\b/i,
  /\bdiff --git\b/i,
  /\b(decision|next action|summary|approval|approved|rejected)\b/i,
];

export function cleanString(value) {
  if (typeof value === "string") return value.trim();
  if (typeof value === "number" || typeof value === "boolean") return String(value).trim();
  return "";
}

export function nowIso() {
  return new Date().toISOString();
}

export function safeId(value, fallback = "default") {
  const cleaned = cleanString(value)
    .toLowerCase()
    .replace(/[^a-z0-9_.:-]/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "");
  return cleaned || fallback;
}

export function hashObject(payload) {
  return `sha256:${createHash("sha256").update(JSON.stringify(payload)).digest("hex")}`;
}

export function stripControl(text) {
  return cleanString(text)
    .replace(/\x1b\[[0-?]*[ -/]*[@-~]/g, "")
    .replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/g, "");
}

export function hasSecret(text) {
  const value = cleanString(text);
  if (!value) return false;
  return SECRET_PATTERNS.some((pattern) => pattern.test(value));
}

export function commandTitle(command) {
  const stripped = stripControl(command).replace(/\s+/g, " ").trim();
  if (!stripped) return "Command";
  return stripped.length > 72 ? `${stripped.slice(0, 69)}...` : stripped;
}

export function bridgeMetadata({ sourceModel = "beagle", rendererHint = WORKBENCH_PROTOCOL, payload = {} } = {}) {
  const cleanSource = safeId(sourceModel, "beagle");
  return {
    sourceModel: cleanSource,
    source_model: cleanSource,
    bridgeVersion: WORKBENCH_BRIDGE_VERSION,
    bridge_version: WORKBENCH_BRIDGE_VERSION,
    rendererHint,
    renderer_hint: rendererHint,
    bridgeHash: hashObject({ sourceModel: cleanSource, rendererHint, payload }),
  };
}

export function workspaceDir(rootDir, slug) {
  return path.join(rootDir, safeId(slug));
}

export function sessionsPath(rootDir, slug) {
  return path.join(workspaceDir(rootDir, slug), "sessions.json");
}

export function blockLogPath(rootDir, slug, sessionId) {
  return path.join(workspaceDir(rootDir, slug), "sessions", safeId(sessionId), "blocks.ndjson");
}

export async function ensureWorkspaceDir(rootDir, slug, sessionId = "") {
  await fs.mkdir(workspaceDir(rootDir, slug), { recursive: true, mode: 0o700 });
  if (sessionId) {
    await fs.mkdir(path.dirname(blockLogPath(rootDir, slug, sessionId)), { recursive: true, mode: 0o700 });
  }
}

export async function readJsonFile(filePath, fallback) {
  try {
    return JSON.parse(await fs.readFile(filePath, "utf8"));
  } catch (error) {
    if (error?.code === "ENOENT") return fallback;
    throw error;
  }
}

export async function writeJsonFile(filePath, payload) {
  await fs.mkdir(path.dirname(filePath), { recursive: true, mode: 0o700 });
  await fs.writeFile(filePath, `${JSON.stringify(payload, null, 2)}\n`, { mode: 0o600 });
}

export async function readSessions(rootDir, slug) {
  return await readJsonFile(sessionsPath(rootDir, slug), { sessions: [] });
}

export async function writeSessions(rootDir, slug, state) {
  await writeJsonFile(sessionsPath(rootDir, slug), { ...state, updatedAt: nowIso() });
}

export function normalizePane(pane = {}, index = 0) {
  const kind = AGENT_KINDS.has(cleanString(pane.kind)) ? cleanString(pane.kind) : "human";
  const agentRole = cleanString(pane.agentRole || pane.agent_role);
  const providerSlot = cleanString(pane.providerSlot || pane.provider_slot);
  const modelId = cleanString(pane.modelId || pane.model_id);
  return {
    id: cleanString(pane.id) || (index === 0 ? "pane-main" : `pane-${randomUUID()}`),
    title: cleanString(pane.title) || (kind === "human" ? "Shell" : kind),
    kind,
    status: cleanString(pane.status) || "idle",
    createdAt: cleanString(pane.createdAt) || nowIso(),
    lastAttachedAt: cleanString(pane.lastAttachedAt),
    cwd: cleanString(pane.cwd),
    reconnectState: cleanString(pane.reconnectState || pane.reconnect_state || "fresh"),
    agentRole: agentRole || null,
    providerSlot: providerSlot || null,
    modelId: modelId || null,
    routeReason: cleanString(pane.routeReason || pane.route_reason) || null,
    arousalMode: cleanString(pane.arousalMode || pane.arousal_mode) || null,
    agent: pane.agent || (agentRole || modelId ? {
      kind,
      role: agentRole,
      providerSlot,
      modelId,
      state: cleanString(pane.agentState || pane.agent_state || "idle"),
      summary: cleanString(pane.routeReason || pane.route_reason),
    } : null),
  };
}

export function agentRegistry() {
  return AGENT_ROLE_REGISTRY.map((entry) => ({
    ...entry,
    enabled: entry.enabled !== false,
    providerSlots: (entry.providerSlots || []).map((slot) => ({
      ...slot,
      enabled: slot.enabled !== false,
    })),
  }));
}

export function findAgentRole(roleOrKind) {
  const wanted = safeId(roleOrKind, "");
  return agentRegistry().find((entry) =>
    entry.role === wanted ||
    entry.kind === wanted ||
    safeId(entry.title, "") === wanted ||
    (entry.providerSlots || []).some((slot) => slot.id === wanted || safeId(slot.title, "") === wanted)
  );
}

function textMatchesAny(text, patterns) {
  return patterns.some((pattern) => pattern.test(text));
}

export function arousalModeForRoute({ query = "", preferredMode = "" } = {}) {
  const forced = cleanString(preferredMode);
  if (forced) return forced;
  const text = cleanString(query).toLowerCase();
  if (/\b(failed|failure|erro|error|incident|rollback|quebrou|broken|blocked|scope|write|oauth|auth)\b/i.test(text)) {
    return "recovering";
  }
  if (/\b(explore|comparar|compare|arquitetura|semantics|semântica|claim|type system|research|review|hip[oó]tese)\b/i.test(text)) {
    return "tonic_explore";
  }
  if (/\b(tired|fatigued|overload|exausto|cansado)\b/i.test(text)) {
    return "fatigued";
  }
  return "phasic_focus";
}

export function routeAgentTask(input = {}) {
  const task = cleanString(input.task || input.query || input.prompt || input.summary);
  const text = task.toLowerCase();
  const registry = agentRegistry();
  const choose = (role) => registry.find((entry) => entry.role === role) || registry[0];
  let chosenRole = "primary_builder";
  let reason = "Default to Claude/Codex for high-stakes implementation when no narrower role matches.";
  let expectedArtifacts = ["plan", "diff", "tests", "work_memory"];

  if (textMatchesAny(text, [/\b(refactor|compiler|bug|test|failing|swift test|cargo test|npm test|lint|patch)\b/i])) {
    chosenRole = textMatchesAny(text, [/\b(cheap|small|maintenance|lint|continuous|loop)\b/i])
      ? "maintenance_agent"
      : "code_worker";
    reason = "Refactor, compiler, bug, or test loop should go to a code-worker role before premium synthesis.";
    expectedArtifacts = ["diff", "test_result", "memory_block"];
  } else if (textMatchesAny(text, [/\b(sounio|semantics|semântica|claim|claim<t>|effect|type system|epistemic|epistemicgrad|formal)\b/i])) {
    chosenRole = "long_thought_architect";
    reason = "Sounio language semantics and epistemic typing benefit from a long-thought architecture lane.";
    expectedArtifacts = ["semantic_note", "claim_seed", "decision"];
  } else if (textMatchesAny(text, [/\b(k8s|kubernetes|cluster|deploy|rollout|pod|service|runbook|incident|cloudflare|auth0|oauth)\b/i])) {
    chosenRole = "platform_operator";
    reason = "Infrastructure, cluster, and incident work should route to the platform-operator role.";
    expectedArtifacts = ["runbook_step", "cluster_check", "audit_note"];
  } else if (textMatchesAny(text, [/\b(whole repo|repo inteiro|readme|docs|logs|manifest|state|estado global|síntese operacional|sintese operacional)\b/i])) {
    chosenRole = "global_reader";
    reason = "Huge docs, manifests, and log synthesis need the long-context reader role.";
    expectedArtifacts = ["state_synthesis", "source_map"];
  } else if (textMatchesAny(text, [/\b(rag|memory|memória|sequence|compress|compression|jamba|mamba|ssm)\b/i])) {
    chosenRole = "memory_experimenter";
    reason = "Memory, sequence, and long-context experiments should route to the memory-experimenter role.";
    expectedArtifacts = ["experiment_note", "comparison"];
  } else if (textMatchesAny(text, [/\b(video|recording|screen|demo|walkthrough|audiovisual|pegasus)\b/i])) {
    chosenRole = "video_memory";
    reason = "Video, screen, and audiovisual sessions need the video-memory role.";
    expectedArtifacts = ["video_summary", "temporal_evidence"];
  } else if (textMatchesAny(text, [/\b(log classify|anomaly|sensor|sidecar|cheap signal|lfm)\b/i])) {
    chosenRole = "local_sensor";
    reason = "Cheap continuous classification and anomaly signals should run through local sensors.";
    expectedArtifacts = ["signal", "anomaly_hint"];
  } else if (textMatchesAny(text, [/\b(cursor|opencode|coding ui|editor)\b/i])) {
    chosenRole = "coding_ui";
    reason = "Editor/terminal coding UI requests should route to the alternate coding harness role.";
    expectedArtifacts = ["agent_transcript", "diff"];
  }

  const chosen = choose(chosenRole);
  const fallbackRoles = Array.isArray(input.fallback_roles) && input.fallback_roles.length > 0
    ? input.fallback_roles.map((role) => cleanString(role)).filter(Boolean)
    : fallbackRolesFor(chosenRole);
  const fallbackSlots = fallbackRoles
    .map((role) => choose(role))
    .filter((entry) => entry && entry.role !== chosen.role)
    .map((entry) => ({
      role: entry.role,
      kind: entry.kind,
      title: entry.title,
      providerSlots: entry.providerSlots,
    }));
  const arousalMode = arousalModeForRoute({ query: task, preferredMode: input.arousal_mode || input.arousalMode });
  const privacyClass = cleanString(input.privacy_class || input.privacyClass || "sensitive");
  return {
    id: `route-${Date.now().toString(36)}-${randomUUID().slice(0, 8)}`,
    createdAt: nowIso(),
    projectSlug: cleanString(input.project_slug || input.projectSlug) || "sounio",
    task,
    chosenRole: chosen.role,
    chosen_role: chosen.role,
    chosenSlot: {
      role: chosen.role,
      kind: chosen.kind,
      title: chosen.title,
      providerSlots: chosen.providerSlots,
    },
    chosen_slot: {
      role: chosen.role,
      kind: chosen.kind,
      title: chosen.title,
      provider_slots: chosen.providerSlots,
    },
    fallbackSlots,
    fallback_slots: fallbackSlots,
    reason,
    arousalMode,
    arousal_mode: arousalMode,
    privacyConstraints: privacyClass === "restricted"
      ? ["restricted_local_only", "do_not_send_to_external_provider"]
      : ["cluster_canonical_memory", "redact_secrets_before_import"],
    privacy_constraints: privacyClass === "restricted"
      ? ["restricted_local_only", "do_not_send_to_external_provider"]
      : ["cluster_canonical_memory", "redact_secrets_before_import"],
    expectedArtifacts,
    expected_artifacts: expectedArtifacts,
    registryVersion: "beagle-agent-ecology-v3.5",
    registry_version: "beagle-agent-ecology-v3.5",
  };
}

function fallbackRolesFor(role) {
  switch (role) {
    case "code_worker": return ["maintenance_agent", "primary_builder"];
    case "maintenance_agent": return ["code_worker", "primary_builder"];
    case "long_thought_architect": return ["primary_builder", "global_reader"];
    case "platform_operator": return ["primary_builder", "local_sensor"];
    case "global_reader": return ["long_thought_architect", "primary_builder"];
    case "memory_experimenter": return ["long_thought_architect", "local_sensor"];
    case "video_memory": return ["global_reader", "primary_builder"];
    case "local_sensor": return ["platform_operator", "primary_builder"];
    case "coding_ui": return ["code_worker", "primary_builder"];
    default: return ["long_thought_architect", "code_worker"];
  }
}

export function normalizeSession(slug, session = {}) {
  const panes = Array.isArray(session.panes) && session.panes.length > 0
    ? session.panes.map(normalizePane)
    : [normalizePane({ id: "pane-main", kind: "human", title: "Shell" }, 0)];
  const base = {
    id: cleanString(session.id) || `wb-${Date.now().toString(36)}-${randomUUID().slice(0, 8)}`,
    projectSlug: cleanString(session.projectSlug || session.project_slug) || slug,
    title: cleanString(session.title) || "Sounio Workbench",
    status: cleanString(session.status) || "active",
    layout: cleanString(session.layout) || "notebook",
    createdAt: cleanString(session.createdAt || session.created_at) || nowIso(),
    updatedAt: cleanString(session.updatedAt || session.updated_at) || nowIso(),
    lastAttachedAt: cleanString(session.lastAttachedAt || session.last_attached_at),
    lastMemoryStatus: session.lastMemoryStatus || session.last_memory_status || null,
    authorityStatus: session.authorityStatus || session.authority_status || null,
    panes,
  };
  const bridge = bridgeMetadata({
    sourceModel: cleanString(session.sourceModel || session.source_model || "beagle"),
    rendererHint: cleanString(session.rendererHint || session.renderer_hint || WORKBENCH_PROTOCOL),
    payload: { id: base.id, projectSlug: base.projectSlug, panes: base.panes.map((pane) => pane.id) },
  });
  return {
    ...base,
    sourceModel: bridge.sourceModel,
    bridgeVersion: bridge.bridgeVersion,
    sessionHash: cleanString(session.sessionHash || session.session_hash) || bridge.bridgeHash,
    rendererHint: bridge.rendererHint,
  };
}

export async function getOrCreateSession(rootDir, slug, sessionId = "", body = {}) {
  await ensureWorkspaceDir(rootDir, slug);
  const state = await readSessions(rootDir, slug);
  const requestedId = cleanString(sessionId || body.session_id || body.sessionId);
  const found = state.sessions.find((entry) => cleanString(entry.id) === requestedId);
  if (found) return normalizeSession(slug, found);

  const session = normalizeSession(slug, {
    id: requestedId,
    title: cleanString(body.title),
    layout: cleanString(body.layout),
  });
  state.sessions = [session, ...state.sessions].slice(0, 80);
  await writeSessions(rootDir, slug, state);
  await ensureWorkspaceDir(rootDir, slug, session.id);
  return session;
}

export async function updateSession(rootDir, slug, sessionId, mutate) {
  const state = await readSessions(rootDir, slug);
  const index = state.sessions.findIndex((entry) => cleanString(entry.id) === cleanString(sessionId));
  if (index < 0) {
    const error = new Error("workspace session not found");
    error.statusCode = 404;
    throw error;
  }
  const next = normalizeSession(slug, mutate(normalizeSession(slug, state.sessions[index])));
  next.updatedAt = nowIso();
  state.sessions[index] = next;
  await writeSessions(rootDir, slug, state);
  return next;
}

export async function appendBlockEvent(rootDir, slug, sessionId, event) {
  await ensureWorkspaceDir(rootDir, slug, sessionId);
  await fs.appendFile(blockLogPath(rootDir, slug, sessionId), `${JSON.stringify(event)}\n`, { mode: 0o600 });
}

export async function readBlockEvents(rootDir, slug, sessionId) {
  try {
    const raw = await fs.readFile(blockLogPath(rootDir, slug, sessionId), "utf8");
    return raw
      .split("\n")
      .map((line) => line.trim())
      .filter(Boolean)
      .map((line) => JSON.parse(line));
  } catch (error) {
    if (error?.code === "ENOENT") return [];
    throw error;
  }
}

export function foldBlocks(events) {
  const byId = new Map();
  for (const event of events) {
    const blockId = cleanString(event.blockId || event.block_id);
    if (!blockId) continue;
    if (!byId.has(blockId)) {
      byId.set(blockId, {
        id: blockId,
        sessionId: cleanString(event.sessionId),
        paneId: cleanString(event.paneId),
        kind: "command",
        title: "",
        command: "",
        outputPreview: "",
        outputByteCount: 0,
        startedAt: cleanString(event.at) || nowIso(),
        finishedAt: "",
        durationMs: null,
        exitCode: null,
        status: "running",
        privacyClass: "sensitive",
        memoryStatus: "not_saved",
        tags: [],
        provenance: {},
        sourceModel: cleanString(event.sourceModel || event.source_model || "beagle"),
        bridgeVersion: cleanString(event.bridgeVersion || event.bridge_version || WORKBENCH_BRIDGE_VERSION),
        blockHash: "",
        sessionHash: cleanString(event.sessionHash || event.session_hash),
        rendererHint: cleanString(event.rendererHint || event.renderer_hint || WORKBENCH_PROTOCOL),
      });
    }
    const block = byId.get(blockId);
    if (event.type === "block_started") {
      block.kind = cleanString(event.kind) || block.kind;
      block.title = cleanString(event.title) || block.title;
      block.command = cleanString(event.command) || block.command;
      block.startedAt = cleanString(event.startedAt || event.at) || block.startedAt;
      block.status = "running";
      block.privacyClass = cleanString(event.privacyClass) || block.privacyClass;
      block.tags = Array.isArray(event.tags) ? event.tags : block.tags;
      block.provenance = event.provenance || block.provenance;
      block.sourceModel = cleanString(event.sourceModel || event.source_model) || block.sourceModel;
      block.bridgeVersion = cleanString(event.bridgeVersion || event.bridge_version) || block.bridgeVersion;
      block.blockHash = cleanString(event.blockHash || event.block_hash) || block.blockHash;
      block.sessionHash = cleanString(event.sessionHash || event.session_hash) || block.sessionHash;
      block.rendererHint = cleanString(event.rendererHint || event.renderer_hint) || block.rendererHint;
    }
    if (event.type === "block_output") {
      const chunk = String(event.data || "");
      block.outputByteCount += Buffer.byteLength(chunk);
      if (block.outputPreview.length < 12000) {
        block.outputPreview = `${block.outputPreview}${chunk}`.slice(0, 12000);
      }
    }
    if (event.type === "block_finished") {
      block.finishedAt = cleanString(event.finishedAt || event.at) || nowIso();
      block.durationMs = Number.isFinite(Number(event.durationMs)) ? Number(event.durationMs) : block.durationMs;
      block.exitCode = Number.isFinite(Number(event.exitCode)) ? Number(event.exitCode) : block.exitCode;
      block.status = cleanString(event.status) || "finished";
      block.privacyClass = cleanString(event.privacyClass) || block.privacyClass;
    }
    if (event.type === "memory") {
      block.memoryStatus = cleanString(event.status) || block.memoryStatus;
      block.memoryEventId = cleanString(event.memoryEventId);
      block.auditEventId = cleanString(event.auditEventId);
      block.memoryError = cleanString(event.error);
    }
    if (event.type === "secret_redacted") {
      block.privacyClass = "restricted_local_only";
      block.status = "blocked";
      block.memoryStatus = "blocked";
    }
  }
  for (const block of byId.values()) {
    if (!block.blockHash) {
      block.blockHash = hashObject({
        id: block.id,
        command: block.command,
        outputByteCount: block.outputByteCount,
        startedAt: block.startedAt,
      });
    }
  }
  return Array.from(byId.values()).sort((left, right) =>
    cleanString(right.startedAt).localeCompare(cleanString(left.startedAt))
  );
}

export function shouldAutoRememberBlock(block) {
  if (!block || block.privacyClass === "restricted_local_only") return false;
  const command = cleanString(block.command);
  const output = cleanString(block.outputPreview);
  if (!command && !output) return false;
  if (hasSecret(`${command}\n${output}`)) return false;
  return AUTO_MEMORY_COMMAND_PATTERNS.some((pattern) => pattern.test(command)) ||
    AUTO_MEMORY_OUTPUT_PATTERNS.some((pattern) => pattern.test(output));
}

export function detectAgentState(text) {
  const value = stripControl(text).toLowerCase();
  if (!value) return "";
  if (value.includes("running tests") || value.includes("test failed") || value.includes("test passed")) {
    return "running_tests";
  }
  if (value.includes("approval") || value.includes("allow this") || value.includes("proceed?")) {
    return "approval_wait";
  }
  if (value.includes("thinking") || value.includes("planning")) return "thinking";
  if (value.includes("done") || value.includes("complete")) return "done";
  return "";
}

export function detectWorkbenchSignals(text) {
  const value = stripControl(text);
  const signals = [];
  if (/\b(swift test|xcodebuild|cargo test|npm test|pytest|tests? passed|tests? failed|BUILD SUCCEEDED|BUILD FAILED)\b/i.test(value)) {
    signals.push({ type: "test_detected", status: /fail|failed|BUILD FAILED/i.test(value) ? "failed" : "observed" });
  }
  if (/\bdiff --git\b|\bfiles? changed\b|\bdiffstat\b/i.test(value)) {
    signals.push({ type: "diff_detected", status: "observed" });
  }
  if (/\b(approval|approve|allow this|proceed\?|confirm)\b/i.test(value)) {
    signals.push({ type: "approval_requested", status: "pending" });
  }
  return signals;
}

import {
  getAgentSession,
  listAgentSessions,
  pauseAgentSession,
  resumeAgentSession,
  startAgentSession,
  stopAgentSession
} from "./agent-routes.mjs";
import {
  contractFailure,
  ErrorCode,
  idempotent,
  withEnvelope
} from "./contract.mjs";
import { getHpcResult, listHpcResults } from "./job-routes.mjs";
import {
  proxyBeagleCompletion,
  proxyCheapProviderCompletion,
  proxySubscriptionBridgeCompletion,
  proxyDiscussionLabCompletion
} from "./auth-bridge.mjs";
import { appendScratchpadEntry, buildScratchpadEntry } from "./scratchpad-routes.mjs";

function cleanString(value) {
  if (typeof value === "string") {
    const trimmed = value.trim();
    return trimmed ? trimmed : "";
  }
  if (typeof value === "number" || typeof value === "boolean") {
    return String(value).trim();
  }
  return "";
}

function mapStatusCodeToErrorCode(statusCode) {
  if (statusCode === 400) return ErrorCode.BAD_REQUEST;
  if (statusCode === 401) return ErrorCode.UNAUTHORIZED;
  if (statusCode === 404) return ErrorCode.NOT_FOUND;
  if (statusCode === 409) return ErrorCode.CONFLICT;
  if (statusCode === 429) return ErrorCode.RATE_LIMIT;
  if (statusCode === 503) return ErrorCode.RUNTIME_UNAVAILABLE;
  if (statusCode === 504) return ErrorCode.TIMEOUT;
  return ErrorCode.INTERNAL;
}

function rethrowAsContract(error, fallbackMessage = "mobile route failed") {
  if (error?.code && ErrorCode[error.code]) {
    throw error;
  }
  const mapped = mapStatusCodeToErrorCode(error?.statusCode);
  throw contractFailure(mapped, error?.message || fallbackMessage);
}

function acceptBodyIdempotencyKey(req, _res, next) {
  const bodyKey = cleanString(req.body?.idempotencyKey);
  if (bodyKey && !req.headers["x-request-id"]) {
    req.headers["x-request-id"] = bodyKey;
  }
  next();
}

function requireConfirmed(req, actionLabel) {
  if (req.body?.confirmed === true) {
    return;
  }
  throw contractFailure(
    ErrorCode.BAD_REQUEST,
    `${actionLabel} requires confirmed: true`
  );
}

function deriveTruthMode(...values) {
  for (const value of values) {
    if (!value || typeof value !== "object") {
      continue;
    }
    const directTruthMode = cleanString(value.truthMode);
    if (directTruthMode) {
      return directTruthMode;
    }
    const nestedTruthMode = cleanString(value.truth?.truthMode);
    if (nestedTruthMode) {
      return nestedTruthMode;
    }
  }
  return "observed";
}

function normalizeCheapDiscussionProfile(value) {
  const normalized = cleanString(value).toLowerCase();
  if (!normalized) {
    return "";
  }
  if (["grok", "grok_fast", "grok-fast"].includes(normalized)) {
    return "grok";
  }
  if (["kimi", "kimi_k2", "kimi-k2", "moonshot"].includes(normalized)) {
    return "kimi";
  }
  return "";
}

function normalizeSubscriptionDiscussionProfile(value) {
  const normalized = cleanString(value).toLowerCase();
  if (!normalized) {
    return "";
  }
  if (["claude", "claude-code", "claudecode", "claude-max", "claude_max"].includes(normalized)) {
    return "claude-code";
  }
  if (["codex", "codex-chat", "codex-pro", "chatgpt-pro"].includes(normalized)) {
    return "codex";
  }
  return "";
}

function buildMeta(generatedAt, ...values) {
  return {
    generatedAt: cleanString(generatedAt) || new Date().toISOString(),
    truthMode: deriveTruthMode(...values)
  };
}

function normalizeSource(value) {
  const source = cleanString(value).toLowerCase();
  if (["device", "cluster", "agent", "hybrid"].includes(source)) {
    return source;
  }
  return "";
}

function findDiscussionLabProfile(catalog = {}, requestedProfile = "") {
  const profileId = cleanString(requestedProfile);
  if (!profileId) {
    return null;
  }
  const projects = Array.isArray(catalog?.projects) ? catalog.projects : [];
  for (const project of projects) {
    const profiles = Array.isArray(
      project?.inferenceCapabilities?.compat?.discussionLab?.profiles
    )
      ? project.inferenceCapabilities.compat.discussionLab.profiles
      : [];
    const found = profiles.find(
      (profile) => cleanString(profile?.id).toLowerCase() === profileId.toLowerCase()
    );
    if (found) {
      return found;
    }
  }
  return null;
}

function deriveProjectFamily(slug, requested = "") {
  const normalizedRequested = cleanString(requested).toLowerCase();
  if (["language", "hsn", "experimental", "platform"].includes(normalizedRequested)) {
    return normalizedRequested;
  }
  const normalizedSlug = cleanString(slug).toLowerCase();
  if (normalizedSlug === "sounio") {
    return "language";
  }
  if (normalizedSlug === "hyperbolic-semantic-networks") {
    return "hsn";
  }
  return "experimental";
}

function derivePublicationScope(projectFamily, requested = "") {
  const normalizedRequested = cleanString(requested).toLowerCase();
  if (["public", "internal", "conference", "draft"].includes(normalizedRequested)) {
    return normalizedRequested;
  }
  if (projectFamily === "language") {
    return "public";
  }
  if (projectFamily === "hsn") {
    return "conference";
  }
  return "internal";
}

function normalizePhysioPolicy(raw = {}) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    return null;
  }

  const modeLabel = cleanString(raw.modeLabel || raw.mode_label);
  const routeLabel = cleanString(raw.routeLabel || raw.route_label);
  const companionInstruction = cleanString(
    raw.companionInstruction || raw.companion_instruction
  );
  const noteInstruction = cleanString(raw.noteInstruction || raw.note_instruction);
  const pacingInstruction = cleanString(
    raw.pacingInstruction || raw.pacing_instruction
  );
  const discussionProfile = cleanString(
    raw.discussionProfile || raw.discussion_profile
  ).toLowerCase();
  const suggestedPlaceholder = cleanString(
    raw.suggestedPlaceholder || raw.suggested_placeholder
  );
  const preferLocal =
    raw.preferLocal === true || raw.prefer_local === true;

  if (
    !modeLabel &&
    !routeLabel &&
    !companionInstruction &&
    !noteInstruction &&
    !pacingInstruction &&
    !discussionProfile &&
    !suggestedPlaceholder &&
    !preferLocal
  ) {
    return null;
  }

  return {
    modeLabel,
    routeLabel,
    companionInstruction,
    noteInstruction,
    pacingInstruction,
    discussionProfile,
    suggestedPlaceholder,
    preferLocal
  };
}

function buildMobileChatSystem(system, flowState, physioPolicy) {
  const lines = [];
  const systemText = cleanString(system);
  if (systemText) {
    lines.push(systemText);
  }
  const normalizedFlowState = cleanString(flowState).toUpperCase();
  if (normalizedFlowState) {
    lines.push(`Flow state: ${normalizedFlowState}.`);
  }
  if (physioPolicy?.modeLabel) {
    lines.push(`Companion mode: ${physioPolicy.modeLabel}.`);
  }
  if (physioPolicy?.routeLabel) {
    lines.push(`Route posture: ${physioPolicy.routeLabel}.`);
  }
  if (physioPolicy?.companionInstruction) {
    lines.push(`Companion behavior: ${physioPolicy.companionInstruction}`);
  }
  if (physioPolicy?.noteInstruction) {
    lines.push(`Note behavior: ${physioPolicy.noteInstruction}`);
  }
  if (physioPolicy?.pacingInstruction) {
    lines.push(`Pacing behavior: ${physioPolicy.pacingInstruction}`);
  }
  if (physioPolicy?.suggestedPlaceholder) {
    lines.push(`Prompting stance: ${physioPolicy.suggestedPlaceholder}`);
  }
  return lines.filter(Boolean).join("\n\n");
}

function estimateTokenCount(prompt, system, response) {
  const mergedPrompt = `${cleanString(system)}\n\n${cleanString(prompt)}`.trim();
  const combined = `${mergedPrompt}\n\n${cleanString(response)}`.trim();
  if (!combined) {
    return 0;
  }
  return Math.max(1, Math.ceil(combined.length / 4));
}

function normalizeProject(project = {}) {
  return {
    slug: cleanString(project.projectSlug || "unknown"),
    title: cleanString(project.displayName || project.projectSlug || "unknown"),
    posture: cleanString(project.mode || "undeclared"),
    workspaceId: cleanString(project.workspaceId || ""),
    workstreamId: cleanString(project.workstreamId || ""),
    namespace: cleanString(project.namespace || ""),
    branch: cleanString(project.branch || ""),
    workspaceBootstrapBranch: cleanString(project.workspaceBootstrapBranch || ""),
    workspaceRoot: cleanString(project.workspaceRoot || "")
  };
}

function normalizeClientSession(session = {}) {
  return {
    ...session,
    projectFamily: cleanString(session.projectFamily || ""),
    publicationScope: cleanString(session.publicationScope || ""),
    promotionState: cleanString(session.promotionState || ""),
    workspaceTarget: cleanString(session.workspaceTarget || "")
  };
}

function normalizeCatalogProject(entry = {}) {
  return {
    slug: cleanString(entry.projectSlug || "unknown"),
    posture: cleanString(entry.mode || "undeclared"),
    memoryStatus: cleanString(entry.memoryStatus || "unknown"),
    missionControl: entry.missionControl || {},
    operatingPosture: entry.operatingPosture || {},
    workspace: entry.workspace || null,
    publication: entry.publication || null
  };
}

function normalizeActionList(project, goWorkNowPacket = {}, operatingPosture = null) {
  const posture =
    cleanString(operatingPosture?.project?.posture) ||
    cleanString(goWorkNowPacket?.project?.posture) ||
    cleanString(project?.mode) ||
    "undeclared";
  const activatePreview = cleanString(goWorkNowPacket?.commands?.activateHabitat);
  const standbyPreview = cleanString(goWorkNowPacket?.commands?.standbyHabitat);
  const slug = cleanString(project?.projectSlug || "unknown");

  return [
    {
      id: "activate-habitat",
      label: "Activate habitat",
      confirmRequired: true,
      enabled: true,
      availability: posture === "always-on" ? "verify-live" : "scale-to-one",
      commandPreview: activatePreview,
      route: `/api/mobile/v1/projects/${slug}/actions/activate-habitat`
    },
    {
      id: "standby-habitat",
      label: "Put habitat on standby",
      confirmRequired: true,
      enabled: posture !== "always-on",
      availability:
        posture === "always-on" ? "disabled-for-always-on" : "scale-to-zero",
      commandPreview: standbyPreview,
      route: `/api/mobile/v1/projects/${slug}/actions/standby-habitat`
    }
  ];
}

function normalizeSession(session = {}) {
  const pods = Array.isArray(session.pods) ? session.pods : [];
  const primaryPod = pods[0] || {};
  const exists = Boolean(session.name);
  const activity = session.activity && typeof session.activity === "object"
    ? {
        summary: cleanString(session.activity.summary || ""),
        source: cleanString(session.activity.source || ""),
        updatedAt: cleanString(session.activity.updatedAt || session.activity.updated_at || ""),
        author: cleanString(session.activity.author || ""),
        excerpt: cleanString(session.activity.excerpt || ""),
        consciousnessState: session.activity.consciousnessState || null
      }
    : null;

  return {
    kind: cleanString(session.kind || ""),
    status: cleanString(session.status || (exists ? "pending" : "idle")),
    exists,
    name: cleanString(session.name || ""),
    podName: cleanString(primaryPod.name || ""),
    replicas: Number.isFinite(session.replicas) ? session.replicas : 0,
    readyReplicas: Number.isFinite(session.readyReplicas) ? session.readyReplicas : 0,
    createdAt: cleanString(session.createdAt || ""),
    pods: pods.map((pod) => ({
      name: cleanString(pod.name || ""),
      phase: cleanString(pod.phase || ""),
      ready: Boolean(pod.ready),
      node: cleanString(pod.node || "")
    })),
    activity
  };
}

function extractHpcResultRecords(payload = {}) {
  const candidates = [
    payload?.results,
    payload?.data?.results,
    payload?.data?.items,
    payload?.data?.entries,
    payload?.items,
    payload?.entries,
    payload?.data,
    payload
  ];
  for (const candidate of candidates) {
    if (Array.isArray(candidate)) {
      return candidate;
    }
  }
  return [];
}

function normalizeHpcResultRecord(record = {}) {
  return {
    jobId: cleanString(record.job_id || record.jobId),
    submittedJobId: cleanString(record.submitted_job_id || record.submittedJobId),
    publishedResultJobId: cleanString(
      record.published_result_job_id || record.publishedResultJobId
    ),
    profileId: cleanString(record.profile_id || record.profileId),
    requestedRunLabel: cleanString(
      record.requested_run_label || record.requestedRunLabel || record.run_label || record.runLabel
    ),
    publishedResultRunLabel: cleanString(
      record.published_result_run_label || record.publishedResultRunLabel || record.run_label || record.runLabel
    ),
    publicationState: cleanString(
      record.publication_state ||
      record.publicationState ||
      record.state ||
      record.run_scoped_publication?.publication_state ||
      record.runScopedPublication?.publicationState
    ),
    finalJobState: cleanString(
      record.final_job_state ||
      record.finalJobState ||
      record.state ||
      record.run_scoped_publication?.final_job_state ||
      record.runScopedPublication?.finalJobState
    ),
    manifestKey: cleanString(
      record.published_result_manifest_key ||
      record.publishedResultManifestKey ||
      record.artifact_manifest_key ||
      record.artifactManifestKey
    ),
    resultManifestObjectKey: cleanString(
      record.result_manifest_object_key ||
      record.resultManifestObjectKey ||
      record.artifact_object_key ||
      record.artifactObjectKey
    ),
    resultLookupScope: cleanString(
      record.result_lookup_scope || record.resultLookupScope
    ),
    nodeList: cleanString(record.node_list || record.nodeList),
    sourcePhase: cleanString(record.source_phase || record.sourcePhase),
    retentionScope: cleanString(record.retention_scope || record.retentionScope),
    latestResultAt: latestIso(
      record.updated_at,
      record.updatedAt,
      record.completed_at,
      record.completedAt,
      record.published_at,
      record.publishedAt,
      record.publication_time,
      record.publicationTime,
      record.end_time,
      record.endTime,
      record.start_time,
      record.startTime,
      record.submitted_at,
      record.submittedAt,
      record.submit_time,
      record.submitTime,
      record.created_at,
      record.createdAt,
      record.run_scoped_publication?.updated_at,
      record.runScopedPublication?.updatedAt,
      record.run_scoped_publication?.published_at,
      record.runScopedPublication?.publishedAt,
      record.run_result_identity_receipt?.updated_at,
      record.runResultIdentityReceipt?.updatedAt,
      record.deterministic_result_binding?.updated_at,
      record.deterministicResultBinding?.updatedAt
    ),
    via: cleanString(record.via)
  };
}

function preferNonEmptyValue(current, fallback) {
  if (typeof current === "string") {
    return current.trim() ? current : fallback;
  }
  if (current !== null && current !== undefined) {
    return current;
  }
  return fallback;
}

function mergeNormalizedHpcResultRecords(primary = {}, fallback = {}) {
  const merged = {};
  const keys = new Set([...Object.keys(fallback || {}), ...Object.keys(primary || {})]);
  for (const key of keys) {
    merged[key] = preferNonEmptyValue(primary[key], fallback[key]);
  }
  return merged;
}

function compareLatestResult(left = {}, right = {}) {
  const leftTime = Date.parse(cleanString(left.latestResultAt || "")) || 0;
  const rightTime = Date.parse(cleanString(right.latestResultAt || "")) || 0;
  return rightTime - leftTime;
}

function buildLaneResultSummary(slug, workstreamId, result = {}) {
  const lookupJobId = cleanString(
    result.submittedJobId || result.jobId || result.publishedResultJobId
  );
  const resultJobId = cleanString(result.publishedResultJobId || result.jobId);
  const runLabel = cleanString(
    result.publishedResultRunLabel || result.requestedRunLabel
  );
  const profileId = cleanString(result.profileId);
  const publicationState = cleanString(result.publicationState);
  const finalJobState = cleanString(result.finalJobState);
  const manifestKey = cleanString(result.manifestKey);
  const resultManifestObjectKey = cleanString(result.resultManifestObjectKey);
  const nodeList = cleanString(result.nodeList);
  const sourcePhase = cleanString(result.sourcePhase);
  const retentionScope = cleanString(result.retentionScope);
  const resultReady = Boolean(
    manifestKey || resultManifestObjectKey || resultJobId
  );
  const stateParts = [publicationState, finalJobState].filter(Boolean);

  let signalLine = "No published result has returned yet.";
  if (runLabel && stateParts.length > 0) {
    signalLine = `Latest returned work: ${runLabel} · ${stateParts.join(" · ")}`;
  } else if (runLabel) {
    signalLine = `Latest returned work: ${runLabel}`;
  } else if (profileId && stateParts.length > 0) {
    signalLine = `Latest ${profileId} result is ${stateParts.join(" · ")}`;
  } else if (profileId) {
    signalLine = `Latest returned work came through ${profileId}`;
  } else if (stateParts.length > 0) {
    signalLine = `Latest returned work is ${stateParts.join(" · ")}`;
  }
  const qualifiers = [nodeList, sourcePhase, retentionScope].filter(Boolean);
  if (qualifiers.length > 0 && signalLine !== "No published result has returned yet.") {
    signalLine = `${signalLine} · ${qualifiers.join(" · ")}`;
  }

  let recommendedAction = resultReady
    ? "Open what came back and decide whether it deserves promotion."
    : "Keep watching this lane until the latest run resolves into a published result.";
  if (!lookupJobId) {
    recommendedAction = "Run new work in this lane so Beagle has something concrete to bring back.";
  }

  return {
    projectSlug: slug,
    workstreamId,
    lookupJobId,
    submittedJobId: cleanString(result.submittedJobId),
    publishedResultJobId: cleanString(result.publishedResultJobId),
    profileId,
    requestedRunLabel: cleanString(result.requestedRunLabel),
    publishedResultRunLabel: runLabel,
    publicationState,
    finalJobState,
    manifestKey,
    resultManifestObjectKey,
    resultLookupScope: cleanString(result.resultLookupScope),
    latestResultAt: cleanString(result.latestResultAt),
    resultReady,
    signalLine,
    recommendedAction,
    resultRoute: lookupJobId ? `/api/projects/${slug}/hpc/results/${lookupJobId}` : "",
    manifestRoute: lookupJobId
      ? `/api/projects/${slug}/hpc/results/${lookupJobId}/manifest`
      : "",
    artifactRoute: lookupJobId
      ? `/api/projects/${slug}/hpc/jobs/${lookupJobId}/artifact`
      : "",
    stdoutRoute: lookupJobId
      ? `/api/projects/${slug}/hpc/jobs/${lookupJobId}/stdout-object`
      : "",
    via: cleanString(result.via || "cockpit-darwin-hpc")
  };
}

async function buildProjectLaneResultSummary(project = {}) {
  const slug = cleanString(project?.projectSlug || project?.slug);
  const workstreamId = cleanString(
    project?.workstreamId ||
    project?.workspace?.workstreamId ||
    project?.workspaceState?.workstreamId ||
    ""
  );
  if (!slug || !workstreamId) {
    return null;
  }

  try {
    const listPayload = await listHpcResults({ workstream_id: workstreamId });
    const latest = extractHpcResultRecords(listPayload)
      .map(normalizeHpcResultRecord)
      .filter(
        (entry) =>
          cleanString(entry.jobId || entry.submittedJobId || entry.publishedResultJobId)
      )
      .sort(compareLatestResult)[0];

    if (!latest) {
      return null;
    }

    const detailLookupId = cleanString(
      latest.submittedJobId || latest.jobId || latest.publishedResultJobId
    );
    let detailed = latest;
    if (detailLookupId) {
      try {
        const detailPayload = await getHpcResult(slug, detailLookupId);
        detailed = mergeNormalizedHpcResultRecords(
          normalizeHpcResultRecord(detailPayload?.data || detailPayload),
          latest
        );
      } catch {
        detailed = latest;
      }
    }

    return buildLaneResultSummary(slug, workstreamId, detailed);
  } catch {
    return null;
  }
}

function inferClusterHealth(catalog = {}) {
  const projects = Array.isArray(catalog?.projects) ? catalog.projects : [];
  const statuses = projects
    .map(
      (entry) =>
        cleanString(entry?.operatingPosture?.cluster?.status) ||
        cleanString(entry?.missionControl?.cluster?.status) ||
        cleanString(entry?.operatingPosture?.project?.posture)
    )
    .filter(Boolean);

  if (statuses.some((status) => ["failed", "error", "critical"].includes(status))) {
    return "critical";
  }
  if (statuses.some((status) => ["degraded", "stale", "warn", "warning"].includes(status))) {
    return "degraded";
  }
  if (statuses.some((status) => ["healthy", "always-on", "live"].includes(status))) {
    return "healthy";
  }
  return "unknown";
}

function latestIso(...values) {
  const normalized = values
    .flat()
    .map((value) => cleanString(value))
    .filter(Boolean)
    .sort((left, right) => new Date(right).getTime() - new Date(left).getTime());
  return normalized[0] || "";
}

async function completeChatRequest(req, deps) {
  const prompt = cleanString(req.body?.prompt);
  if (!prompt) {
    throw contractFailure(ErrorCode.BAD_REQUEST, "prompt is required");
  }

  const system = cleanString(req.body?.system);
  const requiresMath =
    req.body?.requires_math === true || req.body?.requiresMath === true;
  const requiresHighQuality =
    req.body?.requires_high_quality === true || req.body?.requiresHighQuality === true;
  const offlineRequired =
    req.body?.offline_required === true || req.body?.offlineRequired === true;
  const requestedFlowState = cleanString(
    req.body?.flowState || req.body?.flow_state
  );
  const requestedPhysioPolicy = normalizePhysioPolicy(
    req.body?.physioPolicy || req.body?.physio_policy
  );
  const requestedDiscussionProfile = cleanString(
    req.body?.discussionProfile || req.body?.discussion_profile
  );
  const effectiveDiscussionProfile =
    requestedDiscussionProfile ||
    cleanString(requestedPhysioPolicy?.discussionProfile);
  const effectiveSystem = buildMobileChatSystem(
    req.body?.system,
    requestedFlowState,
    requestedPhysioPolicy
  );
  let appliedDiscussionProfile = effectiveDiscussionProfile || "cluster";

  let result;
  const subscriptionProfile = normalizeSubscriptionDiscussionProfile(effectiveDiscussionProfile);
  const cheapProviderProfile = normalizeCheapDiscussionProfile(effectiveDiscussionProfile);
  if (subscriptionProfile) {
    appliedDiscussionProfile = subscriptionProfile;
    result = await proxySubscriptionBridgeCompletion({
      prompt,
      system: effectiveSystem,
      provider: subscriptionProfile,
      projectSlug: cleanString(req.body?.projectSlug || req.body?.project_slug),
      projectFamily: cleanString(req.body?.projectFamily || req.body?.project_family),
      publicationScope: cleanString(req.body?.publicationScope || req.body?.publication_scope),
      readCatalog: deps.readCatalog
    });
  } else if (cheapProviderProfile) {
    appliedDiscussionProfile = cheapProviderProfile;
    result = await proxyCheapProviderCompletion({
      prompt,
      system: effectiveSystem,
      provider: cheapProviderProfile
    });
  } else if (
    effectiveDiscussionProfile &&
    !["cluster", "cluster-default", "default"].includes(
      effectiveDiscussionProfile.toLowerCase()
    )
  ) {
    const catalog = await deps.readCatalog();
    const profile = findDiscussionLabProfile(catalog, effectiveDiscussionProfile);
    if (!profile) {
      if (["qwen3b", "yi6b"].includes(effectiveDiscussionProfile.toLowerCase())) {
        appliedDiscussionProfile = "cluster";
        result = await proxyBeagleCompletion({
          prompt,
          system: effectiveSystem,
          requires_math: requiresMath,
          requires_high_quality: requiresHighQuality,
          offline_required: offlineRequired
        });
      } else {
        throw contractFailure(
          ErrorCode.NOT_FOUND,
          `unknown discussion profile: ${effectiveDiscussionProfile}`
        );
      }
    } else {
      const profileStatus = cleanString(profile?.status || "").toLowerCase();
      if (profileStatus !== "available") {
        throw contractFailure(
          ErrorCode.CONFLICT,
          `discussion profile ${cleanString(profile?.id || requestedDiscussionProfile)} is ${profileStatus || "unavailable"}`
        );
      }
      appliedDiscussionProfile = cleanString(profile?.id) || effectiveDiscussionProfile;
      result = await proxyDiscussionLabCompletion({
        prompt,
        system: effectiveSystem,
        profile
      });
    }
  } else {
    appliedDiscussionProfile = "cluster";
    result = await proxyBeagleCompletion({
      prompt,
      system: effectiveSystem,
      requires_math: requiresMath,
      requires_high_quality: requiresHighQuality,
      offline_required: offlineRequired
    });
  }

  if (result.status < 200 || result.status >= 300) {
    const errorMessage =
      cleanString(result.payload?.error) ||
      cleanString(result.payload?.message) ||
      "chat completion unavailable";
    throw contractFailure(mapStatusCodeToErrorCode(result.status), errorMessage);
  }

  const responseText = cleanString(
    result.payload?.text || result.payload?.answer || result.payload?.response
  );
  if (!responseText) {
    throw contractFailure(ErrorCode.INTERNAL, "empty completion response");
  }

  const provider = cleanString(result.payload?.provider || result.payload?.model || "");
  const tier = cleanString(result.payload?.tier || result.payload?.provider_tier || "");
  const model = provider || tier || "unknown";
  const generatedAt = new Date().toISOString();
  const totalTokens = Number(result.payload?.usage?.total_tokens);

  return {
    response: responseText,
    model,
    provider: provider || model,
    tier,
    source: normalizeSource(result.payload?.source) || "cluster",
    agentKind: cleanString(result.payload?.agentKind || result.payload?.agent_kind),
    sessionId: cleanString(result.payload?.sessionId || result.payload?.session_id),
    podName: cleanString(result.payload?.podName || result.payload?.pod_name),
    conversationMode:
      cleanString(result.payload?.conversationMode || result.payload?.conversation_mode)
      || cleanString(requestedPhysioPolicy?.modeLabel),
    appliedDiscussionProfile:
      cleanString(result.payload?.appliedDiscussionProfile || result.payload?.applied_discussion_profile)
      || appliedDiscussionProfile,
    flowState:
      cleanString(result.payload?.flowState || result.payload?.flow_state)
      || requestedFlowState.toUpperCase(),
    tokensUsed: Number.isFinite(totalTokens) && totalTokens > 0
      ? totalTokens
      : estimateTokenCount(prompt, effectiveSystem, responseText),
    generatedAt,
    truthMode: cleanString(result.payload?.truthMode) || "observed",
    beagleUrl: cleanString(result.payload?.beagle_url || result.beagleUrl || "")
  };
}

async function annotateClientSession(req, deps, projectSlug, currentAction) {
  const clientSessionId = cleanString(req.body?.clientSessionId);
  if (!clientSessionId) {
    return null;
  }

  return deps.touchSession(
    projectSlug,
    clientSessionId,
    deps.deriveViewer(req, req.body?.alias),
    {
      currentAction,
      lastMutationAt: new Date().toISOString(),
      lastMutationLabel: currentAction
    }
  );
}

export function registerMobileRoutes(app, deps) {
  app.get(
    "/api/mobile/v1/health",
    withEnvelope(async () => {
      const generatedAt = new Date().toISOString();
      return {
        data: {
          status: "ok",
          service: "project-cockpit-mobile",
          version: "v1",
          generatedAt
        },
        meta: buildMeta(generatedAt)
      };
    })
  );

  // Resolve to `fallback` if `p` rejects OR exceeds `ms` — never hang, never throw.
  // The mobile summary fan-out hits live per-project services; without this, ONE slow or
  // hung downstream (sessions / lane-result) made the whole endpoint time out. `catalog`
  // stays fast because it only reads a cached file; this gives `summary` the same
  // graceful-degradation contract (return partial data instead of hanging).
  const SUMMARY_SUBCALL_TIMEOUT_MS = Number(
    process.env.PROJECT_COCKPIT_MOBILE_SUMMARY_TIMEOUT_MS || 3000
  );
  const withTimeout = (p, ms, fallback) =>
    new Promise((resolve) => {
      let done = false;
      const t = setTimeout(() => {
        if (!done) {
          done = true;
          resolve(fallback);
        }
      }, ms);
      Promise.resolve(p).then(
        (v) => {
          if (!done) {
            done = true;
            clearTimeout(t);
            resolve(v);
          }
        },
        () => {
          if (!done) {
            done = true;
            clearTimeout(t);
            resolve(fallback);
          }
        }
      );
    });

  app.get(
    "/api/mobile/v1/summary",
    withEnvelope(async () => {
      try {
        let catalog = null;
        try {
          catalog = await deps.readCachedCatalogExecutiveState({ preferStale: true });
        } catch {
          catalog = null;
        }
        const projects = Array.isArray(catalog?.projects) ? catalog.projects : [];
        const perProject = await Promise.all(
          projects.map(async (entry) => {
            const slug = cleanString(entry?.projectSlug);
            if (!slug) {
              return null;
            }
            const resolvedProject = await withTimeout(
              deps.getProjectOrThrow(slug).catch(() => entry),
              SUMMARY_SUBCALL_TIMEOUT_MS,
              entry
            );
            const laneProject = {
              projectSlug: cleanString(
                resolvedProject?.projectSlug || resolvedProject?.slug || slug
              ),
              slug,
              workstreamId: cleanString(
                resolvedProject?.workstreamId ||
                resolvedProject?.workspace?.workstreamId ||
                resolvedProject?.workspaceState?.workstreamId ||
                entry?.workstreamId ||
                entry?.workspace?.workstreamId
              )
            };
            const [clientSessions, agentSessions, laneResult] = await Promise.all([
              withTimeout(deps.listProjectSessions(slug), SUMMARY_SUBCALL_TIMEOUT_MS, { active: [] }),
              withTimeout(listAgentSessions(slug).catch(() => []), SUMMARY_SUBCALL_TIMEOUT_MS, []),
              withTimeout(buildProjectLaneResultSummary(laneProject), SUMMARY_SUBCALL_TIMEOUT_MS, null)
            ]);
            const activeClientSessions = Array.isArray(clientSessions?.active)
              ? clientSessions.active.map(normalizeClientSession)
              : [];
            const activeAgentSessions = (Array.isArray(agentSessions) ? agentSessions : []).filter(
              (session) => Boolean(session?.name)
            );
            return {
              slug,
              activeClientSessions,
              activeAgentSessions,
              laneResult
            };
          })
        );
        const filtered = perProject.filter(Boolean);
        const generatedAt = cleanString(catalog?.generatedAt) || new Date().toISOString();
        return {
          data: {
            generatedAt,
            activeAgentsCount: filtered.reduce(
              (sum, entry) => sum + entry.activeAgentSessions.length,
              0
            ),
            activeSessionsCount: filtered.reduce(
              (sum, entry) => sum + entry.activeClientSessions.length,
              0
            ),
            clusterHealth: inferClusterHealth(catalog || {}),
            lastMemorySyncTime: latestIso(
              filtered.map((entry) =>
                entry.activeClientSessions.map((session) => session.lastMemorySyncAt)
              )
            ),
            laneResults: filtered
              .map((entry) => entry.laneResult)
              .filter(Boolean)
          },
          meta: buildMeta(generatedAt, catalog)
        };
      } catch (error) {
        rethrowAsContract(error, "summary unavailable");
      }
    })
  );

  app.get(
    "/api/mobile/v1/catalog",
    withEnvelope(async () => {
      try {
        let catalog = null;
        try {
          catalog = await deps.readCachedCatalogExecutiveState({ preferStale: true });
        } catch {
          catalog = null;
        }
        const generatedAt = cleanString(catalog?.generatedAt) || new Date().toISOString();
        return {
          data: {
            generatedAt,
            projectPosturePolicy: catalog?.projectPosturePolicy || null,
            projects: Array.isArray(catalog?.projects)
              ? catalog.projects.map(normalizeCatalogProject)
              : []
          },
          meta: buildMeta(generatedAt, catalog)
        };
      } catch (error) {
        rethrowAsContract(error, "catalog unavailable");
      }
    })
  );

  app.get(
    "/api/mobile/v1/projects/:slug/overview",
    withEnvelope(async (req) => {
      try {
        const project = await deps.getProjectOrThrow(req.params.slug);
        const depth = req.query.depth === "deep" ? "deep" : "fast";
        const [mission, lane, research, inference, viewer, goWorkNow] = await Promise.all([
          deps.buildMissionControlResponse(project, depth),
          deps.buildClusterLaneTruthResponse(project, depth),
          deps.buildResearchOperationsResponse(project, depth),
          deps.buildInferenceRuntimeResponse(project),
          deps.buildViewerRuntimeResponse(project),
          deps.buildGoWorkNowResponse(project, depth)
        ]);

        const generatedAt =
          cleanString(mission?.generatedAt) ||
          cleanString(goWorkNow?.generatedAt) ||
          new Date().toISOString();
        const goWorkNowPacket = goWorkNow?.goWorkNow || {};
        const operatingPosture = goWorkNow?.operatingPosture || null;
        const laneProject = {
          projectSlug: cleanString(project?.projectSlug || project?.slug || req.params.slug),
          slug: cleanString(project?.projectSlug || project?.slug || req.params.slug),
          workstreamId: cleanString(
            project?.workstreamId ||
            project?.workspace?.workstreamId ||
            goWorkNowPacket?.workspaceState?.workstreamId ||
            goWorkNowPacket?.workspace?.workstreamId
          )
        };
        const laneResult = await buildProjectLaneResultSummary(laneProject);

        return {
          data: {
            project: normalizeProject(project),
            depth,
            missionControl: mission?.missionControl || {},
            clusterLaneTruth: lane?.clusterLaneTruth || {},
            researchOperations: research?.researchOperations || {},
            inferenceRuntime: inference?.runtime || {},
            viewerRuntime: {
              renderer: viewer?.renderer || {},
              runtimeCapabilities: viewer?.runtimeCapabilities || null
            },
            operatingPosture,
            workspaceState: goWorkNowPacket?.workspaceState || null,
            latestObservedOperation: goWorkNowPacket?.latestObservedOperation || null,
            laneResult,
            actions: normalizeActionList(project, goWorkNowPacket, operatingPosture),
            generatedAt
          },
          meta: buildMeta(
            generatedAt,
            mission,
            lane,
            research,
            inference?.runtime,
            viewer?.renderer
          )
        };
      } catch (error) {
        rethrowAsContract(error, "project overview unavailable");
      }
    })
  );

  app.get(
    "/api/mobile/v1/projects/:slug/actions",
    withEnvelope(async (req) => {
      try {
        const project = await deps.getProjectOrThrow(req.params.slug);
        const depth = req.query.depth === "deep" ? "deep" : "fast";
        const goWorkNow = await deps.buildGoWorkNowResponse(project, depth);
        const generatedAt = cleanString(goWorkNow?.generatedAt) || new Date().toISOString();
        const packet = goWorkNow?.goWorkNow || {};
        const operatingPosture = goWorkNow?.operatingPosture || null;

        return {
          data: {
            project: normalizeProject(project),
            operatingPosture,
            workspaceState: packet.workspaceState || null,
            latestObservedOperation: packet.latestObservedOperation || null,
            actions: normalizeActionList(project, packet, operatingPosture),
            generatedAt
          },
          meta: buildMeta(generatedAt, goWorkNow)
        };
      } catch (error) {
        rethrowAsContract(error, "project actions unavailable");
      }
    })
  );

  app.post(
    "/api/mobile/v1/projects/:slug/actions/:actionId",
    acceptBodyIdempotencyKey,
    idempotent(),
    withEnvelope(async (req) => {
      try {
        requireConfirmed(req, "mobile action");
        const project = await deps.getProjectOrThrow(req.params.slug);
        const actionId = cleanString(req.params.actionId);
        const { label, output } = await deps.runGoWorkNowAction(project, actionId);
        await annotateClientSession(
          req,
          deps,
          project.projectSlug,
          `mobile-action:${label || actionId}`
        );

        const refreshed = await deps.buildGoWorkNowResponse(project, "fast");
        const generatedAt = cleanString(refreshed?.generatedAt) || new Date().toISOString();
        const packet = refreshed?.goWorkNow || {};
        const operatingPosture = refreshed?.operatingPosture || null;

        return {
          data: {
            project: normalizeProject(project),
            action: {
              id: actionId,
              label: label || actionId,
              status: "completed",
              output: cleanString(output)
            },
            operatingPosture,
            workspaceState: packet.workspaceState || null,
            actions: normalizeActionList(project, packet, operatingPosture),
            generatedAt
          },
          meta: buildMeta(generatedAt, refreshed)
        };
      } catch (error) {
        rethrowAsContract(error, "mobile action failed");
      }
    })
  );

  app.post(
    "/api/mobile/v1/projects/:slug/ideas",
    acceptBodyIdempotencyKey,
    idempotent(),
    withEnvelope(async (req) => {
      try {
        const project = await deps.getProjectOrThrow(req.params.slug);
        const projectFamily = deriveProjectFamily(
          project.projectSlug,
          req.body?.project_family || req.body?.projectFamily
        );
        const publicationScope = derivePublicationScope(
          projectFamily,
          req.body?.publication_scope || req.body?.publicationScope
        );
        const entry = buildScratchpadEntry(project.projectSlug, {
          text: req.body?.text,
          author: req.body?.author || req.body?.source || "ios",
          tags: Array.isArray(req.body?.tags)
            ? [...req.body.tags, "mobile-idea"].slice(0, 8)
            : ["mobile-idea"],
          project_family: projectFamily,
          publication_scope: publicationScope,
          promotion_state: "synced",
          consciousness_state: req.body?.consciousness_state || req.body?.consciousnessState
        });
        appendScratchpadEntry(project.projectSlug, entry);
        await annotateClientSession(req, deps, project.projectSlug, "mobile-idea:saved");
        const syncState = "synced";
        const generatedAt = new Date().toISOString();
        if (cleanString(req.body?.clientSessionId)) {
          await deps.touchSession(
            project.projectSlug,
            cleanString(req.body.clientSessionId),
            deps.deriveViewer(req, req.body?.alias),
            {
              currentAction: "mobile-idea:saved",
              lastMutationAt: generatedAt,
              lastMutationLabel: `idea:${entry.entry_id}`,
              lastMemorySyncAt: generatedAt,
              lastMemorySyncState: syncState,
              projectFamily,
              publicationScope,
              promotionState: syncState,
              workspaceTarget: `${project.projectSlug}-${projectFamily}`,
              notes: entry.text
            }
          );
        }
        return {
          data: {
            project: normalizeProject(project),
            idea: entry,
            projectFamily,
            publicationScope,
            syncState,
            generatedAt
          },
          meta: buildMeta(generatedAt)
        };
      } catch (error) {
        rethrowAsContract(error, "save idea failed");
      }
    })
  );

  app.post(
    "/api/mobile/v1/projects/:slug/delegations",
    acceptBodyIdempotencyKey,
    idempotent(),
    withEnvelope(async (req) => {
      try {
        const project = await deps.getProjectOrThrow(req.params.slug);
        const kind = cleanString(req.body?.agentKind || req.body?.kind) || "claude-code";
        const projectFamily = deriveProjectFamily(
          project.projectSlug,
          req.body?.project_family || req.body?.projectFamily
        );
        const publicationScope = derivePublicationScope(
          projectFamily,
          req.body?.publication_scope || req.body?.publicationScope
        );
        const session = await startAgentSession(project.projectSlug, kind);
        const normalized = normalizeSession(session);
        const generatedAt = new Date().toISOString();
        if (cleanString(req.body?.clientSessionId)) {
          await deps.touchSession(
            project.projectSlug,
            cleanString(req.body.clientSessionId),
            deps.deriveViewer(req, req.body?.alias),
            {
              currentAction: `mobile-delegation:${kind}`,
              lastMutationAt: generatedAt,
              lastMutationLabel: `delegated:${kind}`,
              lastDelegationAt: generatedAt,
              lastDelegationState: "delegated",
              lastDelegationAgentKind: kind,
              lastDelegationSessionId: normalized.name,
              lastDelegationPodName: normalized.podName,
              projectFamily,
              publicationScope,
              promotionState: "delegated",
              workspaceTarget: `${project.projectSlug}-${projectFamily}`
            }
          );
        }
        return {
          data: {
            project: normalizeProject(project),
            projectFamily,
            publicationScope,
            agentKind: kind,
            sessionId: normalized.name,
            podName: normalized.podName,
            resultingState: "delegated",
            session: normalized,
            generatedAt
          },
          meta: buildMeta(generatedAt)
        };
      } catch (error) {
        rethrowAsContract(error, "delegate failed");
      }
    })
  );

  app.post(
    "/api/mobile/v1/projects/:slug/heartbeat",
    withEnvelope(async (req) => {
      try {
        const project = await deps.getProjectOrThrow(req.params.slug);
        const clientSessionId = cleanString(req.body?.clientSessionId);
        if (!clientSessionId) {
          throw contractFailure(
            ErrorCode.BAD_REQUEST,
            "clientSessionId is required"
          );
        }

        const viewer = deps.deriveViewer(req, req.body?.alias);
        const projectFamily = deriveProjectFamily(
          project.projectSlug,
          req.body?.project_family || req.body?.projectFamily
        );
        const publicationScope = derivePublicationScope(
          projectFamily,
          req.body?.publication_scope || req.body?.publicationScope
        );
        const session = await deps.touchSession(project.projectSlug, clientSessionId, viewer, {
          route:
            cleanString(req.body?.route) ||
            `/api/mobile/v1/projects/${project.projectSlug}/overview`,
          currentAction:
            cleanString(req.body?.currentAction) || "using-mobile-cockpit",
          projectFamily,
          publicationScope,
          workspaceTarget: `${project.projectSlug}-${projectFamily}`
        });
        const sessions = await deps.listProjectSessions(project.projectSlug);
        const generatedAt = new Date().toISOString();

        return {
          data: {
            project: normalizeProject(project),
            viewer,
            session: normalizeClientSession(session),
            sessions: {
              active: (Array.isArray(sessions?.active) ? sessions.active : []).map(
                normalizeClientSession
              ),
              recent: (Array.isArray(sessions?.recent) ? sessions.recent : []).map(
                normalizeClientSession
              )
            },
            generatedAt
          },
          meta: buildMeta(generatedAt)
        };
      } catch (error) {
        rethrowAsContract(error, "mobile heartbeat failed");
      }
    })
  );

  app.get(
    "/api/mobile/v1/projects/:slug/agent-sessions",
    withEnvelope(async (req) => {
      try {
        await deps.getProjectOrThrow(req.params.slug);
        const sessions = await listAgentSessions(req.params.slug);
        const generatedAt = new Date().toISOString();
        return {
          data: {
            projectSlug: req.params.slug,
            sessions: sessions.map(normalizeSession),
            generatedAt
          },
          meta: buildMeta(generatedAt)
        };
      } catch (error) {
        rethrowAsContract(error, "agent session list unavailable");
      }
    })
  );

  app.get(
    "/api/mobile/v1/projects/:slug/agent-sessions/:kind",
    withEnvelope(async (req) => {
      try {
        await deps.getProjectOrThrow(req.params.slug);
        const session = await getAgentSession(req.params.slug, req.params.kind);
        const generatedAt = new Date().toISOString();
        return {
          data: {
            projectSlug: req.params.slug,
            session: normalizeSession(session),
            generatedAt
          },
          meta: buildMeta(generatedAt)
        };
      } catch (error) {
        rethrowAsContract(error, "agent session unavailable");
      }
    })
  );

  app.post(
    "/api/mobile/v1/projects/:slug/agent-sessions",
    acceptBodyIdempotencyKey,
    idempotent(),
    withEnvelope(async (req) => {
      try {
        await deps.getProjectOrThrow(req.params.slug);
        const kind = cleanString(req.body?.kind) || "claude-code";
        const session = await startAgentSession(req.params.slug, kind);
        await annotateClientSession(
          req,
          deps,
          req.params.slug,
          `mobile-agent-session:start:${kind}`
        );
        const generatedAt = new Date().toISOString();
        return {
          data: {
            projectSlug: req.params.slug,
            action: "start",
            session: normalizeSession(session),
            generatedAt
          },
          meta: buildMeta(generatedAt)
        };
      } catch (error) {
        rethrowAsContract(error, "agent session start failed");
      }
    })
  );

  app.post(
    "/api/mobile/v1/projects/:slug/agent-sessions/:kind/pause",
    acceptBodyIdempotencyKey,
    idempotent(),
    withEnvelope(async (req) => {
      try {
        await deps.getProjectOrThrow(req.params.slug);
        const session = await pauseAgentSession(req.params.slug, req.params.kind);
        await annotateClientSession(
          req,
          deps,
          req.params.slug,
          `mobile-agent-session:pause:${req.params.kind}`
        );
        const generatedAt = new Date().toISOString();
        return {
          data: {
            projectSlug: req.params.slug,
            action: "pause",
            session: normalizeSession(session),
            generatedAt
          },
          meta: buildMeta(generatedAt)
        };
      } catch (error) {
        rethrowAsContract(error, "agent session pause failed");
      }
    })
  );

  app.post(
    "/api/mobile/v1/projects/:slug/agent-sessions/:kind/resume",
    acceptBodyIdempotencyKey,
    idempotent(),
    withEnvelope(async (req) => {
      try {
        await deps.getProjectOrThrow(req.params.slug);
        const session = await resumeAgentSession(req.params.slug, req.params.kind);
        await annotateClientSession(
          req,
          deps,
          req.params.slug,
          `mobile-agent-session:resume:${req.params.kind}`
        );
        const generatedAt = new Date().toISOString();
        return {
          data: {
            projectSlug: req.params.slug,
            action: "resume",
            session: normalizeSession(session),
            generatedAt
          },
          meta: buildMeta(generatedAt)
        };
      } catch (error) {
        rethrowAsContract(error, "agent session resume failed");
      }
    })
  );

  app.delete(
    "/api/mobile/v1/projects/:slug/agent-sessions/:kind",
    acceptBodyIdempotencyKey,
    idempotent(),
    withEnvelope(async (req) => {
      try {
        requireConfirmed(req, "agent session delete");
        await deps.getProjectOrThrow(req.params.slug);
        const session = await stopAgentSession(req.params.slug, req.params.kind, {
          deletePVC: req.body?.deletePersistentState === true
        });
        await annotateClientSession(
          req,
          deps,
          req.params.slug,
          `mobile-agent-session:stop:${req.params.kind}`
        );
        const generatedAt = new Date().toISOString();
        return {
          data: {
            projectSlug: req.params.slug,
            action: "stop",
            session: normalizeSession(session),
            generatedAt
          },
          meta: buildMeta(generatedAt)
        };
      } catch (error) {
        rethrowAsContract(error, "agent session stop failed");
      }
    })
  );

  app.post(
    "/api/mobile/v1/chat",
    withEnvelope(async (req) => {
      try {
        const completion = await completeChatRequest(req, deps);
        return {
          data: {
            response: completion.response,
            model: completion.model,
            source: completion.source,
            agentKind: completion.agentKind || null,
            sessionId: completion.sessionId || null,
            podName: completion.podName || null,
            conversation_mode: completion.conversationMode || null,
            applied_discussion_profile: completion.appliedDiscussionProfile || null,
            flow_state: completion.flowState || null,
            tokens_used: completion.tokensUsed
          },
          meta: buildMeta(completion.generatedAt, {
            truthMode: completion.truthMode
          })
        };
      } catch (error) {
        rethrowAsContract(error, "mobile chat failed");
      }
    })
  );

  app.post("/api/llm/complete", async (req, res) => {
    try {
      const completion = await completeChatRequest(req, deps);
      res.json({
        text: completion.response,
        response: completion.response,
        provider: completion.provider,
        tier: completion.tier,
        source: completion.source,
        agentKind: completion.agentKind || null,
        sessionId: completion.sessionId || null,
        podName: completion.podName || null,
        conversation_mode: completion.conversationMode || null,
        applied_discussion_profile: completion.appliedDiscussionProfile || null,
        flow_state: completion.flowState || null,
        tokens_used: completion.tokensUsed,
        truthMode: completion.truthMode
      });
    } catch (error) {
      const mapped = mapStatusCodeToErrorCode(error?.statusCode);
      const code = error?.code && ErrorCode[error.code] ? error.code : mapped.code;
      const status = ErrorCode[code]?.http || 500;
      res.status(status).json({
        error: error?.message || "chat completion failed",
        truthMode: "stale"
      });
    }
  });
}

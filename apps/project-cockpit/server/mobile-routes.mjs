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
import { proxyBeagleCompletion } from "./auth-bridge.mjs";
import { appendScratchpadEntry } from "./scratchpad-routes.mjs";

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

function buildMeta(generatedAt, ...values) {
  return {
    generatedAt: cleanString(generatedAt) || new Date().toISOString(),
    truthMode: deriveTruthMode(...values)
  };
}

function normalizeMobileSource(value, fallback = "cluster") {
  const normalized = cleanString(value).toLowerCase();
  if (["device", "cluster", "agent", "hybrid"].includes(normalized)) {
    return normalized;
  }
  return fallback;
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
    }))
  };
}

function sessionProvenance(session = {}, fallbackKind = "") {
  const normalized = normalizeSession(session);
  return {
    agentKind: cleanString(normalized.kind || fallbackKind),
    sessionId: cleanString(normalized.name || ""),
    podName: cleanString(normalized.podName || "")
  };
}

async function ensureAgentSession(slug, kind) {
  const current = await getAgentSession(slug, kind);
  if (current?.status === "running" || current?.status === "pending") {
    return {
      action: "reuse",
      session: current
    };
  }
  if (current?.status === "paused") {
    return {
      action: "resume",
      session: await resumeAgentSession(slug, kind)
    };
  }
  return {
    action: "start",
    session: await startAgentSession(slug, kind)
  };
}

function extractLatestMemorySyncAt(sessionGroups = []) {
  return sessionGroups
    .flatMap((group) => {
      const active = Array.isArray(group?.active) ? group.active : [];
      const recent = Array.isArray(group?.recent) ? group.recent : [];
      return [...active, ...recent];
    })
    .map((session) => cleanString(session?.lastMemorySyncAt || ""))
    .filter(Boolean)
    .sort((left, right) => new Date(right).getTime() - new Date(left).getTime())[0] || "";
}

async function completeChatRequest(req) {
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
  const modelProvider = cleanString(req.body?.model_provider || req.body?.modelProvider || req.body?.provider);
  const requestedModel = cleanString(req.body?.model);

  const result = await proxyBeagleCompletion({
    prompt,
    system,
    requires_math: requiresMath,
    requires_high_quality: requiresHighQuality,
    offline_required: offlineRequired,
    model_provider: modelProvider,
    model: requestedModel
  });

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
    source: normalizeMobileSource(result.payload?.source, "cluster"),
    provider: provider || model,
    tier,
    tokensUsed: Number.isFinite(totalTokens) && totalTokens > 0
      ? totalTokens
      : estimateTokenCount(prompt, system, responseText),
    generatedAt,
    truthMode: cleanString(result.payload?.truthMode) || "observed",
    requestId: cleanString(
      result.payload?.request_id ||
      result.payload?.requestId ||
      result.payload?.raw?.id ||
      ""
    ),
    agentKind: cleanString(result.payload?.agentKind || result.payload?.agent_kind || ""),
    sessionId: cleanString(result.payload?.sessionId || result.payload?.session_id || ""),
    podName: cleanString(result.payload?.podName || result.payload?.pod_name || ""),
    beagleUrl: cleanString(result.payload?.beagle_url || result.beagleUrl || ""),
    modelRoute: result.payload?.model_route || null,
    policy: result.payload?.policy || null
  };
}

async function annotateClientSession(req, deps, projectSlug, currentAction, extraPatch = {}) {
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
      lastMutationLabel: currentAction,
      ...extraPatch
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
        meta: {
          ...buildMeta(generatedAt),
          source: "cluster"
        }
      };
    })
  );

  app.get(
    "/api/mobile/v1/summary",
    withEnvelope(async () => {
      try {
        const catalog = await deps.readCachedCatalogExecutiveState({ preferStale: true });
        const projectSlugs = Array.from(
          new Set(
            (Array.isArray(catalog?.projects) ? catalog.projects : [])
              .map((project) => cleanString(project?.projectSlug || project?.slug || ""))
              .filter(Boolean)
          )
        );
        const primaryProjectSlug =
          projectSlugs.includes("sounio") ? "sounio" : projectSlugs[0] || "sounio";
        const primaryProject = await deps.getProjectOrThrow(primaryProjectSlug);

        const [agentGroups, sessionGroups, rememberedMemoryGroups, clusterLane] = await Promise.all([
          Promise.all(
            projectSlugs.map((slug) =>
              listAgentSessions(slug).catch(() => [])
            )
          ),
          Promise.all(
            projectSlugs.map((slug) =>
              deps.listProjectSessions(slug).catch(() => ({ active: [], recent: [] }))
            )
          ),
          Promise.all(
            projectSlugs.map((slug) =>
              deps.readRememberedWorkspaceMemory(slug).catch(() => null)
            )
          ),
          deps.buildClusterLaneTruthResponse(primaryProject, "fast").catch(() => ({
            clusterLaneTruth: {}
          }))
        ]);

        const activeAgentsCount = agentGroups
          .flat()
          .filter((session) => cleanString(session?.status || "") === "running")
          .length;
        const activeSessionsCount = sessionGroups.reduce(
          (sum, group) => sum + (Array.isArray(group?.active) ? group.active.length : 0),
          0
        );
        const rememberedTimes = rememberedMemoryGroups
          .map((memory) => cleanString(memory?.rememberedAt || ""))
          .filter(Boolean);
        const latestSessionSyncAt = extractLatestMemorySyncAt(sessionGroups);
        const lastMemorySyncTime = [latestSessionSyncAt, ...rememberedTimes]
          .filter(Boolean)
          .sort((left, right) => new Date(right).getTime() - new Date(left).getTime())[0] || "";
        const clusterHealth = {
          status: cleanString(clusterLane?.clusterLaneTruth?.status || "unobserved"),
          surface: cleanString(clusterLane?.clusterLaneTruth?.surface || "gpuorangefs"),
          healthyNodes: Number(clusterLane?.clusterLaneTruth?.healthyNodes || 0),
          admittedNodes: Number(clusterLane?.clusterLaneTruth?.admittedNodes || 0)
        };
        const generatedAt = new Date().toISOString();

        return {
          data: {
            source: "hybrid",
            activeAgentsCount,
            activeSessionsCount,
            clusterHealth,
            lastMemorySyncTime,
            generatedAt
          },
          meta: {
            ...buildMeta(generatedAt, catalog, clusterLane),
            source: "hybrid"
          }
        };
      } catch (error) {
        rethrowAsContract(error, "mobile summary unavailable");
      }
    })
  );

  app.get(
    "/api/mobile/v1/catalog",
    withEnvelope(async () => {
      try {
        const catalog = await deps.readCachedCatalogExecutiveState({ preferStale: true });
        const generatedAt = cleanString(catalog?.generatedAt) || new Date().toISOString();
        return {
          data: {
            generatedAt,
            source: "cluster",
            projectPosturePolicy: catalog?.projectPosturePolicy || null,
            projects: Array.isArray(catalog?.projects)
              ? catalog.projects.map(normalizeCatalogProject)
              : []
          },
          meta: {
            ...buildMeta(generatedAt, catalog),
            source: "cluster"
          }
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

        return {
          data: {
            project: normalizeProject(project),
            source: "cluster",
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
            actions: normalizeActionList(project, goWorkNowPacket, operatingPosture),
            generatedAt
          },
          meta: {
            ...buildMeta(
              generatedAt,
              mission,
              lane,
              research,
              inference?.runtime,
              viewer?.renderer
            ),
            source: "cluster"
          }
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
            source: "cluster",
            operatingPosture,
            workspaceState: packet.workspaceState || null,
            latestObservedOperation: packet.latestObservedOperation || null,
            actions: normalizeActionList(project, packet, operatingPosture),
            generatedAt
          },
          meta: {
            ...buildMeta(generatedAt, goWorkNow),
            source: "cluster"
          }
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
            source: "cluster",
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
          meta: {
            ...buildMeta(generatedAt, refreshed),
            source: "cluster"
          }
        };
      } catch (error) {
        rethrowAsContract(error, "mobile action failed");
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
        const session = await deps.touchSession(project.projectSlug, clientSessionId, viewer, {
          route:
            cleanString(req.body?.route) ||
            `/api/mobile/v1/projects/${project.projectSlug}/overview`,
          currentAction:
            cleanString(req.body?.currentAction) || "using-mobile-cockpit"
        });
        const sessions = await deps.listProjectSessions(project.projectSlug);
        const generatedAt = new Date().toISOString();

        return {
          data: {
            project: normalizeProject(project),
            source: "hybrid",
            viewer,
            session,
            sessions,
            generatedAt
          },
          meta: {
            ...buildMeta(generatedAt),
            source: "hybrid"
          }
        };
      } catch (error) {
        rethrowAsContract(error, "mobile heartbeat failed");
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
        const entry = appendScratchpadEntry(project.projectSlug, {
          text: req.body?.text,
          author: req.body?.author || "mobile-user",
          tags: Array.isArray(req.body?.tags) ? req.body.tags : ["idea"]
        });
        await annotateClientSession(
          req,
          deps,
          project.projectSlug,
          "mobile-idea-save",
          {
            lastMemorySyncAt: entry.created_at,
            lastMemorySyncState: "synced"
          }
        );

        return {
          data: {
            project: normalizeProject(project),
            source: "cluster",
            syncState: "synced",
            idea: {
              entryId: entry.entry_id,
              text: entry.text,
              author: entry.author,
              tags: entry.tags,
              createdAt: entry.created_at
            }
          },
          meta: {
            ...buildMeta(entry.created_at),
            source: "cluster"
          }
        };
      } catch (error) {
        rethrowAsContract(error, "mobile idea save failed");
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
        const text = cleanString(req.body?.text || req.body?.prompt);
        if (!text) {
          throw contractFailure(ErrorCode.BAD_REQUEST, "text is required");
        }

        const requestedKind = cleanString(req.body?.agentKind || req.body?.kind || "claude-code");
        const ensured = await ensureAgentSession(project.projectSlug, requestedKind);
        const provenance = sessionProvenance(ensured.session, requestedKind);
        const entry = appendScratchpadEntry(project.projectSlug, {
          text,
          author: req.body?.author || "mobile-user",
          tags: [
            "delegated",
            provenance.agentKind || requestedKind,
            ...(Array.isArray(req.body?.tags) ? req.body.tags.slice(0, 6) : [])
          ]
        });

        await annotateClientSession(
          req,
          deps,
          project.projectSlug,
          `mobile-delegate:${provenance.agentKind || requestedKind}`,
          {
            lastMemorySyncAt: entry.created_at,
            lastMemorySyncState: "delegated",
            lastDelegationAt: entry.created_at,
            lastDelegationKind: provenance.agentKind || requestedKind,
            lastDelegationSessionId: provenance.sessionId,
            lastDelegationPodName: provenance.podName
          }
        );

        return {
          data: {
            project: normalizeProject(project),
            source: "hybrid",
            resultingState: "delegated",
            delegation: {
              action: ensured.action,
              agentKind: provenance.agentKind || requestedKind,
              sessionId: provenance.sessionId,
              podName: provenance.podName,
              status: cleanString(ensured.session?.status || "pending")
            },
            task: {
              entryId: entry.entry_id,
              text: entry.text,
              createdAt: entry.created_at
            }
          },
          meta: {
            ...buildMeta(entry.created_at),
            source: "hybrid"
          }
        };
      } catch (error) {
        rethrowAsContract(error, "mobile delegation failed");
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
            source: "cluster",
            sessions: sessions.map(normalizeSession),
            generatedAt
          },
          meta: {
            ...buildMeta(generatedAt),
            source: "cluster"
          }
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
            source: "cluster",
            session: normalizeSession(session),
            generatedAt
          },
          meta: {
            ...buildMeta(generatedAt),
            source: "cluster"
          }
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
            source: "cluster",
            session: normalizeSession(session),
            generatedAt
          },
          meta: {
            ...buildMeta(generatedAt),
            source: "cluster"
          }
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
            source: "cluster",
            session: normalizeSession(session),
            generatedAt
          },
          meta: {
            ...buildMeta(generatedAt),
            source: "cluster"
          }
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
            source: "cluster",
            session: normalizeSession(session),
            generatedAt
          },
          meta: {
            ...buildMeta(generatedAt),
            source: "cluster"
          }
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
            source: "cluster",
            session: normalizeSession(session),
            generatedAt
          },
          meta: {
            ...buildMeta(generatedAt),
            source: "cluster"
          }
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
        const completion = await completeChatRequest(req);
        return {
          data: {
            response: completion.response,
            model: completion.model,
            source: completion.source,
            agentKind: completion.agentKind || undefined,
            sessionId: completion.sessionId || undefined,
            podName: completion.podName || undefined,
            tokens_used: completion.tokensUsed
          },
          meta: {
            ...buildMeta(completion.generatedAt, {
              truthMode: completion.truthMode
            }),
            source: completion.source,
            upstream_request_id: completion.requestId || undefined
          }
        };
      } catch (error) {
        rethrowAsContract(error, "mobile chat failed");
      }
    })
  );

  app.post("/api/llm/complete", async (req, res) => {
    try {
      const completion = await completeChatRequest(req);
      res.json({
        text: completion.response,
        response: completion.response,
        source: completion.source,
        agentKind: completion.agentKind || undefined,
        sessionId: completion.sessionId || undefined,
        podName: completion.podName || undefined,
        provider: completion.provider,
        tier: completion.tier,
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

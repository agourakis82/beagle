# Cluster-driven Live Activities

Implemented end-to-end across `beagle-tronco/apps/project-cockpit/server` (Mobile API v1 + APNs HTTP/2 worker) and `BeagleSuite` (`BeagleCore` + `BeagleCockpit`). Foreground updates remain active automatically until the cluster acknowledges `remoteDeliveryActive == true` (when APNs `.p8` credentials are provisioned in the pod environment).

## Registration & Revocation Routes (`project-cockpit/server`)

All routes sit behind `authMiddleware` (`x-cockpit-token`, Bearer token, or trusted Tailscale identity) and return the standard `MobileEnvelope`:

- `GET /api/mobile/v1/live-activities/status` — returns `{ apnsConfigured, activeRegistrationsCount }` for the authenticated principal.
- `POST /api/mobile/v1/live-activities/register` — idempotent upsert scoped to `(principalId, activityId)` associating:
  - `activityId` and `installationId`;
  - `kind` (`agent` or `research`);
  - `canonicalId`, optional `agentKind`, and `projectSlug` (validated via `deps.getProjectOrThrow(projectSlug)` or `science` for global research runs);
  - `bundleId` (allowlisted via `PROJECT_COCKPIT_LIVE_ACTIVITY_BUNDLES`, default `dev.sounio.cockpit`) and `apnsEnvironment` (`development` | `production`);
  - monotonic `tokenRevision` and bounded `expiresAt` (`ttlSeconds`, max 12h).
- `POST /api/mobile/v1/live-activities/revoke` — marks the registration revoked/terminal and wipes the stored token immediately.
- `GET /api/mobile/v1/runs/:runId` — authenticated canonical research run lookup returning `status: "found" | "deleted" | "not_found"` (with live K8s job fallback when the reconciler has not yet ticked).

Raw APNs push tokens are never echoed in responses, never written to application logs, never stored in `UserDefaults`, and never captured into memory. Durable server state is persisted atomically in `$BEAGLE_DATA_DIR/live-activities/state.json` (`0600` permissions on the `/var/lib/cockpit` PVC).

## ActivityKit Client Lifecycle (`BeagleCore` + `BeagleCockpit`)

- `LiveActivityManager` requests `pushType: .token` exclusively for `agent` (`AgentSessionAttributes`) and `research` (`ResearchRunAttributes`) activities, falling back cleanly to `pushType: nil` on Simulator or unprovisioned builds.
- `observeClusterActivity` reads initial `activity.pushToken`, streams `activity.pushTokenUpdates`, and streams `activity.activityStateUpdates` to cancel observation tasks and call `revoke` upon `.ended` or `.dismissed`.
- `restoreClusterActivitiesAfterLaunch()` re-binds surviving `Activity<AgentSessionAttributes>.activities` and `Activity<ResearchRunAttributes>.activities` on launch and reconciles any activities dismissed while terminated.
- `NetworkMonitor` emits `.beagleNetworkDidReconnect`, triggering `LiveActivityClusterCoordinator.resubmitAllActive()` idempotently.
- `LiveActivityClusterCoordinator.shouldWriteLocally(activityId:)` yields foreground local `Activity.update(...)` writes once `ack.remoteDeliveryActive == true`, avoiding competing writers while preserving local updates whenever offline or when `apnsConfigured == false`.

## APNs Delivery & Event Sources

`LiveActivityService` (`server/live-activity-apns.mjs`) signs ES256 `.p8` provider tokens (`node:crypto`, cached 50m) and delivers HTTP/2 requests (`node:http2`) with `apns-push-type: liveactivity` and `apns-topic: <bundleId>.push-type.liveactivity`:

- Driven automatically by `server/job-reconciler.mjs` (K8s job progress + terminal `Succeeded`/`Failed`) and `server/agent-routes.mjs` (`startAgentSession`, `pauseAgentSession`, `resumeAgentSession`, `stopAgentSession`).
- Strictly monotonic `aps.timestamp`, SHA-256 content-state deduplication, out-of-order `sourceTimestampMs` rejection, and absorbing terminal `"end"` state (`dismissal-date`).
- Default remote agent payloads leave `lastOutputSnippet` empty (`""`); research payloads publish `{ stepCurrent, stepTotal, etaSeconds }`.
- HTTP `410 Unregistered` and `400 BadDeviceToken` / `DeviceTokenNotForTopic` prune the registration immediately.

### Cluster APNs Environment Variables (`project-cockpit` Deployment)

Configure via Kubernetes Secret mounted into `deployment/project-cockpit`:

- `APNS_TEAM_ID` (default `S9DPGW22A8`)
- `APNS_KEY_ID` (10-char Apple Push Key ID)
- `APNS_AUTH_KEY_P8` or `APNS_AUTH_KEY_PATH` (PEM `.p8` private key)
- `PROJECT_COCKPIT_LIVE_ACTIVITY_BUNDLES` (comma-separated bundle allowlist, default `dev.sounio.cockpit`)

## Spotlight Research Entities

`ResearchRunSearchEntity` and `ResearchRunSearchQuery` (`MemorySearchEntity.swift`) use `CockpitClient.shared.lookupCanonicalResearchRun(runId:)` (`GET /api/mobile/v1/runs/:runId`), deleting stale Spotlight items on `.deleted` / `.notFound` while throwing `LookupError.unavailable` during connectivity outages so valid entities are never wiped offline.

## Verification

- Backend unit suite: `npm --prefix apps/project-cockpit test` (`live-activity-apns.test.mjs` covers ES256 JWT verification, allowlists, token rotation, deduplication, out-of-order rejection, absorbing `"end"`, HTTP `410` pruning, disk reload durability, and canonical run lookup).
- iOS unit suite & build: `DirectBrainTransportTests` covers `LiveActivityClusterCoordinator` registration, token rotation, writer handoff, reconnect resubmission, revocation, and push token redaction; verified with `BuildProject(buildForTesting: true)`.

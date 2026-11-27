//
//  LiveActivityClusterBridge.swift
//  BeagleCore
//
//  Contract models, CockpitClient routes, and MainActor coordinator for
//  cluster-driven ActivityKit Live Activities (`agent` and `research`).
//
//  Security & Epistemic Invariants:
//    - Raw APNs push tokens NEVER appear in String(describing:), debug logs,
//      UserDefaults associations, analytics, or memory capture.
//    - Token revisions are monotonic per activityId.
//    - Local foreground updates remain active until the cluster acknowledges
//      `remoteDeliveryActive == true` (avoiding competing writers once active,
//      while preserving local fallback when offline or before APNs credentials
//      are provisioned on the cluster).
//

import Foundation

public enum LiveActivityClusterKind: String, Codable, Sendable {
    case agent
    case research
}

public struct LiveActivityRegistrationPayload: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public let installationId: String
    public let activityId: String
    public let kind: LiveActivityClusterKind
    public let canonicalId: String
    public let agentKind: String?
    public let projectSlug: String
    public let bundleId: String
    public let apnsEnvironment: String
    /// Raw lowercase hex APNs ActivityKit push token. Never logged or persisted to disk.
    public let pushToken: String
    public let tokenRevision: Int
    public let ttlSeconds: Int

    public init(
        installationId: String,
        activityId: String,
        kind: LiveActivityClusterKind,
        canonicalId: String,
        agentKind: String? = nil,
        projectSlug: String,
        bundleId: String,
        apnsEnvironment: String,
        pushToken: String,
        tokenRevision: Int,
        ttlSeconds: Int = 28_800
    ) {
        self.installationId = installationId
        self.activityId = activityId
        self.kind = kind
        self.canonicalId = canonicalId
        self.agentKind = agentKind
        self.projectSlug = projectSlug
        self.bundleId = bundleId
        self.apnsEnvironment = apnsEnvironment
        self.pushToken = pushToken
        self.tokenRevision = tokenRevision
        self.ttlSeconds = ttlSeconds
    }

    public var description: String {
        "LiveActivityRegistrationPayload(activityId: \(activityId), kind: \(kind.rawValue), canonicalId: \(canonicalId), slug: \(projectSlug), rev: \(tokenRevision), pushToken: <redacted>)"
    }

    public var debugDescription: String {
        description
    }

    public static func encodeHexToken(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    public static var defaultApnsEnvironment: String {
        #if DEBUG
        return "development"
        #else
        return "production"
        #endif
    }
}

public struct LiveActivityRegistrationAck: Codable, Sendable, Equatable {
    public let registrationId: String
    public let activityId: String
    public let installationId: String
    public let kind: LiveActivityClusterKind
    public let canonicalId: String
    public let agentKind: String?
    public let projectSlug: String
    public let bundleId: String
    public let apnsEnvironment: String
    public let tokenRevision: Int
    public let registeredAt: String
    public let updatedAt: String
    public let expiresAt: String
    public let revoked: Bool
    public let terminal: Bool
    public let apnsConfigured: Bool
    public let remoteDeliveryActive: Bool

    public init(
        registrationId: String,
        activityId: String,
        installationId: String,
        kind: LiveActivityClusterKind,
        canonicalId: String,
        agentKind: String? = nil,
        projectSlug: String,
        bundleId: String,
        apnsEnvironment: String,
        tokenRevision: Int,
        registeredAt: String,
        updatedAt: String,
        expiresAt: String,
        revoked: Bool,
        terminal: Bool,
        apnsConfigured: Bool,
        remoteDeliveryActive: Bool
    ) {
        self.registrationId = registrationId
        self.activityId = activityId
        self.installationId = installationId
        self.kind = kind
        self.canonicalId = canonicalId
        self.agentKind = agentKind
        self.projectSlug = projectSlug
        self.bundleId = bundleId
        self.apnsEnvironment = apnsEnvironment
        self.tokenRevision = tokenRevision
        self.registeredAt = registeredAt
        self.updatedAt = updatedAt
        self.expiresAt = expiresAt
        self.revoked = revoked
        self.terminal = terminal
        self.apnsConfigured = apnsConfigured
        self.remoteDeliveryActive = remoteDeliveryActive
    }
}

public struct LiveActivityRevokeAck: Codable, Sendable, Equatable {
    public let activityId: String
    public let revoked: Bool
    public let alreadyAbsent: Bool?

    public init(activityId: String, revoked: Bool, alreadyAbsent: Bool? = nil) {
        self.activityId = activityId
        self.revoked = revoked
        self.alreadyAbsent = alreadyAbsent
    }
}

public struct LiveActivityClusterStatus: Codable, Sendable, Equatable {
    public let apnsConfigured: Bool
    public let activeRegistrationsCount: Int

    public init(apnsConfigured: Bool, activeRegistrationsCount: Int) {
        self.apnsConfigured = apnsConfigured
        self.activeRegistrationsCount = activeRegistrationsCount
    }
}

// MARK: - Canonical Research Run Lookup (Spotlight + Reconciler Truth)

public struct CanonicalResearchRunRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: String { runId }
    public let runId: String
    public let projectSlug: String
    public let kind: String
    public let campaignName: String
    public let status: String
    public let phase: String?
    public let stepCurrent: Int
    public let stepTotal: Int
    public let etaSeconds: Int
    public let startedAt: String?
    public let updatedAt: String?
    public let completedAt: String?
    public let error: String?
    public let deleted: Bool?
}

public struct CanonicalResearchRunEnvelope: Codable, Sendable, Equatable {
    public let status: String
    public let runId: String?
    public let run: CanonicalResearchRunRecord?
}

public enum CanonicalResearchRunLookupState: Sendable, Equatable {
    case found(CanonicalResearchRunRecord)
    case deleted(runId: String)
    case notFound(runId: String)
    case unavailable(reason: String)
}

// MARK: - CockpitClient Mobile v1 Endpoints

public extension CockpitClient {
    func liveActivitiesStatus() async -> Truthful<LiveActivityClusterStatus> {
        await fetchMobile(
            LiveActivityClusterStatus.self,
            path: "/api/mobile/v1/live-activities/status"
        )
    }

    func registerLiveActivity(_ payload: LiveActivityRegistrationPayload) async -> Truthful<LiveActivityRegistrationAck> {
        var body: [String: any Sendable] = [
            "idempotencyKey": "la-reg:\(payload.activityId):r\(payload.tokenRevision)",
            "installationId": payload.installationId,
            "activityId": payload.activityId,
            "kind": payload.kind.rawValue,
            "canonicalId": payload.canonicalId,
            "projectSlug": payload.projectSlug,
            "bundleId": payload.bundleId,
            "apnsEnvironment": payload.apnsEnvironment,
            "pushToken": payload.pushToken,
            "tokenRevision": payload.tokenRevision,
            "ttlSeconds": payload.ttlSeconds
        ]
        if let agentKind = payload.agentKind, !agentKind.isEmpty {
            body["agentKind"] = agentKind
        }
        return await postMobile(
            LiveActivityRegistrationAck.self,
            path: "/api/mobile/v1/live-activities/register",
            body: body
        )
    }

    func revokeLiveActivity(
        activityId: String,
        installationId: String,
        reason: String = "dismissed"
    ) async -> Truthful<LiveActivityRevokeAck> {
        let body: [String: any Sendable] = [
            "idempotencyKey": "la-rev:\(activityId):\(reason)",
            "activityId": activityId,
            "installationId": installationId,
            "reason": reason
        ]
        return await postMobile(
            LiveActivityRevokeAck.self,
            path: "/api/mobile/v1/live-activities/revoke",
            body: body
        )
    }

    func lookupCanonicalResearchRun(runId: String) async -> CanonicalResearchRunLookupState {
        let trimmed = runId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .notFound(runId: "") }
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? trimmed
        let result = await fetchMobile(
            CanonicalResearchRunEnvelope.self,
            path: "/api/mobile/v1/runs/\(encoded)"
        )
        if let envelope = result.value {
            switch envelope.status.lowercased() {
            case "found":
                if let run = envelope.run {
                    return .found(run)
                }
                return .notFound(runId: trimmed)
            case "deleted":
                return .deleted(runId: trimmed)
            default:
                return .notFound(runId: trimmed)
            }
        }
        let err = result.error ?? "cluster unavailable"
        if err.contains("HTTP 404") || err.contains("code=NOT_FOUND") {
            return .notFound(runId: trimmed)
        }
        return .unavailable(reason: err)
    }
}

// MARK: - Durable Non-Secret Activity Association

public struct PersistedLiveActivityAssociation: Codable, Sendable, Equatable {
    public let activityId: String
    public let kind: LiveActivityClusterKind
    public var canonicalId: String
    public var agentKind: String?
    public var projectSlug: String
    public var tokenRevision: Int
    public var remoteDeliveryActive: Bool
    public var registrationAcknowledged: Bool
    public var updatedAt: Date

    public init(
        activityId: String,
        kind: LiveActivityClusterKind,
        canonicalId: String,
        agentKind: String? = nil,
        projectSlug: String,
        tokenRevision: Int = 0,
        remoteDeliveryActive: Bool = false,
        registrationAcknowledged: Bool = false,
        updatedAt: Date = .now
    ) {
        self.activityId = activityId
        self.kind = kind
        self.canonicalId = canonicalId
        self.agentKind = agentKind
        self.projectSlug = projectSlug
        self.tokenRevision = tokenRevision
        self.remoteDeliveryActive = remoteDeliveryActive
        self.registrationAcknowledged = registrationAcknowledged
        self.updatedAt = updatedAt
    }
}

// MARK: - Coordinator

@MainActor
public final class LiveActivityClusterCoordinator {
    public typealias RegisterFn = @Sendable (LiveActivityRegistrationPayload) async -> Truthful<LiveActivityRegistrationAck>
    public typealias RevokeFn = @Sendable (_ activityId: String, _ installationId: String, _ reason: String) async -> Truthful<LiveActivityRevokeAck>

    public static let shared = LiveActivityClusterCoordinator()

    private static let installationDefaultsKey = "dev.sounio.cockpit.liveActivity.installationId"
    private static let associationsDefaultsKey = "dev.sounio.cockpit.liveActivity.associations.v1"

    private let defaults: UserDefaults
    private let bundleId: String
    private let apnsEnvironment: String
    private let registerTransport: RegisterFn
    private let revokeTransport: RevokeFn

    public let installationId: String
    public private(set) var associations: [String: PersistedLiveActivityAssociation] = [:]
    /// Transient in-memory hex tokens keyed by activityId for reconnect resubmission; never persisted.
    private var transientHexTokens: [String: String] = [:]
    private var lastSubmittedTokenByActivity: [String: String] = [:]
    nonisolated(unsafe) private var reconnectTask: Task<Void, Never>? = nil

    public init(
        defaults: UserDefaults = .standard,
        bundleId: String? = nil,
        apnsEnvironment: String? = nil,
        observeNetworkReconnect: Bool = true,
        registerTransport: RegisterFn? = nil,
        revokeTransport: RevokeFn? = nil
    ) {
        self.defaults = defaults
        self.bundleId = bundleId ?? Bundle.main.bundleIdentifier ?? "dev.sounio.cockpit"
        self.apnsEnvironment = apnsEnvironment ?? LiveActivityRegistrationPayload.defaultApnsEnvironment
        self.registerTransport = registerTransport ?? { payload in
            await CockpitClient.shared.registerLiveActivity(payload)
        }
        self.revokeTransport = revokeTransport ?? { activityId, installationId, reason in
            await CockpitClient.shared.revokeLiveActivity(
                activityId: activityId,
                installationId: installationId,
                reason: reason
            )
        }

        if let existingId = defaults.string(forKey: Self.installationDefaultsKey), !existingId.isEmpty {
            self.installationId = existingId
        } else {
            let fresh = UUID().uuidString.lowercased()
            defaults.set(fresh, forKey: Self.installationDefaultsKey)
            self.installationId = fresh
        }

        self.associations = Self.loadAssociations(from: defaults)

        if observeNetworkReconnect {
            self.reconnectTask = Task { @MainActor [weak self] in
                for await _ in NotificationCenter.default.notifications(named: .beagleNetworkDidReconnect) {
                    if Task.isCancelled { break }
                    await self?.resubmitAllActive()
                }
            }
        }
    }

    deinit {
        reconnectTask?.cancel()
    }

    /// Returns `true` when foreground local ActivityKit updates should remain active.
    /// Once the cluster acknowledges `remoteDeliveryActive == true`, local updates step aside
    /// to prevent competing foreground and APNs writers.
    public func shouldWriteLocally(activityId: String) -> Bool {
        guard let assoc = associations[activityId] else { return true }
        return !assoc.remoteDeliveryActive
    }

    /// Track an activity's canonical metadata before or after push token arrival.
    public func trackActivity(
        activityId: String,
        kind: LiveActivityClusterKind,
        canonicalId: String,
        agentKind: String? = nil,
        projectSlug: String
    ) {
        if var existing = associations[activityId] {
            existing.canonicalId = canonicalId
            existing.agentKind = agentKind ?? existing.agentKind
            existing.projectSlug = projectSlug
            existing.updatedAt = .now
            associations[activityId] = existing
        } else {
            associations[activityId] = PersistedLiveActivityAssociation(
                activityId: activityId,
                kind: kind,
                canonicalId: canonicalId,
                agentKind: agentKind,
                projectSlug: projectSlug
            )
        }
        persistAssociations()
    }

    /// Submit a raw Data push token from `activity.pushToken` or `activity.pushTokenUpdates`.
    @discardableResult
    public func submitPushTokenData(
        _ tokenData: Data,
        activityId: String,
        kind: LiveActivityClusterKind,
        canonicalId: String,
        agentKind: String? = nil,
        projectSlug: String,
        forceResubmit: Bool = false
    ) async -> LiveActivityRegistrationAck? {
        let hex = LiveActivityRegistrationPayload.encodeHexToken(tokenData)
        return await submitHexPushToken(
            hex,
            activityId: activityId,
            kind: kind,
            canonicalId: canonicalId,
            agentKind: agentKind,
            projectSlug: projectSlug,
            forceResubmit: forceResubmit
        )
    }

    /// Submit a hex push token (idempotent on unchanged token unless `forceResubmit` or previously unacknowledged).
    @discardableResult
    public func submitHexPushToken(
        _ hexToken: String,
        activityId: String,
        kind: LiveActivityClusterKind,
        canonicalId: String,
        agentKind: String? = nil,
        projectSlug: String,
        forceResubmit: Bool = false
    ) async -> LiveActivityRegistrationAck? {
        let cleanHex = hexToken.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard cleanHex.count >= 32 else { return nil }

        trackActivity(
            activityId: activityId,
            kind: kind,
            canonicalId: canonicalId,
            agentKind: agentKind,
            projectSlug: projectSlug
        )

        let previousHex = transientHexTokens[activityId]
        transientHexTokens[activityId] = cleanHex

        guard var assoc = associations[activityId] else { return nil }

        // Suppress duplicate network call if the exact token is already acknowledged and not forced
        if !forceResubmit,
           assoc.registrationAcknowledged,
           lastSubmittedTokenByActivity[activityId] == cleanHex {
            return nil
        }

        // Advance revision when rotating to a new token or on initial registration
        if previousHex != cleanHex || assoc.tokenRevision == 0 {
            assoc.tokenRevision += 1
        }
        assoc.updatedAt = .now
        associations[activityId] = assoc
        persistAssociations()

        let payload = LiveActivityRegistrationPayload(
            installationId: installationId,
            activityId: activityId,
            kind: kind,
            canonicalId: canonicalId,
            agentKind: agentKind,
            projectSlug: projectSlug,
            bundleId: bundleId,
            apnsEnvironment: apnsEnvironment,
            pushToken: cleanHex,
            tokenRevision: assoc.tokenRevision
        )

        let response = await registerTransport(payload)
        guard var current = associations[activityId] else { return response.value }

        if let ack = response.value {
            current.registrationAcknowledged = !ack.revoked && !ack.terminal
            current.remoteDeliveryActive = ack.remoteDeliveryActive
            current.tokenRevision = max(current.tokenRevision, ack.tokenRevision)
            current.updatedAt = .now
            associations[activityId] = current
            lastSubmittedTokenByActivity[activityId] = cleanHex
            persistAssociations()
            return ack
        } else {
            // Retain local foreground updates when registration fails or cluster is unreachable
            current.registrationAcknowledged = false
            current.remoteDeliveryActive = false
            current.updatedAt = .now
            associations[activityId] = current
            persistAssociations()
            return nil
        }
    }

    /// Re-submit all active tracked activities that have an in-memory token (e.g. after reconnect).
    public func resubmitAllActive() async {
        let snapshot = Array(associations.values)
        for assoc in snapshot {
            guard let hex = transientHexTokens[assoc.activityId] else { continue }
            _ = await submitHexPushToken(
                hex,
                activityId: assoc.activityId,
                kind: assoc.kind,
                canonicalId: assoc.canonicalId,
                agentKind: assoc.agentKind,
                projectSlug: assoc.projectSlug,
                forceResubmit: true
            )
        }
    }

    /// Prune any persisted associations whose `activityId` is no longer present in `Activity<...>.activities`.
    public func reconcileSurvivingActivities(activeIds: Set<String>) async {
        let staleIds = Set(associations.keys).subtracting(activeIds)
        for staleId in staleIds {
            await revoke(activityId: staleId, reason: "relaunch_missing")
        }
    }

    /// Revoke an ended or dismissed activity on the cluster and wipe local tracking state.
    public func revoke(activityId: String, reason: String = "dismissed") async {
        let hadAssociation = associations.removeValue(forKey: activityId) != nil
        transientHexTokens.removeValue(forKey: activityId)
        lastSubmittedTokenByActivity.removeValue(forKey: activityId)
        if hadAssociation {
            persistAssociations()
        }
        _ = await revokeTransport(activityId, installationId, reason)
    }

    // MARK: - Persistence (Non-Secret Metadata Only)

    private static func loadAssociations(from defaults: UserDefaults) -> [String: PersistedLiveActivityAssociation] {
        guard let data = defaults.data(forKey: associationsDefaultsKey),
              let decoded = try? JSONDecoder().decode([String: PersistedLiveActivityAssociation].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private func persistAssociations() {
        if let encoded = try? JSONEncoder().encode(associations) {
            defaults.set(encoded, forKey: Self.associationsDefaultsKey)
        }
    }
}

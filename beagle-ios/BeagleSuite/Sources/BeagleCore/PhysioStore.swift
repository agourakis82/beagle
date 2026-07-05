//
//  PhysioStore.swift
//  BeagleCore
//
//  Local body-state bridge for the Beagle exocortex.
//  Reads HealthKit when available and turns it into a compact,
//  discussion-ready summary instead of isolated biometrics.
//

import Foundation
import Observation
#if canImport(HealthKit)
import HealthKit
#endif

private extension ProcessInfo {
    var beagleSkipsPhysioAuthorization: Bool {
        arguments.contains("--beagle-skip-physio-auth")
    }
}

public enum PhysioAuthorizationState: String, Sendable {
    case unavailable
    case idle
    case requesting
    case authorized
    case denied
    case error
}

public enum PhysioReadiness: String, Sendable {
    case restored
    case steady
    case strained
    case unavailable

    public var title: String {
        switch self {
        case .restored:
            return "Body state is restored"
        case .steady:
            return "Body state is steady"
        case .strained:
            return "Body state is strained"
        case .unavailable:
            return "Body state is still unknown"
        }
    }

    public var discussionFlowState: String {
        switch self {
        case .restored:
            return "FLOW"
        case .steady:
            return "NORMAL"
        case .strained:
            return "STRESS"
        case .unavailable:
            return "UNKNOWN"
        }
    }
}

public struct PhysioConversationPolicy: Sendable, Equatable, Codable {
    public let modeLabel: String
    public let routeLabel: String
    public let companionInstruction: String
    public let noteInstruction: String
    public let pacingInstruction: String
    public let discussionProfile: DiscussionProfile
    public let preferLocal: Bool
    public let suggestedPlaceholder: String

    public init(
        modeLabel: String,
        routeLabel: String,
        companionInstruction: String,
        noteInstruction: String,
        pacingInstruction: String,
        discussionProfile: DiscussionProfile,
        preferLocal: Bool,
        suggestedPlaceholder: String
    ) {
        self.modeLabel = modeLabel
        self.routeLabel = routeLabel
        self.companionInstruction = companionInstruction
        self.noteInstruction = noteInstruction
        self.pacingInstruction = pacingInstruction
        self.discussionProfile = discussionProfile
        self.preferLocal = preferLocal
        self.suggestedPlaceholder = suggestedPlaceholder
    }

    public var requestBody: [String: any Sendable] {
        [
            "mode_label": modeLabel,
            "route_label": routeLabel,
            "companion_instruction": companionInstruction,
            "note_instruction": noteInstruction,
            "pacing_instruction": pacingInstruction,
            "discussion_profile": discussionProfile.rawValue,
            "prefer_local": preferLocal,
            "suggested_placeholder": suggestedPlaceholder
        ]
    }
}

public struct PhysioSummary: Sendable, Equatable {
    public let hrvMs: Double?
    public let restingHeartRate: Double?
    /// Most recent instantaneous heart rate (bpm) — the live interoceptive anchor.
    public let heartRate: Double?
    /// Latest Apple State of Mind valence (−1..1), logged by the user himself.
    public let stateOfMind: Double?
    /// Primary emotion word the user tagged on that State of Mind entry ("ansioso"), pt-BR.
    public let stateOfMindLabel: String?
    public let sleepHours: Double?
    public let mindfulMinutes: Double?
    public let workoutCount: Int
    public let observedAt: Date?
    public let authorizationState: PhysioAuthorizationState
    public let readiness: PhysioReadiness

    public init(
        hrvMs: Double? = nil,
        restingHeartRate: Double? = nil,
        heartRate: Double? = nil,
        stateOfMind: Double? = nil,
        stateOfMindLabel: String? = nil,
        sleepHours: Double? = nil,
        mindfulMinutes: Double? = nil,
        workoutCount: Int = 0,
        observedAt: Date? = nil,
        authorizationState: PhysioAuthorizationState = .idle,
        readiness: PhysioReadiness = .unavailable
    ) {
        self.hrvMs = hrvMs
        self.restingHeartRate = restingHeartRate
        self.heartRate = heartRate
        self.stateOfMind = stateOfMind
        self.stateOfMindLabel = stateOfMindLabel
        self.sleepHours = sleepHours
        self.mindfulMinutes = mindfulMinutes
        self.workoutCount = workoutCount
        self.observedAt = observedAt
        self.authorizationState = authorizationState
        self.readiness = readiness
    }

    public static let empty = PhysioSummary(
        authorizationState: .idle,
        readiness: .unavailable
    )

    public var isMeaningful: Bool {
        hrvMs != nil || restingHeartRate != nil || sleepHours != nil || mindfulMinutes != nil || workoutCount > 0
    }

    public var truthMode: TruthMode {
        switch authorizationState {
        case .authorized:
            return isMeaningful ? .observed : .remembered
        case .requesting, .idle:
            return .declared
        case .denied, .error, .unavailable:
            return .stale
        }
    }

    public var title: String {
        readiness.title
    }

    public var bodyLine: String {
        switch readiness {
        case .restored:
            return "Recovery looks good enough for deeper work. Let the larger mind carry more weight without overwhelming the thread."
        case .steady:
            return "Your body-state looks workable. Beagle should help you pace the day, not flood it."
        case .strained:
            return "The body is asking for gentler cognition. Prefer interpretation, compression, and one clear next move over escalation."
        case .unavailable:
            switch authorizationState {
            case .denied:
                return "Health access is off, so Beagle cannot yet sense how your body is shaping today’s cognition."
            case .unavailable:
                return "HealthKit is not available on this device, so the exocortex cannot read body-state here."
            default:
                return "Beagle can read HRV, sleep, recovery, and movement here, but it still needs permission or fresh samples."
            }
        }
    }

    public var detailLine: String {
        var parts: [String] = []
        if let hrvMs {
            parts.append("HRV \(Int(hrvMs)) ms")
        }
        if let sleepHours {
            parts.append(String(format: "sleep %.1f h", sleepHours))
        }
        if let restingHeartRate {
            parts.append("resting \(Int(restingHeartRate)) bpm")
        }
        if let mindfulMinutes, mindfulMinutes > 0 {
            parts.append("\(Int(mindfulMinutes)) mindful min")
        }
        if workoutCount > 0 {
            parts.append("\(workoutCount) workout\(workoutCount == 1 ? "" : "s")")
        }
        if let observedAt {
            parts.append("updated \(PhysioSummary.relativeTime(from: observedAt))")
        }
        return parts.isEmpty ? "No recent body-state samples yet." : parts.joined(separator: " · ")
    }

    public var recommendedPrompt: String {
        switch readiness {
        case .restored:
            return "I feel recovered enough for deeper work. Help me choose the one hard thing worth carrying today."
        case .steady:
            return "Given my current body-state, help me choose a sustainable next move instead of fragmenting."
        case .strained:
            return "I’m carrying some physiological strain. Help me simplify the lane and choose the gentlest high-value next move."
        case .unavailable:
            return "Help me decide the next move without body-state telemetry yet."
        }
    }

    public var promptContextLine: String {
        switch readiness {
        case .restored:
            return "Physio context: recovered enough for deeper work."
        case .steady:
            return "Physio context: steady, workable body-state."
        case .strained:
            return "Physio context: strained body-state; prefer gentler pacing and lower cognitive load."
        case .unavailable:
            return "Physio context: unavailable."
        }
    }

    public var conversationPolicy: PhysioConversationPolicy {
        switch readiness {
        case .restored:
            return PhysioConversationPolicy(
                modeLabel: "deep synthesis",
                routeLabel: "cluster depth",
                companionInstruction: "You can use higher cognitive pressure here. Make deeper cross-domain connections, challenge assumptions, and help carry the hard question without losing warmth or companionship.",
                noteInstruction: "Preserve research-grade notes. Capture the thread, the strongest hypothesis, the main uncertainty, and the next experiment or move.",
                pacingInstruction: "Longer answers are acceptable, but they should still resolve into a clear thread, a compact note trail, and one decisive next move.",
                discussionProfile: .cluster,
                preferLocal: false,
                suggestedPlaceholder: "What difficult idea should Beagle carry with you right now?"
            )
        case .steady:
            return PhysioConversationPolicy(
                modeLabel: "steady pacing",
                routeLabel: "balanced route",
                companionInstruction: "Keep the conversation clear, structured, and sustainable. Advance the idea without flooding the user with branches or pressure.",
                noteInstruction: "Compress the exchange into working notes with the active thread, the practical constraints, and one good next move.",
                pacingInstruction: "Prefer medium-length answers, explicit structure, and calm continuity over maximal depth.",
                discussionProfile: .qwen3b,
                preferLocal: true,
                suggestedPlaceholder: "What do you want to work through steadily?"
            )
        case .strained:
            return PhysioConversationPolicy(
                modeLabel: "gentle containment",
                routeLabel: "low-pressure route",
                companionInstruction: "Be calm, supportive, and low-pressure. Reduce branching, avoid intensity, and help lighten the thread instead of escalating it.",
                noteInstruction: "Preserve only the essential notes: one interpretation, one simplification, and one next move worth carrying.",
                pacingInstruction: "Prefer shorter answers, fewer options, and gentle compression. Do not overwhelm the user.",
                discussionProfile: .qwen3b,
                preferLocal: true,
                suggestedPlaceholder: "What feels heavy right now, and how should Beagle help lighten it?"
            )
        case .unavailable:
            return PhysioConversationPolicy(
                modeLabel: "adaptive listening",
                routeLabel: "adaptive route",
                companionInstruction: "Body-state is unavailable, so stay balanced, transparent, and adaptive instead of pretending certainty about the user's capacity.",
                noteInstruction: "Keep a light note trail with the living question, the current interpretation, and the next move.",
                pacingInstruction: "Prefer clear, moderate answers that can deepen later if the user wants more.",
                discussionProfile: .qwen3b,
                preferLocal: true,
                suggestedPlaceholder: "What should Beagle help you think through right now?"
            )
        }
    }

    public var suggestedDiscussionProfile: DiscussionProfile {
        conversationPolicy.discussionProfile
    }

    public var suggestedPreferLocal: Bool {
        conversationPolicy.preferLocal
    }

    private static func relativeTime(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: .now)
    }
}

/// A single night's sleep, bucketed by stage — the granular counterpart to
/// `PhysioSummary.sleepHours`, meant for a dedicated sleep view rather than the compact summary.
public struct SleepNight: Sendable, Equatable {
    public let date: Date
    public let totalAsleepHours: Double
    public let deepMinutes: Double
    public let remMinutes: Double
    public let coreMinutes: Double
    public let awakeMinutes: Double
    public let inBedHours: Double
    public let hrvMs: Double?
    public let restingHeartRate: Double?

    public init(
        date: Date,
        totalAsleepHours: Double,
        deepMinutes: Double,
        remMinutes: Double,
        coreMinutes: Double,
        awakeMinutes: Double,
        inBedHours: Double,
        hrvMs: Double? = nil,
        restingHeartRate: Double? = nil
    ) {
        self.date = date
        self.totalAsleepHours = totalAsleepHours
        self.deepMinutes = deepMinutes
        self.remMinutes = remMinutes
        self.coreMinutes = coreMinutes
        self.awakeMinutes = awakeMinutes
        self.inBedHours = inBedHours
        self.hrvMs = hrvMs
        self.restingHeartRate = restingHeartRate
    }

    /// Ratio of restorative (deep + REM) sleep to total asleep time, 0 when nothing was asleep.
    public var deepREMFraction: Double {
        guard totalAsleepHours > 0 else { return 0 }
        let totalAsleepMinutes = totalAsleepHours * 60.0
        return (deepMinutes + remMinutes) / totalAsleepMinutes
    }
}

// MARK: - Cognitive Posture (5-signal biosensor fusion)

public struct CognitivePosture: Sendable {
    public let hrv: Double?
    public let respiratoryRate: Double?
    public let wristTemperature: Double?
    public let sleepQuality: Double?  // 0.0-1.0 ratio of deep+REM to total
    public let stateOfMind: Double?   // -1.0 to 1.0 valence
    public let observedAt: Date?

    public static let empty = CognitivePosture(hrv: nil, respiratoryRate: nil, wristTemperature: nil, sleepQuality: nil, stateOfMind: nil, observedAt: nil)

    public var readiness: Double? {
        var total = 0.0, weight = 0.0
        if let hrv { total += normalizeHRV(hrv) * 0.4; weight += 0.4 }
        if let sleepQuality { total += sleepQuality * 0.3; weight += 0.3 }
        if let respiratoryRate { total += normalizeRespiratory(respiratoryRate) * 0.15; weight += 0.15 }
        if let wristTemperature { total += normalizeTemperature(wristTemperature) * 0.15; weight += 0.15 }
        guard weight > 0 else { return nil }
        return total / weight
    }

    public var suggestedIntensity: InterfaceIntensity {
        guard let r = readiness else { return .normal }
        let hour = Calendar.current.component(.hour, from: .now)
        if hour >= 23 || hour < 5 { return .minimal }
        if r >= 0.7 { return .challenge }
        if r >= 0.5 { return .engaged }
        if r >= 0.3 { return .normal }
        return .calm
    }

    public enum InterfaceIntensity: String, Sendable {
        case minimal, calm, normal, engaged, challenge
    }

    private func normalizeHRV(_ ms: Double) -> Double { min(max((ms - 20) / 80, 0), 1) }
    private func normalizeRespiratory(_ bpm: Double) -> Double { bpm >= 12 && bpm <= 20 ? 0.8 : 0.4 }
    private func normalizeTemperature(_ delta: Double) -> Double { abs(delta) < 0.5 ? 0.8 : 0.4 }
}

@Observable
@MainActor
public final class PhysioStore {
    public private(set) var summary: PhysioSummary = .empty
    public private(set) var cognitivePosture: CognitivePosture = .empty
    public private(set) var authorizationState: PhysioAuthorizationState = .idle
    public private(set) var isRefreshing = false
    public private(set) var lastError: String?

    public init() {}

    public var isAvailable: Bool {
        #if canImport(HealthKit)
        return HKHealthStore.isHealthDataAvailable()
        #else
        return false
        #endif
    }

    public func refresh(requestAuthorization: Bool = false) async {
        #if canImport(HealthKit)
        if ProcessInfo.processInfo.beagleSkipsPhysioAuthorization {
            authorizationState = .unavailable
            summary = PhysioSummary(authorizationState: .unavailable, readiness: .unavailable)
            return
        }
        guard HKHealthStore.isHealthDataAvailable() else {
            authorizationState = .unavailable
            summary = PhysioSummary(authorizationState: .unavailable, readiness: .unavailable)
            return
        }

        isRefreshing = true
        lastError = nil
        defer { isRefreshing = false }

        do {
            try await requestAuthorizationIfNeeded(allowPrompt: requestAuthorization)
            guard authorizationState == .authorized else {
                summary = PhysioSummary(authorizationState: authorizationState, readiness: .unavailable)
                return
            }

            let hrv = try await latestQuantitySample(
                identifier: .heartRateVariabilitySDNN,
                unit: HKUnit(from: "ms"),
                lookbackDays: 3
            )
            let resting = try await latestQuantitySample(
                identifier: .restingHeartRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                lookbackDays: 7
            )
            let sleepHours = try await sleepHoursLastNight()
            let mindfulMinutes = try await mindfulMinutesToday()
            let workoutCount = try await workoutCountToday()

            // 5-signal biosensor fusion: additional queries
            let respiratoryRate = try await queryRespiratoryRate()
            let wristTemperature = try await queryWristTemperature()
            let sleepQualityRatio = try await querySleepQuality()

            let observedAt = [hrv?.date, resting?.date].compactMap { $0 }.max()
            let readiness = Self.classifyReadiness(
                hrvMs: hrv?.value,
                restingHeartRate: resting?.value,
                sleepHours: sleepHours,
                workoutCount: workoutCount
            )

            let som = await queryStateOfMind()
            let latestHeartRate = await queryLatestHeartRate()

            summary = PhysioSummary(
                hrvMs: hrv?.value,
                restingHeartRate: resting?.value,
                heartRate: latestHeartRate,
                stateOfMind: som?.valence,
                stateOfMindLabel: som?.label,
                sleepHours: sleepHours,
                mindfulMinutes: mindfulMinutes,
                workoutCount: workoutCount,
                observedAt: observedAt,
                authorizationState: authorizationState,
                readiness: readiness
            )

            cognitivePosture = CognitivePosture(
                hrv: hrv?.value,
                respiratoryRate: respiratoryRate,
                wristTemperature: wristTemperature,
                sleepQuality: sleepQualityRatio,
                stateOfMind: som?.valence,
                observedAt: observedAt
            )
        } catch {
            authorizationState = .error
            lastError = error.localizedDescription
            summary = PhysioSummary(authorizationState: .error, readiness: .unavailable)
        }
        #else
        authorizationState = .unavailable
        summary = PhysioSummary(authorizationState: .unavailable, readiness: .unavailable)
        #endif
    }

    /// Last night's sleep, bucketed by stage (deep/REM/core/awake/inBed) plus the latest HRV and
    /// resting heart rate — the granular counterpart to `summary.sleepHours` for a dedicated sleep
    /// view. Returns nil only when there were zero asleep samples in the last 24h, so the view can
    /// distinguish "no sleep data yet" from "slept zero restorative minutes."
    public func lastNightSleep() async -> SleepNight? {
        #if canImport(HealthKit)
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        let calendar = Calendar.current
        let end = Date()
        let start = calendar.date(byAdding: .day, value: -1, to: end) ?? end.addingTimeInterval(-86400)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        let samples: [HKCategorySample]
        do {
            samples = try await withCheckedThrowingContinuation { continuation in
                let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    continuation.resume(returning: (samples as? [HKCategorySample]) ?? [])
                }
                healthStore.execute(query)
            }
        } catch {
            return nil
        }

        var deepSeconds = 0.0
        var remSeconds = 0.0
        var coreSeconds = 0.0
        var awakeSeconds = 0.0
        var inBedSeconds = 0.0
        var latestEnd: Date?

        for sample in samples {
            let duration = sample.endDate.timeIntervalSince(sample.startDate)
            switch sample.value {
            case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                deepSeconds += duration
            case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                remSeconds += duration
            case HKCategoryValueSleepAnalysis.asleepCore.rawValue, HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
                coreSeconds += duration
            case HKCategoryValueSleepAnalysis.awake.rawValue:
                awakeSeconds += duration
            case HKCategoryValueSleepAnalysis.inBed.rawValue:
                inBedSeconds += duration
            default:
                break
            }
            if latestEnd == nil || sample.endDate > latestEnd! {
                latestEnd = sample.endDate
            }
        }

        let totalAsleepSeconds = deepSeconds + remSeconds + coreSeconds
        guard totalAsleepSeconds > 0 else { return nil }

        let hrvSample = (try? await latestQuantitySample(
            identifier: .heartRateVariabilitySDNN,
            unit: HKUnit(from: "ms"),
            lookbackDays: 1
        )) ?? nil
        let restingSample = (try? await latestQuantitySample(
            identifier: .restingHeartRate,
            unit: HKUnit.count().unitDivided(by: .minute()),
            lookbackDays: 1
        )) ?? nil

        return SleepNight(
            date: latestEnd ?? end,
            totalAsleepHours: totalAsleepSeconds / 3600.0,
            deepMinutes: deepSeconds / 60.0,
            remMinutes: remSeconds / 60.0,
            coreMinutes: coreSeconds / 60.0,
            awakeMinutes: awakeSeconds / 60.0,
            inBedHours: inBedSeconds / 3600.0,
            hrvMs: hrvSample?.value,
            restingHeartRate: restingSample?.value
        )
        #else
        return nil
        #endif
    }

    #if canImport(HealthKit)
    private let healthStore = HKHealthStore()

    private func requestAuthorizationIfNeeded(allowPrompt: Bool) async throws {
        var readTypes: Set<HKObjectType> = [
            HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
            HKQuantityType.quantityType(forIdentifier: .restingHeartRate)!,
            HKQuantityType.quantityType(forIdentifier: .heartRate)!,
            HKQuantityType(.respiratoryRate),
            HKQuantityType(.appleSleepingWristTemperature),
            HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKCategoryType.categoryType(forIdentifier: .mindfulSession)!,
            HKObjectType.workoutType()
        ]
        if #available(iOS 18.0, watchOS 11.0, macOS 15.0, *) {
            readTypes.insert(HKSampleType.stateOfMindType())
        }

        if authorizationState == .authorized {
            return
        }

        guard allowPrompt else {
            if authorizationState == .requesting {
                authorizationState = .idle
            }
            return
        }

        authorizationState = .requesting
        try await healthStore.requestAuthorization(toShare: [], read: readTypes)

        // authorizationStatus(for:) reports SHARE/write permission only. Apple deliberately keeps
        // it .sharingDenied for a read-only app even when READ access is fully granted (read status
        // is unqueryable for privacy) — so it must NOT gate reads. The old heuristic below flipped
        // authorizationState to .denied whenever the HRV *write* toggle was off, emptying the whole
        // summary despite Health being on (observed as AUTH:denied with HRV/HR/sleep all absent).
        // After requestAuthorization returns, treat as authorized; the sample reads fail-soft to
        // nil if read was actually denied, which surfaces honestly as "no data" — not a hard block.
        authorizationState = .authorized
    }

    private func latestQuantitySample(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        lookbackDays: Int
    ) async throws -> (value: Double, date: Date)? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -lookbackDays, to: end) ?? end.addingTimeInterval(-86400 * Double(lookbackDays))
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: [sort]) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: (sample.quantity.doubleValue(for: unit), sample.endDate))
            }
            healthStore.execute(query)
        }
    }

    private func sleepHoursLastNight() async throws -> Double? {
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        let calendar = Calendar.current
        let end = Date()
        let start = calendar.date(byAdding: .day, value: -1, to: end) ?? end.addingTimeInterval(-86400)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            healthStore.execute(query)
        }

        let asleepRawValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue
        ]

        let seconds = samples
            .filter { asleepRawValues.contains($0.value) }
            .reduce(0.0) { partial, sample in
                partial + sample.endDate.timeIntervalSince(sample.startDate)
            }

        guard seconds > 0 else { return nil }
        return seconds / 3600.0
    }

    private func mindfulMinutesToday() async throws -> Double? {
        guard let type = HKCategoryType.categoryType(forIdentifier: .mindfulSession) else { return nil }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: .now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)

        let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            healthStore.execute(query)
        }

        let seconds = samples.reduce(0.0) { partial, sample in
            partial + sample.endDate.timeIntervalSince(sample.startDate)
        }
        guard seconds > 0 else { return nil }
        return seconds / 60.0
    }

    private func workoutCountToday() async throws -> Int {
        let type = HKObjectType.workoutType()
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: .now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: samples?.count ?? 0)
            }
            healthStore.execute(query)
        }
    }

    // MARK: - 5-signal biosensor queries

    private func queryRespiratoryRate() async throws -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .respiratoryRate) else { return nil }
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -1, to: end) ?? end.addingTimeInterval(-86400)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: [sort]) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                let bpm = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                continuation.resume(returning: bpm)
            }
            healthStore.execute(query)
        }
    }

    private func queryWristTemperature() async throws -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .appleSleepingWristTemperature) else { return nil }
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -3, to: end) ?? end.addingTimeInterval(-86400 * 3)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: [sort]) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                let celsius = sample.quantity.doubleValue(for: .degreeCelsius())
                continuation.resume(returning: celsius)
            }
            healthStore.execute(query)
        }
    }

    private func querySleepQuality() async throws -> Double? {
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        let calendar = Calendar.current
        let end = Date()
        let start = calendar.date(byAdding: .day, value: -1, to: end) ?? end.addingTimeInterval(-86400)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            healthStore.execute(query)
        }

        let deepREMValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue
        ]
        let allAsleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue
        ]

        let deepREMSeconds = samples
            .filter { deepREMValues.contains($0.value) }
            .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
        let totalAsleepSeconds = samples
            .filter { allAsleepValues.contains($0.value) }
            .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }

        guard totalAsleepSeconds > 0 else { return nil }
        return deepREMSeconds / totalAsleepSeconds
    }

    /// Query the latest State of Mind from HealthKit (iOS 18+): valence (−1..1) plus the primary
    /// emotion word the user tagged, mapped to pt-BR. nil when none logged in the last ~3 days.
    private func queryStateOfMind() async -> (valence: Double, label: String?)? {
        guard #available(iOS 18.0, watchOS 11.0, macOS 15.0, *) else { return nil }
        let sampleType = HKSampleType.stateOfMindType()
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -3, to: end) ?? end.addingTimeInterval(-86400 * 3)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return try? await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(valence: Double, label: String?)?, Error>) in
            let query = HKSampleQuery(sampleType: sampleType, predicate: predicate, limit: 1, sortDescriptors: [sort]) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let sample = samples?.first as? HKStateOfMind else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: (sample.valence, Self.stateOfMindLabelPtBR(sample.labels)))
            }
            healthStore.execute(query)
        }
    }

    /// Map the user's tagged Apple State of Mind label to a pt-BR emotion word (adjective form),
    /// or nil for anything unmapped — the server then falls back to the valence band. A regular
    /// `default` covers future/unknown labels (HKStateOfMind.Label is a non-frozen enum).
    @available(iOS 18.0, watchOS 11.0, macOS 15.0, *)
    private static func stateOfMindLabelPtBR(_ labels: [HKStateOfMind.Label]) -> String? {
        guard let label = labels.first else { return nil }
        switch label {
        case .amazed: return "maravilhado"
        case .amused: return "divertido"
        case .angry: return "com raiva"
        case .anxious: return "ansioso"
        case .ashamed: return "envergonhado"
        case .brave: return "corajoso"
        case .calm: return "calmo"
        case .content: return "contente"
        case .disappointed: return "decepcionado"
        case .discouraged: return "desencorajado"
        case .disgusted: return "com nojo"
        case .embarrassed: return "constrangido"
        case .excited: return "empolgado"
        case .frustrated: return "frustrado"
        case .grateful: return "grato"
        case .guilty: return "culpado"
        case .happy: return "feliz"
        case .hopeful: return "esperançoso"
        case .indifferent: return "indiferente"
        case .irritated: return "irritado"
        case .jealous: return "com ciúme"
        case .joyful: return "radiante"
        case .lonely: return "solitário"
        case .overwhelmed: return "sobrecarregado"
        case .passionate: return "apaixonado"
        case .peaceful: return "em paz"
        case .proud: return "orgulhoso"
        case .relieved: return "aliviado"
        case .sad: return "triste"
        case .satisfied: return "satisfeito"
        case .scared: return "assustado"
        case .stressed: return "estressado"
        case .surprised: return "surpreso"
        case .worried: return "preocupado"
        default: return nil
        }
    }

    /// Query the most recent instantaneous heart rate sample (bpm) from HealthKit, or nil.
    /// The live beat the companion names back as an interoceptive anchor in a hard moment.
    private func queryLatestHeartRate() async -> Double? {
        let sampleType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let end = Date()
        let start = Calendar.current.date(byAdding: .hour, value: -6, to: end) ?? end.addingTimeInterval(-3600 * 6)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let bpmUnit = HKUnit.count().unitDivided(by: .minute())

        return try? await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Double?, Error>) in
            let query = HKSampleQuery(sampleType: sampleType, predicate: predicate, limit: 1, sortDescriptors: [sort]) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: sample.quantity.doubleValue(for: bpmUnit))
            }
            healthStore.execute(query)
        }
    }
    #endif

    private static func classifyReadiness(
        hrvMs: Double?,
        restingHeartRate: Double?,
        sleepHours: Double?,
        workoutCount: Int
    ) -> PhysioReadiness {
        if let sleepHours, sleepHours < 5.5 {
            return .strained
        }
        if let hrvMs, hrvMs < 45 {
            return .strained
        }
        if let restingHeartRate, restingHeartRate > 78 {
            return .strained
        }
        if let hrvMs, let sleepHours, hrvMs >= 75, sleepHours >= 7 {
            return .restored
        }
        if workoutCount >= 1, (sleepHours ?? 6) >= 6, (hrvMs ?? 55) >= 55 {
            return .restored
        }
        if hrvMs != nil || restingHeartRate != nil || sleepHours != nil {
            return .steady
        }
        return .unavailable
    }
}

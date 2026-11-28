//
//  HealthSyncEngine.swift
//  BeagleCore
//
//  Incremental HealthKit sync layer for the Beagle Physiome foundation.
//
//  Requests authorization for the complete HealthKit type set defined in the
//  Beagle Physiome spec (2026-06-22). Manages per-type HKAnchoredObjectQuery
//  with persisted anchors so only new samples are fetched on every launch.
//  HKObserverQuery + enableBackgroundDelivery keeps anchors current in the
//  background; foreground catch-up is triggered on every app resume.
//
//  Architecture:
//    HealthSyncEngine (actor) ──→ PhysiomeSampleBatch (struct)
//                             ──→ PhysiomeUploader (actor)
//
//  Anchor persistence: UserDefaults under "beagle.healthsync.anchors.<typeId>"
//  (serialised as NSKeyedArchiver Data). Safe to wipe for full-history backfill.
//
//  Entitlements required (add to BeagleCockpit.entitlements in Xcode):
//    com.apple.developer.healthkit                       = true
//    com.apple.developer.healthkit.background-delivery  = true
//

import Foundation
#if canImport(HealthKit)
import HealthKit

// MARK: - Sample model

/// A single HealthKit sample ready to be sent to /api/physiome/ingest.
public struct PhysioHealthSample: Sendable, Codable, Equatable {
    /// Stable UUID from HKObject.uuid — used for idempotent upsert on the server.
    public let uuid: String
    /// ISO-8601 start timestamp.
    public let ts: String
    /// ISO-8601 end timestamp (same as ts for instantaneous samples).
    public let endTs: String
    /// Canonical type identifier, e.g. "HKQuantityTypeIdentifierHeartRateVariabilitySDNN".
    public let type: String
    /// Numeric value in the canonical unit.
    public let value: Double
    /// Canonical unit string, e.g. "ms", "count/min", "%.
    public let unit: String
    /// Source bundle ID or device name.
    public let source: String
    /// Device model/name if available.
    public let device: String?
    /// Extra structured fields the flat columns can't hold (e.g. ECG classification,
    /// symptoms) — lands in the server's health_samples.metadata JSONB.
    public let metadata: [String: String]?

    // The server reads snake_case (end_ts) and the encoder does NOT convert case, so
    // map endTs explicitly — otherwise end_ts is silently dropped (breaks sleep duration).
    enum CodingKeys: String, CodingKey {
        case uuid, ts
        case endTs = "end_ts"
        case type, value, unit, source, device, metadata
    }

    public init(
        uuid: String,
        ts: String,
        endTs: String,
        type: String,
        value: Double,
        unit: String,
        source: String,
        device: String?,
        metadata: [String: String]? = nil
    ) {
        self.uuid = uuid
        self.ts = ts
        self.endTs = endTs
        self.type = type
        self.value = value
        self.unit = unit
        self.source = source
        self.device = device
        self.metadata = metadata
    }
}

/// A single sleep category sample (HKCategorySample).
public struct PhysioSleepSample: Sendable, Codable, Equatable {
    public let uuid: String
    public let ts: String
    public let endTs: String
    public let type: String      // always "HKCategoryTypeIdentifierSleepAnalysis"
    public let value: Int        // raw HKCategoryValueSleepAnalysis int
    public let source: String
    public let device: String?

    enum CodingKeys: String, CodingKey {
        case uuid, ts
        case endTs = "end_ts"    // server needs end_ts to compute sleep duration
        case type, value, source, device
    }
}

/// A single workout summary.
public struct PhysioWorkoutSample: Sendable, Codable, Equatable {
    public let uuid: String
    public let ts: String
    public let endTs: String
    public let type: String      // always "HKWorkoutType"
    public let activityType: UInt
    public let durationSeconds: Double
    public let totalEnergyKcal: Double?
    public let totalDistanceMeters: Double?
    public let source: String
    public let device: String?

    enum CodingKeys: String, CodingKey {
        case uuid, ts
        case endTs = "end_ts"
        case type
        case activityType = "activity_type"
        case durationSeconds = "duration_seconds"
        case totalEnergyKcal = "total_energy_kcal"
        case totalDistanceMeters = "total_distance_meters"
        case source, device
    }
}

// MARK: - Observer completion box

/// Lets HKObserverQuery's non-Sendable completion handler cross into a Task without
/// tripping Swift 6 'sending' diagnostics. HealthKit guarantees a single call.
struct SendableObserverCompletion: @unchecked Sendable {
    private let handler: HKObserverQueryCompletionHandler
    init(_ handler: @escaping HKObserverQueryCompletionHandler) { self.handler = handler }
    func callAsFunction() { handler() }
}

// MARK: - Engine

/// Actor that owns the HealthKit store and all anchor/observer management.
/// Safe to call from any Task context. All HealthKit callbacks are marshalled
/// through Swift concurrency continuations.
public actor HealthSyncEngine {

    // MARK: - Shared

    public static let shared = HealthSyncEngine()

    // MARK: - State

    let store = HKHealthStore()
    // Sendable value-type ISO-8601 formatter so nonisolated HKAnchoredObjectQuery
    // result closures can format timestamps safely without `nonisolated(unsafe)`.
    private static let iso8601Style = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    static func iso8601String(from date: Date) -> String {
        date.formatted(iso8601Style)
    }

    var observerTokens: [String: HKObserverQuery] = [:]
    private var isAuthorized = false

    // The Swift overlay doesn't expose a short case name (e.g. `.gad7`) for these — only
    // the raw ObjC constant strings are documented (HKTypeIdentifiers.h) — so construct via
    // RawRepresentable instead of guessing a synthesized short name.
    @available(iOS 18.0, watchOS 11.0, macOS 15.0, *)
    static let gad7AssessmentType = HKScoredAssessmentType(
        HKScoredAssessmentTypeIdentifier(rawValue: "HKScoredAssessmentTypeIdentifierGAD7")
    )
    @available(iOS 18.0, watchOS 11.0, macOS 15.0, *)
    static let phq9AssessmentType = HKScoredAssessmentType(
        HKScoredAssessmentTypeIdentifier(rawValue: "HKScoredAssessmentTypeIdentifierPHQ9")
    )

    // MARK: - Type catalogue

    /// Complete set of quantity types to authorise and sync.
    private static var quantityTypeIds: [(HKQuantityTypeIdentifier, String, HKUnit)] {
        var list: [(HKQuantityTypeIdentifier, String, HKUnit)] = [
            (.heartRate,                             "HKQuantityTypeIdentifierHeartRate",                             .count().unitDivided(by: .minute())),
            (.heartRateVariabilitySDNN,              "HKQuantityTypeIdentifierHeartRateVariabilitySDNN",              HKUnit(from: "ms")),
            (.restingHeartRate,                      "HKQuantityTypeIdentifierRestingHeartRate",                      .count().unitDivided(by: .minute())),
            (.walkingHeartRateAverage,               "HKQuantityTypeIdentifierWalkingHeartRateAverage",               .count().unitDivided(by: .minute())),
            (.respiratoryRate,                       "HKQuantityTypeIdentifierRespiratoryRate",                       .count().unitDivided(by: .minute())),
            (.oxygenSaturation,                      "HKQuantityTypeIdentifierOxygenSaturation",                      .percent()),
            (.stepCount,                             "HKQuantityTypeIdentifierStepCount",                             .count()),
            (.distanceWalkingRunning,                "HKQuantityTypeIdentifierDistanceWalkingRunning",                .meter()),
            (.activeEnergyBurned,                    "HKQuantityTypeIdentifierActiveEnergyBurned",                    .kilocalorie()),
            (.basalEnergyBurned,                     "HKQuantityTypeIdentifierBasalEnergyBurned",                     .kilocalorie()),
            (.flightsClimbed,                        "HKQuantityTypeIdentifierFlightsClimbed",                        .count()),
            (.vo2Max,                                "HKQuantityTypeIdentifierVO2Max",                                HKUnit(from: "ml/kg*min")),
            (.appleSleepingWristTemperature,         "HKQuantityTypeIdentifierAppleSleepingWristTemperature",         .degreeCelsius()),
        ]
        #if os(iOS) || os(watchOS)
        // Circadian / environmental signals (Watch-sourced) — core to the heliobiology
        // angle: daylight exposure, activity-ring time, ambient noise. iOS/watchOS only.
        list.append((.timeInDaylight,            "HKQuantityTypeIdentifierTimeInDaylight",            .minute()))
        list.append((.appleExerciseTime,         "HKQuantityTypeIdentifierAppleExerciseTime",         .minute()))
        list.append((.appleStandTime,            "HKQuantityTypeIdentifierAppleStandTime",            .minute()))
        list.append((.environmentalAudioExposure, "HKQuantityTypeIdentifierEnvironmentalAudioExposure", .decibelAWeightedSoundPressureLevel()))
        // Mobility (iPhone motion coprocessor, iOS 14+) — non-obvious gait signals for the
        // N-of-1 panorama: asymmetry/double-support can shift subtly with fatigue or affect
        // before the person consciously notices.
        list.append((.walkingSpeed,                       "HKQuantityTypeIdentifierWalkingSpeed",                       HKUnit(from: "m/s")))
        list.append((.walkingStepLength,                  "HKQuantityTypeIdentifierWalkingStepLength",                  .meter()))
        list.append((.walkingAsymmetryPercentage,         "HKQuantityTypeIdentifierWalkingAsymmetryPercentage",         .percent()))
        list.append((.walkingDoubleSupportPercentage,     "HKQuantityTypeIdentifierWalkingDoubleSupportPercentage",     .percent()))
        list.append((.stairAscentSpeed,                   "HKQuantityTypeIdentifierStairAscentSpeed",                   HKUnit(from: "m/s")))
        list.append((.stairDescentSpeed,                  "HKQuantityTypeIdentifierStairDescentSpeed",                  HKUnit(from: "m/s")))
        // Balance (iPhone motion coprocessor, iOS 15+) — steadiness score; a gradual decline
        // can precede a fall-risk event, complementing the fall-risk category event below.
        if #available(iOS 15.0, watchOS 8.0, *) {
            list.append((.appleWalkingSteadiness, "HKQuantityTypeIdentifierAppleWalkingSteadiness", .percent()))
        }
        // Cardio recovery (Watch, iOS 16+) — how fast HR drops after exertion; an autonomic
        // tone signal distinct from resting HR/HRV.
        if #available(iOS 16.0, watchOS 9.0, *) {
            list.append((.heartRateRecoveryOneMinute, "HKQuantityTypeIdentifierHeartRateRecoveryOneMinute", .count().unitDivided(by: .minute())))
        }
        #endif
        return list
    }

    /// All HKObjectTypes that we request read authorisation for.
    private static var allReadTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()
        for (id, _, _) in quantityTypeIds {
            if let t = HKQuantityType.quantityType(forIdentifier: id) { types.insert(t) }
        }
        if let sleep = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) { types.insert(sleep) }
        if let mind  = HKCategoryType.categoryType(forIdentifier: .mindfulSession) { types.insert(mind) }
        types.insert(HKObjectType.workoutType())
        if #available(iOS 18.0, watchOS 11.0, macOS 15.0, *) {
            types.insert(HKSampleType.stateOfMindType())
        }
        if #available(iOS 18.0, watchOS 11.0, *),
           let apnea = HKCategoryType.categoryType(forIdentifier: .sleepApneaEvent) {
            types.insert(apnea)
        }
        if #available(iOS 18.0, watchOS 11.0, macOS 15.0, *) {
            types.insert(Self.gad7AssessmentType)
            types.insert(Self.phq9AssessmentType)
        }
        if #available(iOS 15.0, watchOS 8.0, *),
           let steadinessEvent = HKCategoryType.categoryType(forIdentifier: .appleWalkingSteadinessEvent) {
            types.insert(steadinessEvent)
        }
        #if os(iOS) || os(watchOS)
        types.insert(HKObjectType.electrocardiogramType())   // Apple Watch ECG
        #endif
        return types
    }

    // MARK: - Authorization

    /// Request read authorisation for all Physiome types. Safe to call multiple times.
    public func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        try await store.requestAuthorization(toShare: [], read: Self.allReadTypes)
        isAuthorized = true
    }

    // MARK: - Foreground catch-up

    /// Pull all new samples since last anchor and hand them to the uploader.
    /// Called every time the app comes to foreground and on first launch.
    public func catchUp(uploader: PhysiomeUploader) async {
        guard HKHealthStore.isHealthDataAvailable(), isAuthorized else { return }

        // Quantity types
        for (id, label, unit) in Self.quantityTypeIds {
            guard let type = HKQuantityType.quantityType(forIdentifier: id) else { continue }
            do {
                let samples = try await fetchNewQuantitySamples(type: type, label: label, unit: unit)
                if !samples.isEmpty {
                    await uploader.enqueue(healthSamples: samples)
                }
            } catch {
                print("[HealthSyncEngine] catch-up failed for \(label): \(error)")
            }
        }

        // Sleep
        do {
            let sleep = try await fetchNewSleepSamples()
            if !sleep.isEmpty {
                await uploader.enqueue(sleepSamples: sleep)
            }
        } catch {
            print("[HealthSyncEngine] sleep catch-up failed: \(error)")
        }

        // Workouts
        do {
            let workouts = try await fetchNewWorkouts()
            if !workouts.isEmpty {
                await uploader.enqueue(workoutSamples: workouts)
            }
        } catch {
            print("[HealthSyncEngine] workout catch-up failed: \(error)")
        }

        // ECG (Apple Watch)
        #if os(iOS) || os(watchOS)
        do {
            let ecgs = try await fetchNewECG()
            if !ecgs.isEmpty { await uploader.enqueue(healthSamples: ecgs) }
        } catch {
            print("[HealthSyncEngine] ECG catch-up failed: \(error)")
        }
        #endif

        // Mood (HKStateOfMind, iOS 18+) — authorized since line ~202 but never actually fetched
        // until now; see fetchNewStateOfMind's doc comment for the full story.
        if #available(iOS 18.0, watchOS 11.0, macOS 15.0, *) {
            do {
                let moods = try await fetchNewStateOfMind()
                if !moods.isEmpty { await uploader.enqueue(healthSamples: moods) }
            } catch {
                print("[HealthSyncEngine] state-of-mind catch-up failed: \(error)")
            }
        }

        // Clinical questionnaires (GAD-7/PHQ-9, iOS 18+) — read-only, filled out via Health app
        if #available(iOS 18.0, watchOS 11.0, macOS 15.0, *) {
            do {
                let gad7 = try await fetchNewGAD7Assessments()
                if !gad7.isEmpty { await uploader.enqueue(healthSamples: gad7) }
            } catch {
                print("[HealthSyncEngine] GAD-7 catch-up failed: \(error)")
            }
            do {
                let phq9 = try await fetchNewPHQ9Assessments()
                if !phq9.isEmpty { await uploader.enqueue(healthSamples: phq9) }
            } catch {
                print("[HealthSyncEngine] PHQ-9 catch-up failed: \(error)")
            }
        }

        // Sleep apnea / breathing disturbances (Watch, watchOS 11+)
        if #available(iOS 18.0, watchOS 11.0, *) {
            do {
                let apneaEvents = try await fetchNewSleepApneaEvents()
                if !apneaEvents.isEmpty { await uploader.enqueue(sleepSamples: apneaEvents) }
            } catch {
                print("[HealthSyncEngine] sleep-apnea catch-up failed: \(error)")
            }
        }

        // Fall-risk / walking-steadiness-decline events (iOS 15+)
        if #available(iOS 15.0, watchOS 8.0, *) {
            do {
                let steadinessEvents = try await fetchNewWalkingSteadinessEvents()
                if !steadinessEvents.isEmpty { await uploader.enqueue(sleepSamples: steadinessEvents) }
            } catch {
                print("[HealthSyncEngine] walking-steadiness catch-up failed: \(error)")
            }
        }
    }

    // MARK: - Background delivery registration

    /// Register HKObserverQuery + enableBackgroundDelivery for every type.
    /// Call once after authorisation, typically from AppDelegate/Scene lifecycle.
    public func enableBackgroundDelivery(uploader: PhysiomeUploader) async {
        guard HKHealthStore.isHealthDataAvailable(), isAuthorized else { return }

        for (id, label, unit) in Self.quantityTypeIds {
            guard let type = HKQuantityType.quantityType(forIdentifier: id) else { continue }
            do {
                try await store.enableBackgroundDelivery(for: type, frequency: .hourly)
                registerObserver(for: type, label: label, unit: unit, uploader: uploader)
            } catch {
                print("[HealthSyncEngine] background delivery failed for \(label): \(error)")
            }
        }

        if let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) {
            do {
                try await store.enableBackgroundDelivery(for: sleepType, frequency: .hourly)
                registerSleepObserver(uploader: uploader)
            } catch {
                print("[HealthSyncEngine] sleep background delivery failed: \(error)")
            }
        }

        let workoutType = HKObjectType.workoutType()
        do {
            try await store.enableBackgroundDelivery(for: workoutType, frequency: .hourly)
            registerWorkoutObserver(uploader: uploader)
        } catch {
            print("[HealthSyncEngine] workout background delivery failed: \(error)")
        }

        #if os(iOS) || os(watchOS)
        let ecgType = HKObjectType.electrocardiogramType()
        do {
            try await store.enableBackgroundDelivery(for: ecgType, frequency: .immediate)
            registerECGObserver(uploader: uploader)
        } catch {
            print("[HealthSyncEngine] ECG background delivery failed: \(error)")
        }
        #endif

        if #available(iOS 18.0, watchOS 11.0, macOS 15.0, *) {
            let stateOfMindType = HKSampleType.stateOfMindType()
            do {
                try await store.enableBackgroundDelivery(for: stateOfMindType, frequency: .hourly)
                registerStateOfMindObserver(uploader: uploader)
            } catch {
                print("[HealthSyncEngine] state-of-mind background delivery failed: \(error)")
            }
        }

        if #available(iOS 18.0, watchOS 11.0, macOS 15.0, *) {
            let gad7Type = Self.gad7AssessmentType
            do {
                try await store.enableBackgroundDelivery(for: gad7Type, frequency: .hourly)
                registerGAD7Observer(uploader: uploader)
            } catch {
                print("[HealthSyncEngine] GAD-7 background delivery failed: \(error)")
            }
            let phq9Type = Self.phq9AssessmentType
            do {
                try await store.enableBackgroundDelivery(for: phq9Type, frequency: .hourly)
                registerPHQ9Observer(uploader: uploader)
            } catch {
                print("[HealthSyncEngine] PHQ-9 background delivery failed: \(error)")
            }
        }

        if #available(iOS 18.0, watchOS 11.0, *),
           let apneaType = HKCategoryType.categoryType(forIdentifier: .sleepApneaEvent) {
            do {
                try await store.enableBackgroundDelivery(for: apneaType, frequency: .hourly)
                registerSleepApneaObserver(uploader: uploader)
            } catch {
                print("[HealthSyncEngine] sleep-apnea background delivery failed: \(error)")
            }
        }

        if #available(iOS 15.0, watchOS 8.0, *),
           let steadinessEventType = HKCategoryType.categoryType(forIdentifier: .appleWalkingSteadinessEvent) {
            do {
                try await store.enableBackgroundDelivery(for: steadinessEventType, frequency: .hourly)
                registerWalkingSteadinessObserver(uploader: uploader)
            } catch {
                print("[HealthSyncEngine] walking-steadiness background delivery failed: \(error)")
            }
        }
    }

    // MARK: - Anchor persistence

    private func anchorKey(for label: String) -> String {
        "beagle.healthsync.anchors.\(label)"
    }

    func loadAnchor(for label: String) -> HKQueryAnchor? {
        guard let data = UserDefaults.standard.data(forKey: anchorKey(for: label)) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    func saveAnchor(_ anchor: HKQueryAnchor, for label: String) {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true) else { return }
        UserDefaults.standard.set(data, forKey: anchorKey(for: label))
    }
}
#endif

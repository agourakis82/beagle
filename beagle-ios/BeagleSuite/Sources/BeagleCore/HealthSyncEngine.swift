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

    public init(
        uuid: String,
        ts: String,
        endTs: String,
        type: String,
        value: Double,
        unit: String,
        source: String,
        device: String?
    ) {
        self.uuid = uuid
        self.ts = ts
        self.endTs = endTs
        self.type = type
        self.value = value
        self.unit = unit
        self.source = source
        self.device = device
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
}

// MARK: - Observer completion box

/// Lets HKObserverQuery's non-Sendable completion handler cross into a Task without
/// tripping Swift 6 'sending' diagnostics. HealthKit guarantees a single call.
private struct SendableObserverCompletion: @unchecked Sendable {
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

    private let store = HKHealthStore()
    // Static + nonisolated so the (nonisolated) HKAnchoredObjectQuery result closures can
    // format dates without crossing actor isolation. ISO8601DateFormatter is thread-safe
    // for formatting, so concurrent reads are safe.
    nonisolated(unsafe) private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private var observerTokens: [String: HKObserverQuery] = [:]
    private var isAuthorized = false

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
    }

    // MARK: - Anchor persistence

    private func anchorKey(for label: String) -> String {
        "beagle.healthsync.anchors.\(label)"
    }

    private func loadAnchor(for label: String) -> HKQueryAnchor? {
        guard let data = UserDefaults.standard.data(forKey: anchorKey(for: label)) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    private func saveAnchor(_ anchor: HKQueryAnchor, for label: String) {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true) else { return }
        UserDefaults.standard.set(data, forKey: anchorKey(for: label))
    }

    // MARK: - HKAnchoredObjectQuery helpers

    private func fetchNewQuantitySamples(
        type: HKQuantityType,
        label: String,
        unit: HKUnit
    ) async throws -> [PhysioHealthSample] {
        let anchor = loadAnchor(for: label)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: type,
                predicate: nil,
                anchor: anchor,
                limit: HKObjectQueryNoLimit
            ) { [weak self] _, added, _, newAnchor, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let self else { continuation.resume(returning: []); return }
                if let newAnchor { Task { await self.saveAnchor(newAnchor, for: label) } }
                let samples = (added as? [HKQuantitySample] ?? []).map { s -> PhysioHealthSample in
                    PhysioHealthSample(
                        uuid: s.uuid.uuidString,
                        ts: Self.iso8601.string(from: s.startDate),
                        endTs: Self.iso8601.string(from: s.endDate),
                        type: label,
                        value: s.quantity.doubleValue(for: unit),
                        unit: unit.unitString,
                        source: s.sourceRevision.source.bundleIdentifier,
                        device: s.device?.name
                    )
                }
                continuation.resume(returning: samples)
            }
            store.execute(query)
        }
    }

    private func fetchNewSleepSamples() async throws -> [PhysioSleepSample] {
        let label = "HKCategoryTypeIdentifierSleepAnalysis"
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }
        let anchor = loadAnchor(for: label)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: type,
                predicate: nil,
                anchor: anchor,
                limit: HKObjectQueryNoLimit
            ) { [weak self] _, added, _, newAnchor, error in
                if let error { continuation.resume(throwing: error); return }
                guard let self else { continuation.resume(returning: []); return }
                if let newAnchor { Task { await self.saveAnchor(newAnchor, for: label) } }
                let samples = (added as? [HKCategorySample] ?? []).map { s in
                    PhysioSleepSample(
                        uuid: s.uuid.uuidString,
                        ts: Self.iso8601.string(from: s.startDate),
                        endTs: Self.iso8601.string(from: s.endDate),
                        type: label,
                        value: s.value,
                        source: s.sourceRevision.source.bundleIdentifier,
                        device: s.device?.name
                    )
                }
                continuation.resume(returning: samples)
            }
            store.execute(query)
        }
    }

    private func fetchNewWorkouts() async throws -> [PhysioWorkoutSample] {
        let label = "HKWorkoutType"
        let type = HKObjectType.workoutType()
        let anchor = loadAnchor(for: label)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: type,
                predicate: nil,
                anchor: anchor,
                limit: HKObjectQueryNoLimit
            ) { [weak self] _, added, _, newAnchor, error in
                if let error { continuation.resume(throwing: error); return }
                guard let self else { continuation.resume(returning: []); return }
                if let newAnchor { Task { await self.saveAnchor(newAnchor, for: label) } }
                let workouts = (added as? [HKWorkout] ?? []).map { w in
                    PhysioWorkoutSample(
                        uuid: w.uuid.uuidString,
                        ts: Self.iso8601.string(from: w.startDate),
                        endTs: Self.iso8601.string(from: w.endDate),
                        type: label,
                        activityType: w.workoutActivityType.rawValue,
                        durationSeconds: w.duration,
                        totalEnergyKcal: w.totalEnergyBurned?.doubleValue(for: .kilocalorie()),
                        totalDistanceMeters: w.totalDistance?.doubleValue(for: .meter()),
                        source: w.sourceRevision.source.bundleIdentifier,
                        device: w.device?.name
                    )
                }
                continuation.resume(returning: workouts)
            }
            store.execute(query)
        }
    }

    // MARK: - Observer registration (HKObserverQuery, background)

    private func registerObserver(
        for type: HKQuantityType,
        label: String,
        unit: HKUnit,
        uploader: PhysiomeUploader
    ) {
        let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completionHandler, error in
            let complete = SendableObserverCompletion(completionHandler)
            guard let self, error == nil else { complete(); return }
            Task {
                do {
                    let samples = try await self.fetchNewQuantitySamples(type: type, label: label, unit: unit)
                    if !samples.isEmpty { await uploader.enqueue(healthSamples: samples) }
                    await uploader.flush()
                } catch {
                    print("[HealthSyncEngine] observer fetch failed for \(label): \(error)")
                }
                complete()
            }
        }
        observerTokens[label] = query
        store.execute(query)
    }

    private func registerSleepObserver(uploader: PhysiomeUploader) {
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return }
        let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completionHandler, error in
            let complete = SendableObserverCompletion(completionHandler)
            guard let self, error == nil else { complete(); return }
            Task {
                do {
                    let samples = try await self.fetchNewSleepSamples()
                    if !samples.isEmpty { await uploader.enqueue(sleepSamples: samples) }
                    await uploader.flush()
                } catch {
                    print("[HealthSyncEngine] sleep observer fetch failed: \(error)")
                }
                complete()
            }
        }
        observerTokens["HKCategoryTypeIdentifierSleepAnalysis"] = query
        store.execute(query)
    }

    private func registerWorkoutObserver(uploader: PhysiomeUploader) {
        let type = HKObjectType.workoutType()
        let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completionHandler, error in
            let complete = SendableObserverCompletion(completionHandler)
            guard let self, error == nil else { complete(); return }
            Task {
                do {
                    let workouts = try await self.fetchNewWorkouts()
                    if !workouts.isEmpty { await uploader.enqueue(workoutSamples: workouts) }
                    await uploader.flush()
                } catch {
                    print("[HealthSyncEngine] workout observer fetch failed: \(error)")
                }
                complete()
            }
        }
        observerTokens["HKWorkoutType"] = query
        store.execute(query)
    }
}
#endif

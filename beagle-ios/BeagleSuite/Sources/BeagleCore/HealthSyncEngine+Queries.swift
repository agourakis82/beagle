//
//  HealthSyncEngine+Queries.swift
//  BeagleCore
//
//  HKAnchoredObjectQuery fetchers, HKObserverQuery background delivery
//  registrations, clinical assessments (State of Mind, GAD-7, PHQ-9), and ECG.
//

import Foundation
#if canImport(HealthKit)
import HealthKit

extension HealthSyncEngine {
    // MARK: - HKAnchoredObjectQuery helpers

    func fetchNewQuantitySamples(
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
                        ts: Self.iso8601String(from: s.startDate),
                        endTs: Self.iso8601String(from: s.endDate),
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

    func fetchNewSleepSamples() async throws -> [PhysioSleepSample] {
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
                        ts: Self.iso8601String(from: s.startDate),
                        endTs: Self.iso8601String(from: s.endDate),
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

    /// Sleep apnea / breathing-disturbance events (Watch, iOS/watchOS 18+/11+). Same shape as
    /// sleep analysis (HKCategorySample) — mirrors fetchNewSleepSamples exactly, different type.
    @available(iOS 18.0, watchOS 11.0, *)
    func fetchNewSleepApneaEvents() async throws -> [PhysioSleepSample] {
        let label = "HKCategoryTypeIdentifierSleepApneaEvent"
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepApneaEvent) else { return [] }
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
                        ts: Self.iso8601String(from: s.startDate),
                        endTs: Self.iso8601String(from: s.endDate),
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

    @available(iOS 18.0, watchOS 11.0, *)
    func registerSleepApneaObserver(uploader: PhysiomeUploader) {
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepApneaEvent) else { return }
        let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completionHandler, error in
            let complete = SendableObserverCompletion(completionHandler)
            guard let self, error == nil else { complete(); return }
            Task {
                do {
                    let samples = try await self.fetchNewSleepApneaEvents()
                    if !samples.isEmpty { await uploader.enqueue(sleepSamples: samples) }
                    await uploader.flush()
                } catch {
                    print("[HealthSyncEngine] sleep-apnea observer fetch failed: \(error)")
                }
                complete()
            }
        }
        observerTokens["HKCategoryTypeIdentifierSleepApneaEvent"] = query
        store.execute(query)
    }

    /// Fall-risk / walking-steadiness-decline events (iOS 15+). Same HKCategorySample shape
    /// as sleep apnea — mirrors fetchNewSleepApneaEvents exactly, different type.
    @available(iOS 15.0, watchOS 8.0, *)
    func fetchNewWalkingSteadinessEvents() async throws -> [PhysioSleepSample] {
        let label = "HKCategoryTypeIdentifierAppleWalkingSteadinessEvent"
        guard let type = HKCategoryType.categoryType(forIdentifier: .appleWalkingSteadinessEvent) else { return [] }
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
                        ts: Self.iso8601String(from: s.startDate),
                        endTs: Self.iso8601String(from: s.endDate),
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

    @available(iOS 15.0, watchOS 8.0, *)
    func registerWalkingSteadinessObserver(uploader: PhysiomeUploader) {
        guard let type = HKCategoryType.categoryType(forIdentifier: .appleWalkingSteadinessEvent) else { return }
        let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completionHandler, error in
            let complete = SendableObserverCompletion(completionHandler)
            guard let self, error == nil else { complete(); return }
            Task {
                do {
                    let samples = try await self.fetchNewWalkingSteadinessEvents()
                    if !samples.isEmpty { await uploader.enqueue(sleepSamples: samples) }
                    await uploader.flush()
                } catch {
                    print("[HealthSyncEngine] walking-steadiness observer fetch failed: \(error)")
                }
                complete()
            }
        }
        observerTokens["HKCategoryTypeIdentifierAppleWalkingSteadinessEvent"] = query
        store.execute(query)
    }

    func fetchNewWorkouts() async throws -> [PhysioWorkoutSample] {
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
                        ts: Self.iso8601String(from: w.startDate),
                        endTs: Self.iso8601String(from: w.endDate),
                        type: label,
                        activityType: w.workoutActivityType.rawValue,
                        durationSeconds: w.duration,
                        totalEnergyKcal: w.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie()),
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

    /// HKStateOfMind (mood/valence, iOS 18+) — authorization was already requested (line ~202)
    /// but this engine never actually fetched/uploaded it; `correlate.mjs`'s `mood` outcome has
    /// been null the whole time because nothing reached `health_samples`, not because the
    /// server-side digest was broken. Mirrors fetchNewSleepSamples/fetchNewWorkouts (a distinct
    /// HKSampleType, not a plain quantity type, so it needs its own fetch like sleep/workouts do).
    @available(iOS 18.0, watchOS 11.0, macOS 15.0, *)
    func fetchNewStateOfMind() async throws -> [PhysioHealthSample] {
        let label = "HKStateOfMindType"
        let type = HKSampleType.stateOfMindType()
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
                let samples = (added as? [HKStateOfMind] ?? []).map { s -> PhysioHealthSample in
                    PhysioHealthSample(
                        uuid: s.uuid.uuidString,
                        ts: Self.iso8601String(from: s.startDate),
                        endTs: Self.iso8601String(from: s.endDate),
                        type: label,
                        value: s.valence,
                        unit: "valence",
                        source: s.sourceRevision.source.bundleIdentifier,
                        device: s.device?.name,
                        metadata: ["kind": String(describing: s.kind)]
                    )
                }
                continuation.resume(returning: samples)
            }
            store.execute(query)
        }
    }

    @available(iOS 18.0, watchOS 11.0, macOS 15.0, *)
    func registerStateOfMindObserver(uploader: PhysiomeUploader) {
        let type = HKSampleType.stateOfMindType()
        let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completionHandler, error in
            let complete = SendableObserverCompletion(completionHandler)
            guard let self, error == nil else { complete(); return }
            Task {
                do {
                    let samples = try await self.fetchNewStateOfMind()
                    if !samples.isEmpty { await uploader.enqueue(healthSamples: samples) }
                    await uploader.flush()
                } catch {
                    print("[HealthSyncEngine] state-of-mind observer fetch failed: \(error)")
                }
                complete()
            }
        }
        observerTokens["HKStateOfMindType"] = query
        store.execute(query)
    }

    /// GAD-7 (anxiety) clinical assessment (iOS 18+) — read-only: the user fills this out via
    /// the Health app's own assessment UI, we only ever read the score/risk it produces.
    @available(iOS 18.0, watchOS 11.0, macOS 15.0, *)
    func fetchNewGAD7Assessments() async throws -> [PhysioHealthSample] {
        let label = "HKGAD7Assessment"
        let type = Self.gad7AssessmentType
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
                let samples = (added as? [HKGAD7Assessment] ?? []).map { s -> PhysioHealthSample in
                    PhysioHealthSample(
                        uuid: s.uuid.uuidString,
                        ts: Self.iso8601String(from: s.startDate),
                        endTs: Self.iso8601String(from: s.endDate),
                        type: label,
                        value: Double(s.score),
                        unit: "score",
                        source: s.sourceRevision.source.bundleIdentifier,
                        device: s.device?.name,
                        metadata: ["risk": String(describing: s.risk)]
                    )
                }
                continuation.resume(returning: samples)
            }
            store.execute(query)
        }
    }

    @available(iOS 18.0, watchOS 11.0, macOS 15.0, *)
    func registerGAD7Observer(uploader: PhysiomeUploader) {
        let type = Self.gad7AssessmentType
        let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completionHandler, error in
            let complete = SendableObserverCompletion(completionHandler)
            guard let self, error == nil else { complete(); return }
            Task {
                do {
                    let samples = try await self.fetchNewGAD7Assessments()
                    if !samples.isEmpty { await uploader.enqueue(healthSamples: samples) }
                    await uploader.flush()
                } catch {
                    print("[HealthSyncEngine] GAD-7 observer fetch failed: \(error)")
                }
                complete()
            }
        }
        observerTokens["HKGAD7Assessment"] = query
        store.execute(query)
    }

    /// PHQ-9 (depression) clinical assessment (iOS 18+) — same read-only pattern as GAD-7.
    @available(iOS 18.0, watchOS 11.0, macOS 15.0, *)
    func fetchNewPHQ9Assessments() async throws -> [PhysioHealthSample] {
        let label = "HKPHQ9Assessment"
        let type = Self.phq9AssessmentType
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
                let samples = (added as? [HKPHQ9Assessment] ?? []).map { s -> PhysioHealthSample in
                    PhysioHealthSample(
                        uuid: s.uuid.uuidString,
                        ts: Self.iso8601String(from: s.startDate),
                        endTs: Self.iso8601String(from: s.endDate),
                        type: label,
                        value: Double(s.score),
                        unit: "score",
                        source: s.sourceRevision.source.bundleIdentifier,
                        device: s.device?.name,
                        metadata: ["risk": String(describing: s.risk)]
                    )
                }
                continuation.resume(returning: samples)
            }
            store.execute(query)
        }
    }

    @available(iOS 18.0, watchOS 11.0, macOS 15.0, *)
    func registerPHQ9Observer(uploader: PhysiomeUploader) {
        let type = Self.phq9AssessmentType
        let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completionHandler, error in
            let complete = SendableObserverCompletion(completionHandler)
            guard let self, error == nil else { complete(); return }
            Task {
                do {
                    let samples = try await self.fetchNewPHQ9Assessments()
                    if !samples.isEmpty { await uploader.enqueue(healthSamples: samples) }
                    await uploader.flush()
                } catch {
                    print("[HealthSyncEngine] PHQ-9 observer fetch failed: \(error)")
                }
                complete()
            }
        }
        observerTokens["HKPHQ9Assessment"] = query
        store.execute(query)
    }

    // MARK: - Observer registration (HKObserverQuery, background)

    func registerObserver(
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

    func registerSleepObserver(uploader: PhysiomeUploader) {
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

    func registerWorkoutObserver(uploader: PhysiomeUploader) {
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

    // MARK: - ECG (Apple Watch electrocardiogram)
    #if os(iOS) || os(watchOS)

    /// ECG is a special sample type (a voltage time-series), not a scalar quantity. We
    /// emit one health_sample per ECG carrying the average heart rate as the value and
    /// the clinically meaningful scalars (classification, symptoms, sampling frequency,
    /// measurement count) in metadata — the raw waveform is intentionally not streamed.
    func fetchNewECG() async throws -> [PhysioHealthSample] {
        let label = "HKElectrocardiogram"
        let type = HKObjectType.electrocardiogramType()
        let anchor = loadAnchor(for: label)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: type, predicate: nil, anchor: anchor, limit: HKObjectQueryNoLimit
            ) { [weak self] _, added, _, newAnchor, error in
                if let error { continuation.resume(throwing: error); return }
                guard let self else { continuation.resume(returning: []); return }
                if let newAnchor { Task { await self.saveAnchor(newAnchor, for: label) } }
                let bpm = HKUnit.count().unitDivided(by: .minute())
                let samples = (added as? [HKElectrocardiogram] ?? []).map { ecg -> PhysioHealthSample in
                    let avg = ecg.averageHeartRate?.doubleValue(for: bpm)
                    var meta: [String: String] = [
                        "classification": Self.ecgClassification(ecg.classification),
                        "symptoms": Self.ecgSymptoms(ecg.symptomsStatus),
                        "num_voltage_measurements": String(ecg.numberOfVoltageMeasurements),
                    ]
                    if let f = ecg.samplingFrequency?.doubleValue(for: .hertz()) {
                        meta["sampling_frequency_hz"] = String(f)
                    }
                    return PhysioHealthSample(
                        uuid: ecg.uuid.uuidString,
                        ts: Self.iso8601String(from: ecg.startDate),
                        endTs: Self.iso8601String(from: ecg.endDate),
                        type: label,
                        value: avg ?? 0,
                        unit: "count/min",
                        source: ecg.sourceRevision.source.bundleIdentifier,
                        device: ecg.device?.name,
                        metadata: meta
                    )
                }
                continuation.resume(returning: samples)
            }
            store.execute(query)
        }
    }

    func registerECGObserver(uploader: PhysiomeUploader) {
        let type = HKObjectType.electrocardiogramType()
        let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completionHandler, error in
            let complete = SendableObserverCompletion(completionHandler)
            guard let self, error == nil else { complete(); return }
            Task {
                do {
                    let ecgs = try await self.fetchNewECG()
                    if !ecgs.isEmpty { await uploader.enqueue(healthSamples: ecgs) }
                    await uploader.flush()
                } catch {
                    print("[HealthSyncEngine] ECG observer fetch failed: \(error)")
                }
                complete()
            }
        }
        observerTokens["HKElectrocardiogram"] = query
        store.execute(query)
    }

    private static func ecgClassification(_ c: HKElectrocardiogram.Classification) -> String {
        switch c {
        case .notSet: return "notSet"
        case .sinusRhythm: return "sinusRhythm"
        case .atrialFibrillation: return "atrialFibrillation"
        case .inconclusiveLowHeartRate: return "inconclusiveLowHeartRate"
        case .inconclusiveHighHeartRate: return "inconclusiveHighHeartRate"
        case .inconclusivePoorReading: return "inconclusivePoorReading"
        case .inconclusiveOther: return "inconclusiveOther"
        case .unrecognized: return "unrecognized"
        @unknown default: return "unknown"
        }
    }

    private static func ecgSymptoms(_ s: HKElectrocardiogram.SymptomsStatus) -> String {
        switch s {
        case .notSet: return "notSet"
        case .none: return "none"
        case .present: return "present"
        @unknown default: return "unknown"
        }
    }
    #endif
}
#endif

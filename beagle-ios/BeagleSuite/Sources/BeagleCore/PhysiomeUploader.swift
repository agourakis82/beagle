//
//  PhysiomeUploader.swift
//  BeagleCore
//
//  Batch uploader for the Beagle Physiome sync layer.
//
//  Collects health samples and weather observations from HealthSyncEngine /
//  WeatherSyncEngine and POSTs them to <base>/api/physiome/ingest as:
//
//    POST /api/physiome/ingest
//    Authorization: Bearer <operator-token>
//    X-Beagle-Consumer: beagle-operator
//    Content-Type: application/json
//
//    {
//      "health_samples": [...],
//      "sleep_samples":  [...],
//      "workout_samples": [...],
//      "weather_obs": [...]
//    }
//
//  Guarantees:
//   • Idempotent by sample UUID — server performs upsert, so retries are safe.
//   • Offline queue — samples are queued in memory and flushed when connectivity
//     resumes. A lightweight file-backed queue survives app restarts (stored under
//     the app's Caches directory, marked excluded-from-backup).
//   • Exponential backoff — first retry after 5 s, doubling up to 5 minutes cap.
//   • Last-acked anchor is NOT managed here; each sync engine owns its own
//     per-type HKQueryAnchor stored in UserDefaults (see HealthSyncEngine).
//
//  Auth: Tokens come from BeagleClient.ensureAuth() (the same cockpit bridge
//  used by all other BeagleClient calls). This uploader shares the client actor
//  to piggyback on the existing token refresh logic.
//

import Foundation

// MARK: - Request / Response models

struct PhysiomeIngestRequest: Codable, Sendable {
    let healthSamples: [PhysioHealthSample]
    let sleepSamples: [PhysioSleepSample]
    let workoutSamples: [PhysioWorkoutSample]
    let weatherObs: [PhysioWeatherObservation]

    enum CodingKeys: String, CodingKey {
        case healthSamples  = "health_samples"
        case sleepSamples   = "sleep_samples"
        case workoutSamples = "workout_samples"
        case weatherObs     = "weather_obs"
    }

    var isEmpty: Bool {
        healthSamples.isEmpty && sleepSamples.isEmpty && workoutSamples.isEmpty && weatherObs.isEmpty
    }
}

struct PhysiomeIngestResponse: Codable, Sendable {
    let accepted: Int?
    let skipped: Int?
    let status: String?
}

// MARK: - Persisted queue entry

private struct QueueEntry: Codable {
    var healthSamples: [PhysioHealthSample]
    var sleepSamples: [PhysioSleepSample]
    var workoutSamples: [PhysioWorkoutSample]
    var weatherObs: [PhysioWeatherObservation]
    var enqueuedAt: Date
    var attemptCount: Int
}

// MARK: - Uploader

/// Actor that manages the offline queue, batching, and HTTP delivery.
/// All public methods are safe to call from any Swift Task context.
public actor PhysiomeUploader {

    // MARK: - Shared

    public static let shared = PhysiomeUploader()

    // MARK: - Configuration

    /// Base retry delay in seconds (doubles on each attempt, capped at maxDelay).
    private let baseRetryDelay: TimeInterval = 5
    private let maxRetryDelay: TimeInterval  = 5 * 60
    private let maxAttempts = 12
    /// Max samples per HTTP POST — keeps each request well under the server's body
    /// limit while letting a millions-strong Watch backlog drain over many requests.
    private let uploadChunkSize = 5000

    // MARK: - In-memory queue

    private var pendingHealth: [PhysioHealthSample]      = []
    private var pendingSleep: [PhysioSleepSample]        = []
    private var pendingWorkouts: [PhysioWorkoutSample]   = []
    private var pendingWeather: [PhysioWeatherObservation] = []

    // MARK: - Flush state

    private var isFlushing = false
    private var retryTask: Task<Void, Never>?
    private var consecutiveFailures = 0

    // MARK: - File-backed persistence (survives process restart)

    private let cacheURL: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = caches.appendingPathComponent("BeaglePhysiome", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("offline_queue.json")
        // Exclude from iCloud backup — transient cache.
        var rv = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? rv.setResourceValues(values)
        return url
    }()

    // MARK: - Enqueue

    public func enqueue(healthSamples: [PhysioHealthSample]) {
        pendingHealth.append(contentsOf: healthSamples)
        persistQueue()
    }

    public func enqueue(sleepSamples: [PhysioSleepSample]) {
        pendingSleep.append(contentsOf: sleepSamples)
        persistQueue()
    }

    public func enqueue(workoutSamples: [PhysioWorkoutSample]) {
        pendingWorkouts.append(contentsOf: workoutSamples)
        persistQueue()
    }

    public func enqueue(weatherObservations: [PhysioWeatherObservation]) {
        pendingWeather.append(contentsOf: weatherObservations)
        persistQueue()
    }

    // MARK: - Flush

    /// Attempt to upload all queued samples. Non-blocking — returns immediately if
    /// a flush is already in progress. A retry task will be scheduled on failure.
    public func flush() {
        guard !isFlushing else { return }
        guard !pendingHealth.isEmpty || !pendingSleep.isEmpty ||
              !pendingWorkouts.isEmpty || !pendingWeather.isEmpty else { return }
        isFlushing = true
        Task { await self.performFlush() }
    }

    /// Load persisted queue from disk and schedule a flush. Call on app launch
    /// to recover items queued during a previous session.
    public func recoverAndFlush() {
        loadPersistedQueue()
        flush()
    }

    // MARK: - Internal flush

    private func performFlush() async {
        defer { isFlushing = false }

        // Drain the queue one bounded chunk at a time. A whole-queue POST can be huge
        // (a fresh Watch catch-up is millions of samples) and would blow the server's
        // body limit; chunking keeps each request small and lets a big backlog drain
        // over many requests. Each chunk takes from the FRONT (oldest first) and is
        // only removed after the server ACKs it, so a crash mid-drain loses nothing.
        while !pendingHealth.isEmpty || !pendingSleep.isEmpty ||
              !pendingWorkouts.isEmpty || !pendingWeather.isEmpty {

            var room = uploadChunkSize
            let h  = Array(pendingHealth.prefix(room));   room -= h.count
            let sl = Array(pendingSleep.prefix(max(0, room)));   room -= sl.count
            let w  = Array(pendingWorkouts.prefix(max(0, room))); room -= w.count
            let we = Array(pendingWeather.prefix(max(0, room)))

            let chunk = PhysiomeIngestRequest(healthSamples: h, sleepSamples: sl, workoutSamples: w, weatherObs: we)

            do {
                try await upload(batch: chunk)
                // ACKed — drop exactly this chunk from the front (enqueue only appends,
                // so the front items are unchanged across the await).
                pendingHealth.removeFirst(h.count)
                pendingSleep.removeFirst(sl.count)
                pendingWorkouts.removeFirst(w.count)
                pendingWeather.removeFirst(we.count)
                persistQueue()
                consecutiveFailures = 0
                let left = pendingHealth.count + pendingSleep.count + pendingWorkouts.count + pendingWeather.count
                print("[PhysiomeUploader] flushed chunk \(h.count)h+\(sl.count)s+\(w.count)w+\(we.count)wx (\(left) remaining)")
            } catch {
                // Leave the queue intact (nothing removed) and back off.
                persistQueue()
                consecutiveFailures += 1
                let delay = min(baseRetryDelay * pow(2.0, Double(consecutiveFailures - 1)), maxRetryDelay)
                print("[PhysiomeUploader] chunk upload failed (\(consecutiveFailures) failures), retrying in \(Int(delay))s: \(error)")
                if consecutiveFailures <= maxAttempts {
                    scheduleRetry(after: delay)
                } else {
                    print("[PhysiomeUploader] max retry attempts reached, will retry on next flush() call")
                }
                return
            }
        }
    }

    private func scheduleRetry(after delay: TimeInterval) {
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.flush()
        }
    }

    // MARK: - HTTP upload

    private func upload(batch: PhysiomeIngestRequest) async throws {
        // Piggyback BeagleClient's auth token (shared actor, zero duplication).
        let authReady = await BeagleClient.shared.ensureAuth()
        guard authReady else {
            throw PhysiomeUploaderError.authFailed
        }

        let result = await BeagleClient.shared.postEncoded(
            PhysiomeIngestResponse.self,
            path: "/api/physiome/ingest",
            body: batch,
            timeout: 60
        )

        switch result.mode {
        case .observed:
            return // success
        default:
            throw PhysiomeUploaderError.uploadFailed(result.error ?? "unknown error")
        }
    }

    // MARK: - Queue persistence

    private func persistQueue() {
        let entry = QueueEntry(
            healthSamples:  pendingHealth,
            sleepSamples:   pendingSleep,
            workoutSamples: pendingWorkouts,
            weatherObs:     pendingWeather,
            enqueuedAt:     Date(),
            attemptCount:   consecutiveFailures
        )
        do {
            let data = try JSONEncoder().encode(entry)
            try data.write(to: cacheURL, options: .atomic)
        } catch {
            print("[PhysiomeUploader] queue persist failed: \(error)")
        }
    }

    private func loadPersistedQueue() {
        guard FileManager.default.fileExists(atPath: cacheURL.path) else { return }
        do {
            let data = try Data(contentsOf: cacheURL)
            let entry = try JSONDecoder().decode(QueueEntry.self, from: data)
            // Prepend (older items first).
            pendingHealth   = entry.healthSamples  + pendingHealth
            pendingSleep    = entry.sleepSamples   + pendingSleep
            pendingWorkouts = entry.workoutSamples + pendingWorkouts
            pendingWeather  = entry.weatherObs     + pendingWeather
            print("[PhysiomeUploader] recovered \(pendingHealth.count) health + \(pendingSleep.count) sleep + \(pendingWorkouts.count) workouts + \(pendingWeather.count) weather samples from disk")
        } catch {
            print("[PhysiomeUploader] failed to load persisted queue: \(error)")
        }
    }

    private func clearPersistedQueue() {
        try? FileManager.default.removeItem(at: cacheURL)
    }
}

// MARK: - Errors

public enum PhysiomeUploaderError: LocalizedError {
    case authFailed
    case uploadFailed(String)

    public var errorDescription: String? {
        switch self {
        case .authFailed:
            return "Physiome uploader: auth token unavailable"
        case .uploadFailed(let msg):
            return "Physiome uploader: \(msg)"
        }
    }
}


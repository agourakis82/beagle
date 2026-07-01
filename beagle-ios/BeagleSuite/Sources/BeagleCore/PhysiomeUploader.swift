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

    /// Base URLs tried in order for /api/physiome/ingest.
    ///  1. Public gateway (https://beagle.chiuratto.ai) — reachable from any device;
    ///     routes to physiome-ingest.beagle.svc.cluster.local:8080 via cockpit proxy.
    ///  2. Direct in-cluster path — used when the app runs inside the cluster network.
    private let physiomeBaseURLs: [URL] = [
        URL(string: "https://beagle.chiuratto.ai")!,
        URL(string: "http://physiome-ingest.beagle.svc.cluster.local:8080")!
    ]

    /// Cockpit auth-bridge endpoints — same list as BeagleClient.ensureAuth().
    private let physAuthBridgeURLs: [URL] = [
        URL(string: "https://beagle.chiuratto.ai")!,
        URL(string: "http://sounio-cockpit.tail21cbc4.ts.net")!,
        URL(string: "http://project-cockpit.beagle.svc.cluster.local")!
    ]

    /// Dedicated URLSession for physiome uploads (separate connection pool from
    /// BeagleClient so token negotiation timeouts don't stall ongoing health-data drains).
    private let physSession: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.waitsForConnectivity = true
        return URLSession(configuration: cfg)
    }()

    /// Operator token cached locally for direct POST to physiome-ingest.
    /// Re-fetched on nil or on 401 from the ingest service.
    private var physToken: String?
    private var physConsumerId: String = "beagle-operator"

    /// Fetch the operator token from the cockpit auth bridge and cache it locally.
    /// Mirrors the token-fetch logic in BeagleClient.ensureAuth() so the uploader
    /// can attach the same Authorization header to the direct physiome-ingest POST.
    private func refreshPhysiomeToken() async {
        for base in physAuthBridgeURLs {
            guard let url = URL(string: "/api/auth/beagle-token", relativeTo: base) else { continue }
            var authRequest = URLRequest(url: url)
            authRequest.setValue(BeagleClient.cockpitMobileToken, forHTTPHeaderField: "x-cockpit-token")
            guard let (data, resp) = try? await physSession.data(for: authRequest),
                  let http = resp as? HTTPURLResponse, http.statusCode == 200 else { continue }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let rawToken = json["token"] as? String
            let authHeader = json["auth_header_value"] as? String
            if let rawToken, !rawToken.isEmpty {
                physToken = rawToken
            } else if let authHeader, authHeader.hasPrefix("Bearer "),
                      authHeader.count > "Bearer ".count {
                physToken = String(authHeader.dropFirst("Bearer ".count))
            }
            if let cv = (json["consumer_header_value"] as? String ?? json["consumer"] as? String),
               !cv.isEmpty {
                physConsumerId = cv
            }
            if physToken != nil {
                print("[PhysiomeUploader] refreshPhysiomeToken ✅ acquired via \(base.host ?? base.absoluteString)")
                return
            }
        }
        print("[PhysiomeUploader] refreshPhysiomeToken ⚠️  all auth-bridge endpoints failed")
    }

    private func upload(batch: PhysiomeIngestRequest) async throws {
        // Step 1: Piggyback BeagleClient's auth bootstrap to confirm the auth bridge
        // is reachable and the token is still valid (reuses the same accessor as before).
        let authReady = await BeagleClient.shared.ensureAuth()
        guard authReady else {
            throw PhysiomeUploaderError.authFailed
        }

        // Step 2: Ensure we hold a local copy of the operator token for the direct POST.
        // (BeagleClient caches the token internally in its actor; this uploader maintains
        // its own copy so it can attach it to requests that bypass BeagleClient's URL list.)
        if physToken == nil {
            await refreshPhysiomeToken()
        }
        guard let token = physToken else {
            throw PhysiomeUploaderError.authFailed
        }

        // Step 3: Encode the ingest payload.
        let payload: Data
        do {
            payload = try JSONEncoder().encode(batch)
        } catch {
            throw PhysiomeUploaderError.uploadFailed("encode: \(error.localizedDescription)")
        }

        // Step 4: POST directly to physiome-ingest, trying each base URL in order.
        // The gateway at beagle.chiuratto.ai validates the operator token and forwards
        // to physiome-ingest.beagle.svc.cluster.local:8080/api/physiome/ingest.
        var lastError = "physiome-ingest unreachable on all endpoints"
        for base in physiomeBaseURLs {
            guard let url = URL(string: "/api/physiome/ingest", relativeTo: base) else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(physConsumerId, forHTTPHeaderField: "X-Beagle-Consumer")
            request.setValue(BeagleClient.cockpitMobileToken, forHTTPHeaderField: "x-cockpit-token")
            request.timeoutInterval = 60
            request.httpBody = payload
            do {
                let (data, response) = try await physSession.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    lastError = "non-HTTP response from \(base.host ?? base.absoluteString)"
                    continue
                }
                if http.statusCode == 401 {
                    // Token may be stale — refresh once and retry this same URL.
                    physToken = nil
                    await refreshPhysiomeToken()
                    guard let refreshed = physToken else {
                        throw PhysiomeUploaderError.authFailed
                    }
                    var retryReq = request
                    retryReq.setValue("Bearer \(refreshed)", forHTTPHeaderField: "Authorization")
                    let (_, retryResp) = try await physSession.data(for: retryReq)
                    guard let retryHttp = retryResp as? HTTPURLResponse,
                          (200..<300).contains(retryHttp.statusCode) else {
                        lastError = "HTTP \((retryResp as? HTTPURLResponse)?.statusCode ?? 0) (post-refresh)"
                        continue
                    }
                    print("[PhysiomeUploader] upload ✅ \(base.host ?? "") (after token refresh)")
                    return
                }
                guard (200..<300).contains(http.statusCode) else {
                    let bodyText = String(data: data, encoding: .utf8)?.prefix(200) ?? "<empty>"
                    lastError = "HTTP \(http.statusCode) from \(base.host ?? ""): \(bodyText)"
                    continue
                }
                print("[PhysiomeUploader] upload ✅ \(base.host ?? "")")
                return
            } catch {
                lastError = error.localizedDescription
                continue
            }
        }
        throw PhysiomeUploaderError.uploadFailed(lastError)
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


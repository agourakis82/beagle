//
//  DrivingSyncEngine.swift
//  BeagleCore
//
//  Driving-time capture for the Beagle Physiome foundation — the pragmatic substitute for
//  CarPlay/Waze trip data.
//
//  Investigated and confirmed infeasible: a CarPlay entitlement is restricted by Apple to
//  one exclusive app category (Audio/Communication/EV-Charging/Navigation/Parking/Food
//  ordering) that a personal data-logging app doesn't fit; Waze has no public API for a
//  third-party app to read a user's own trip history. CMMotionActivityManager's `.automotive`
//  state needs no special entitlement and gives a rough "was probably driving, ~how long"
//  signal instead — noisier (can misclassify as Unknown/Walking at low speed), but a real,
//  buildable proxy. This is NOT a trip/route log.
//
//  Privacy string required (already in project.yml, shared with BaroSyncEngine):
//  NSMotionUsageDescription.
//

import Foundation

#if os(iOS)
import CoreMotion

/// Actor that owns the CMMotionActivityManager and streams driving-session duration into
/// PhysiomeUploader. Mirrors BaroSyncEngine/AQISyncEngine's actor lifecycle exactly.
public actor DrivingSyncEngine {

    public static let shared = DrivingSyncEngine()

    private let activityManager = CMMotionActivityManager()
    private var uploader: PhysiomeUploader?
    private var driveStartedAt: Date?
    private var isRunning = false

    /// Drives shorter than this are dropped — filters isolated automotive-state
    /// misclassification blips rather than real trips.
    private static let minDriveMinutes: Double = 1.0

    nonisolated(unsafe) private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private init() {}

    /// Begin streaming automotive-activity transitions. No-op if unavailable or already
    /// running. Idempotent.
    public func start(uploader: PhysiomeUploader) {
        guard !isRunning else { return }
        guard CMMotionActivityManager.isActivityAvailable() else {
            print("[DrivingSyncEngine] motion activity unavailable on this device")
            return
        }
        self.uploader = uploader
        isRunning = true
        activityManager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let self, let activity else { return }
            // Extract Sendable fields synchronously — CMMotionActivity itself isn't Sendable,
            // so it can't cross into the actor-isolated Task below.
            let isDriving = activity.automotive && activity.confidence != .low
            let startDate = activity.startDate
            Task { await self.handleActivityUpdate(isDriving: isDriving, startDate: startDate) }
        }
    }

    public func stop() {
        activityManager.stopActivityUpdates()
        isRunning = false
    }

    private func handleActivityUpdate(isDriving: Bool, startDate: Date) async {
        if isDriving {
            if driveStartedAt == nil { driveStartedAt = startDate }
            return
        }
        guard let started = driveStartedAt else { return }
        driveStartedAt = nil
        let endedAt = Date()
        let minutes = endedAt.timeIntervalSince(started) / 60.0
        guard minutes >= Self.minDriveMinutes, let uploader else { return }

        let sample = PhysioHealthSample(
            uuid: UUID().uuidString,
            ts: Self.iso8601.string(from: started),
            endTs: Self.iso8601.string(from: endedAt),
            type: "DrivingAutomotiveMinutes",
            value: minutes,
            unit: "min",
            source: "com.beagle.cockpit",
            device: "iPhone (CMMotionActivityManager)"
        )
        await uploader.enqueue(healthSamples: [sample])
        await uploader.flush()
    }
}
#endif

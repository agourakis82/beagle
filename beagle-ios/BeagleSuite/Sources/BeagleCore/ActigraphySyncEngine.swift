//
//  ActigraphySyncEngine.swift
//  BeagleCore
//
//  Actigraphy complexity capture for the Beagle Physiome foundation — DFA-alpha and sample
//  entropy over raw accelerometer, not raw step counts. This mirrors the N-of-1
//  relapse-prediction methodology (Scientific Reports 2023, n=277): per-patient LSTM models
//  trained on DFA/sample-entropy features from wrist actigraphy caught depressive relapse
//  2-3 weeks early. This engine only produces the daily complexity scalars — the predictive
//  modeling itself is future work once enough days of data exist.
//
//  CMSensorRecorder retains only ~3 days of raw accelerometer on-device, so the app MUST
//  wake and pull the buffer at least every ~2 days or data is silently lost. Two triggers:
//  a foreground opportunistic pull (same lifecycle hook as HealthSyncEngine.catchUp) and a
//  BGAppRefreshTask for when the app isn't opened for a while (registered by the caller;
//  see runBackgroundRefresh(uploader:) below for the task's actual work).
//
//  Privacy string required: same NSMotionUsageDescription already used by
//  BaroSyncEngine/DrivingSyncEngine — no new entitlement.
//

import Foundation

#if os(iOS)
import CoreMotion

/// Actor that owns the CMSensorRecorder pull/DSP pipeline. Unlike BaroSyncEngine/
/// AQISyncEngine (which stream continuously), this engine is invoked opportunistically —
/// call `pullAndProcess(uploader:)` on foreground and from a BGAppRefreshTask handler.
public actor ActigraphySyncEngine {

    public static let shared = ActigraphySyncEngine()

    private let recorder = CMSensorRecorder()
    private var lastProcessedThrough: Date?

    /// One epoch = 60s of raw accelerometer, matching the actigraphy-complexity literature's
    /// standard resolution.
    private static let epochSeconds: TimeInterval = 60
    /// CMSensorRecorder's native accelerometer rate (fixed by the hardware, ~50Hz on iPhone).
    private static let approxSampleRate: Double = 50

    nonisolated(unsafe) private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private init() {}

    /// Ensures the recorder is actively capturing (idempotent — safe to call repeatedly).
    /// Requests the maximum single-shot duration (36h); call this periodically (foreground +
    /// background refresh) to keep the recording window rolling forward.
    public func ensureRecording() {
        guard CMSensorRecorder.isAccelerometerRecordingAvailable() else {
            print("[ActigraphySyncEngine] accelerometer recording unavailable on this device")
            return
        }
        recorder.recordAccelerometer(forDuration: 36 * 3600)
    }

    /// Read back whatever's been recorded since the last pull, compute daily DFA/SampEn per
    /// UTC day represented in the batch, and upload one scalar pair per day. Best-effort:
    /// CMSensorRecorder data can be sparse/gappy (only records while the device has been
    /// recently in motion in some conditions), so days with too few epochs are skipped
    /// rather than reported with a misleading value.
    public func pullAndProcess(uploader: PhysiomeUploader) async {
        ensureRecording()
        guard CMSensorRecorder.isAccelerometerRecordingAvailable() else { return }

        // CMSensorRecorder throws an uncaught NSException ("startTime must be within 3 days
        // of today") — not a Swift-catchable error — if `from` is at or past the 3-day
        // boundary by the time it actually validates the request. A 2-day lookback leaves
        // enough margin for that gap; the ~2-day BGTask/foreground cadence already keeps
        // `lastProcessedThrough` fresher than this in normal operation.
        let from = lastProcessedThrough ?? Date().addingTimeInterval(-2 * 24 * 3600)
        let to = Date()
        guard to.timeIntervalSince(from) > Self.epochSeconds else { return }

        guard let data = recorder.accelerometerData(from: from, to: to) else { return }
        let byDay = Self.bucketMagnitudesByDay(data)
        lastProcessedThrough = to
        guard !byDay.isEmpty else { return }

        let samplesPerEpoch = Int(Self.approxSampleRate * Self.epochSeconds)
        var samples: [PhysioHealthSample] = []
        let dayFormatter = Self.makeDayFormatter()

        for (day, magnitudes) in byDay {
            let epochs = ActigraphyDSP.epochActivityCounts(magnitudes: magnitudes, samplesPerEpoch: samplesPerEpoch)
            // Skip days with too little coverage for a meaningful daily complexity estimate.
            guard epochs.count >= 360 else { continue } // ~6h of epochs minimum
            guard let dayDate = dayFormatter.date(from: day) else { continue }
            let ts = Self.iso8601.string(from: dayDate)

            if let alpha = ActigraphyDSP.dfaAlpha(series: epochs) {
                samples.append(PhysioHealthSample(
                    uuid: UUID().uuidString, ts: ts, endTs: ts, type: "ActigraphyDfaAlpha",
                    value: alpha, unit: "alpha", source: "com.beagle.cockpit",
                    device: "iPhone (CMSensorRecorder)"
                ))
            }
            if let entropy = ActigraphyDSP.sampleEntropy(series: epochs) {
                samples.append(PhysioHealthSample(
                    uuid: UUID().uuidString, ts: ts, endTs: ts, type: "ActigraphySampleEntropy",
                    value: entropy, unit: "nats", source: "com.beagle.cockpit",
                    device: "iPhone (CMSensorRecorder)"
                ))
            }
        }

        guard !samples.isEmpty else { return }
        await uploader.enqueue(healthSamples: samples)
        await uploader.flush()
    }

    private static func makeDayFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }

    /// Bucket raw magnitude samples by UTC day. Synchronous (not async) because
    /// NSFastEnumerationIterator — needed since CMSensorDataList only adopts
    /// NSFastEnumeration, not Swift's Sequence — is unavailable from async contexts.
    private static func bucketMagnitudesByDay(_ data: CMSensorDataList) -> [String: [Double]] {
        let dayFormatter = makeDayFormatter()
        var byDay: [String: [Double]] = [:]
        var iterator = NSFastEnumerationIterator(data)
        while let item = iterator.next() {
            guard let accel = item as? CMRecordedAccelerometerData else { continue }
            let ax = accel.acceleration.x
            let ay = accel.acceleration.y
            let az = accel.acceleration.z
            let sumSquares: Double = ax * ax + ay * ay + az * az
            let magnitude: Double = sumSquares.squareRoot()
            let day = dayFormatter.string(from: accel.startDate)
            byDay[day, default: []].append(magnitude)
        }
        return byDay
    }
}
#endif

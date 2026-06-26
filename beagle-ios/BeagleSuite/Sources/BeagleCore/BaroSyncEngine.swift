//
//  BaroSyncEngine.swift
//  BeagleCore
//
//  Device-barometer pressure capture for the Beagle Physiome foundation.
//
//  The iPhone's built-in barometer (via CoreMotion's CMAltimeter) reports the EXACT
//  local atmospheric pressure where you are — it works indoors, needs no network, and
//  updates continuously. That is a sharper physiological input than WeatherKit's
//  station-modelled pressure, so we stream it into weather_obs alongside the WeatherKit
//  observations (which still carry temp/humidity/UV/condition).
//
//  Barometer readings are geo-tagged with the most recent location forwarded from
//  WeatherSyncEngine (weather_obs PK is ts+lat+lon), and throttled so we record real
//  pressure transitions without bloating the table with redundant rows.
//
//  Privacy string required (already in project.yml): NSMotionUsageDescription.
//

import Foundation

// MARK: - Pure math (platform-independent, unit-tested)

/// Throttle + unit logic for barometer sampling. Free of CoreMotion so it can be
/// unit-tested on any platform.
public enum BaroMath {
    /// CMAltitudeData.pressure is in kilopascals; weather_obs stores hectopascals.
    public static func hPa(fromKPa kPa: Double) -> Double { kPa * 10.0 }

    /// Emit a new observation only when enough time has elapsed OR the pressure has
    /// moved meaningfully — keeps weather_obs from bloating with redundant rows while
    /// still capturing real pressure-front transitions promptly.
    public static func shouldEmit(
        elapsed: TimeInterval,
        deltaHpa: Double,
        minInterval: TimeInterval = 120,
        minDeltaHpa: Double = 0.2
    ) -> Bool {
        elapsed >= minInterval || abs(deltaHpa) >= minDeltaHpa
    }
}

#if os(iOS)
import CoreMotion

/// Actor that owns the CMAltimeter and streams local pressure into PhysiomeUploader.
public actor BaroSyncEngine {

    public static let shared = BaroSyncEngine()

    private let altimeter = CMAltimeter()
    private var uploader: PhysiomeUploader?
    private var lastLocation: (lat: Double, lon: Double)?
    private var lastEmitAt: Date?
    private var lastPressureHpa: Double?
    private var isRunning = false

    nonisolated(unsafe) private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private init() {}

    /// Most recent device location, forwarded from WeatherSyncEngine so barometer rows
    /// are geo-tagged to where you are.
    public func noteLocation(lat: Double, lon: Double) {
        lastLocation = (lat, lon)
    }

    /// Begin streaming barometric pressure. No-op if the device has no barometer or if
    /// already running. Idempotent.
    public func start(uploader: PhysiomeUploader) {
        guard !isRunning else { return }
        guard CMAltimeter.isRelativeAltitudeAvailable() else {
            print("[BaroSyncEngine] barometer unavailable on this device")
            return
        }
        self.uploader = uploader
        isRunning = true
        altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, error in
            guard let self, let data, error == nil else { return }
            let kPa = data.pressure.doubleValue   // CMAltitudeData.pressure is kPa
            Task { await self.handlePressure(kPa: kPa) }
        }
    }

    public func stop() {
        altimeter.stopRelativeAltitudeUpdates()
        isRunning = false
    }

    private func handlePressure(kPa: Double) async {
        guard let loc = lastLocation else { return } // wait for a location to tag
        let hPa = BaroMath.hPa(fromKPa: kPa)
        let elapsed = lastEmitAt.map { Date().timeIntervalSince($0) } ?? .greatestFiniteMagnitude
        let delta = lastPressureHpa.map { hPa - $0 } ?? .greatestFiniteMagnitude
        guard BaroMath.shouldEmit(elapsed: elapsed, deltaHpa: delta) else { return }
        lastEmitAt = Date()
        lastPressureHpa = hPa

        let obs = PhysioWeatherObservation(
            ts: Self.iso8601.string(from: Date()),
            lat: loc.lat,
            lon: loc.lon,
            tempC: nil,
            pressureHpa: hPa,
            humidityPct: nil,
            uvIndex: nil,
            precipMm: nil,
            condition: "barometer",
            windKph: nil,
            dewPointC: nil,
            visibilityKm: nil
        )
        guard let uploader else { return }
        await uploader.enqueue(weatherObservations: [obs])
        await uploader.flush()
    }
}
#endif

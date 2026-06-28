//
//  SpaceWeatherStore.swift
//  BeagleCore
//
//  Live geomagnetic state for the AuroraPresence: Kp index, F10.7 solar flux,
//  solar wind speed, IMF Bz. Reads /api/physiome/space-weather/latest from the
//  cluster (the NOAA SWPC poller writes a fresh row every 2h). Polls every 30min
//  while the app is foregrounded; falls back to a calm placeholder if unreachable.
//
//  Used by ChatScreen → AuroraPresence to modulate intensity (Kp >= 5 = active
//  storm → aurora saturates and breathes faster) and palette (high solar wind →
//  more violet/pink in the gradient).
//

import Foundation
import Observation

@MainActor
@Observable
public final class SpaceWeatherStore {
    public struct Snapshot: Sendable, Equatable {
        public let ts: Date
        public let kp: Double           // 0–9, current 3-hourly index
        public let f107: Double         // solar flux, sfu
        public let solarWindSpeed: Double  // km/s
        public let bz: Double           // IMF Bz, nT (negative = active)
        public let source: String
        public init(ts: Date, kp: Double, f107: Double, solarWindSpeed: Double, bz: Double, source: String) {
            self.ts = ts; self.kp = kp; self.f107 = f107
            self.solarWindSpeed = solarWindSpeed; self.bz = bz; self.source = source
        }
    }

    /// The most recent observed snapshot. nil until the first successful fetch.
    public private(set) var latest: Snapshot?

    /// Convenience: Kp normalized 0…1 (quiet ≤ 2 → 0; storm ≥ 6 → 1).
    public var kpIntensity: Double {
        guard let k = latest?.kp else { return 0.15 }   // gentle default
        return max(0, min(1, (k - 2) / 4))
    }

    /// Convenience: is geomagnetic storm in progress (G1+ = Kp ≥ 5).
    public var isStorm: Bool { (latest?.kp ?? 0) >= 5 }

    private let client: BeagleClient
    private var pollTask: Task<Void, Never>?
    private let pollIntervalSeconds: UInt64 = 30 * 60   // 30min

    public init(client: BeagleClient = .shared) {
        self.client = client
    }

    /// Start polling on app foreground. Idempotent.
    public func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: (self?.pollIntervalSeconds ?? 1800) * 1_000_000_000)
            }
        }
    }

    /// Stop polling on background.
    public func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Manual one-shot refresh.
    public func refresh() async {
        guard let snap = await client.fetchLatestSpaceWeather() else { return }
        self.latest = snap
    }
}

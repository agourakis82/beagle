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
        public let dst: Double?         // Dst storm-time index, nT (more negative = deeper storm)
        public let f107: Double         // solar flux, sfu
        public let solarWindSpeed: Double  // km/s
        public let bz: Double           // IMF Bz, nT (negative = active)
        public let source: String
        public init(ts: Date, kp: Double, dst: Double? = nil, f107: Double, solarWindSpeed: Double, bz: Double, source: String) {
            self.ts = ts; self.kp = kp; self.dst = dst; self.f107 = f107
            self.solarWindSpeed = solarWindSpeed; self.bz = bz; self.source = source
        }
        /// Named band — severity is the worst of Kp and Dst (Dst weighs as much as Kp).
        public var band: SkyBand { SkyBand.from(kp: kp, dst: dst) }
    }

    /// The most recent observed snapshot. nil until the first successful fetch.
    public private(set) var latest: Snapshot?

    /// Convenience: Kp normalized 0…1 (quiet ≤ 2 → 0; storm ≥ 6 → 1).
    public var kpIntensity: Double {
        guard let k = latest?.kp else { return 0.15 }   // gentle default
        return max(0, min(1, (k - 2) / 4))
    }

    /// Convenience: is geomagnetic storm in progress — Kp ≥ 5 (G1+) OR Dst ≤ −50 nT.
    public var isStorm: Bool {
        guard let l = latest else { return false }
        if l.kp >= 5 { return true }
        if let d = l.dst, d <= -50 { return true }
        return false
    }

    /// Current named band for surfaces that speak the sky (strip badge, detail screen).
    public var band: SkyBand { latest?.band ?? .calm }

    private let client: BeagleClient
    private var pollTask: Task<Void, Never>?
    private let pollIntervalSeconds: UInt64 = 30 * 60   // 30min

    public init(client: BeagleClient = .shared) {
        self.client = client
    }

    /// Start polling on app foreground. Idempotent.
    public func start() {
        guard pollTask == nil else { print("[SpaceWeather] start: already running"); return }
        print("[SpaceWeather] start: launching poll loop")
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
        print("[SpaceWeather] refresh: fetching latest")
        guard let snap = await client.fetchLatestSpaceWeather() else {
            print("[SpaceWeather] refresh: ❌ fetch returned nil")
            return
        }
        print("[SpaceWeather] refresh: ✅ kp=\(snap.kp) wind=\(snap.solarWindSpeed) bz=\(snap.bz)")
        self.latest = snap
    }
}

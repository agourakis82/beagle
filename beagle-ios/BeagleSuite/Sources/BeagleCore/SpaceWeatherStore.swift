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
        public let solarWindSpeed: Double?  // km/s (null when the SWPC feed omits it)
        public let bz: Double?          // IMF Bz, nT (negative = active)
        public let hp30: Double?        // GFZ 30-min geomagnetic (finer than 3-hourly Kp, open-ended)
        public let ap30: Double?        // GFZ ap30 (linear amplitude of Hp30)
        public let hp60: Double?        // GFZ 60-min geomagnetic
        public let cosmicRayOulu: Double?   // NMDB neutron rate, % of baseline (Forbush context)
        public let schumannF1: Double?  // Schumann fundamental ~7.83 Hz, relative amplitude (exploratory)
        public let schumannF2: Double?  // 2nd harmonic ~14.3 Hz
        public let schumannF3: Double?  // 3rd harmonic ~20.8 Hz
        public let xrayFlux: Double?    // GOES 0.1-0.8nm long-channel flux, W/m² (flare class)
        public let protonFlux: Double?  // GOES >=10 MeV integral proton flux, pfu (S-scale)
        public let auroraPower: Double? // OVATION hemispheric power proxy
        public let symH: Double?        // SYM-H ring current, nT (retrospective via OMNI)
        public let aeIndex: Double?     // AE auroral electrojet, nT (retrospective)
        public let source: String
        public init(ts: Date, kp: Double, dst: Double? = nil, f107: Double, solarWindSpeed: Double? = nil, bz: Double? = nil, hp30: Double? = nil, ap30: Double? = nil, hp60: Double? = nil, cosmicRayOulu: Double? = nil, schumannF1: Double? = nil, schumannF2: Double? = nil, schumannF3: Double? = nil, xrayFlux: Double? = nil, protonFlux: Double? = nil, auroraPower: Double? = nil, symH: Double? = nil, aeIndex: Double? = nil, source: String) {
            self.ts = ts; self.kp = kp; self.dst = dst; self.f107 = f107
            self.solarWindSpeed = solarWindSpeed; self.bz = bz
            self.hp30 = hp30; self.ap30 = ap30; self.hp60 = hp60; self.cosmicRayOulu = cosmicRayOulu
            self.schumannF1 = schumannF1; self.schumannF2 = schumannF2; self.schumannF3 = schumannF3
            self.xrayFlux = xrayFlux; self.protonFlux = protonFlux; self.auroraPower = auroraPower
            self.symH = symH; self.aeIndex = aeIndex
            self.source = source
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
        print("[SpaceWeather] refresh: ✅ kp=\(snap.kp) wind=\(snap.solarWindSpeed.map { "\($0)" } ?? "nil") bz=\(snap.bz.map { "\($0)" } ?? "nil")")
        self.latest = snap
    }
}

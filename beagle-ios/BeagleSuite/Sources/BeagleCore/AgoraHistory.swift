//
//  AgoraHistory.swift
//  BeagleCore — recent sky/ambient/body series for the Agora detail screen's trends.
//  Decoded from the cockpit's GET /api/mobile/v1/agora-history.
//

import Foundation

public struct AgoraHistory: Decodable, Sendable {
    public let hours: Int
    public let sky: [SkyPoint]
    public let weather: [WeatherPoint]
    public let hrv: [HrvPoint]
    /// Ambient decibel level (HKQuantityTypeIdentifierEnvironmentalAudioExposure) — Tier 0
    /// of the ambient-audio panorama; just a loudness proxy, no scene classification.
    /// Decoded leniently (missing key → []) so an older/rolled-back server response can't
    /// fail the WHOLE decode and take the sky/weather/HRV charts down with it.
    public let audioDb: [HrvPoint]

    enum CodingKeys: String, CodingKey { case hours, sky, weather, hrv, audioDb }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hours = try c.decode(Int.self, forKey: .hours)
        sky = try c.decode([SkyPoint].self, forKey: .sky)
        weather = try c.decode([WeatherPoint].self, forKey: .weather)
        hrv = try c.decode([HrvPoint].self, forKey: .hrv)
        audioDb = try c.decodeIfPresent([HrvPoint].self, forKey: .audioDb) ?? []
    }
}

// MARK: - Correlations (body × sky × ambient, Spearman + lag scan)

/// Decoded from the cockpit's GET /api/mobile/v1/correlations (proxy to physiome). Exploratory
/// (rank correlation over daily aggregates) — the "afeto" dimension joins once the EMA exists.
public struct PhysioCorrelations: Decodable, Sendable {
    public let ok: Bool?
    public let windowDays: Int?
    public let correlations: [Correlation]?
    public let summary: String?
    enum CodingKeys: String, CodingKey { case ok, correlations, summary; case windowDays = "window_days" }

    public struct Correlation: Decodable, Sendable, Identifiable {
        public let driver: String
        public let outcome: String
        public let rho: Double
        public let lag: Int
        public let n: Int
        public let p: Double?
        public let notable: Bool?
        public var id: String { "\(driver)→\(outcome)@\(lag)" }
    }
}

public struct SkyPoint: Decodable, Sendable, Identifiable {
    public let ts: String
    public let kp: Double?
    public let dst: Double?
    public let solarWindSpeed: Double?
    public let bz: Double?
    public let hp30: Double?
    public let cosmicRayOulu: Double?
    public let schumannF1: Double?
    public let xrayFlux: Double?
    public let protonFlux: Double?
    public let auroraPower: Double?
    public let symH: Double?
    public let aeIndex: Double?
    public var id: String { ts }
    enum CodingKeys: String, CodingKey {
        case ts, kp, dst, bz, hp30
        case solarWindSpeed = "solar_wind_speed"
        case cosmicRayOulu = "cosmic_ray_oulu"
        case schumannF1 = "schumann_f1"
        case xrayFlux = "xray_flux"
        case protonFlux = "proton_flux"
        case auroraPower = "aurora_power"
        case symH = "sym_h"
        case aeIndex = "ae_index"
    }
}

public struct WeatherPoint: Decodable, Sendable, Identifiable {
    public let ts: String
    public let tempC: Double?
    public let pressureHpa: Double?
    public let humidity: Double?
    public let uvIndex: Double?
    public let aqi: Double?
    public let ambientPressureHpa: Double?
    public let altitudeM: Double?
    public let city: String?
    public let place: String?
    public var id: String { ts }
    enum CodingKeys: String, CodingKey {
        case ts, humidity, aqi, city, place
        case tempC = "temp_c"
        case pressureHpa = "pressure_hpa"
        case uvIndex = "uv_index"
        case ambientPressureHpa = "ambient_pressure_hpa"
        case altitudeM = "altitude_m"
    }
}

public struct HrvPoint: Decodable, Sendable, Identifiable {
    public let ts: String
    public let value: Double?
    public var id: String { ts }
}


// --- Forecast (Agora charts forward half): /api/physiome/forecast ---
public struct AgoraForecast: Decodable, Sendable {
    public let weather: [WxForecastPoint]
    public let skyKp: [KpForecastPoint]
    enum CodingKeys: String, CodingKey { case weather; case skyKp = "sky_kp" }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        weather = (try? c.decode([WxForecastPoint].self, forKey: .weather)) ?? []
        skyKp = (try? c.decode([KpForecastPoint].self, forKey: .skyKp)) ?? []
    }
}
public struct WxForecastPoint: Decodable, Sendable, Identifiable {
    public let ts: String
    public let tempC: Double?
    public let uvIndex: Double?
    public let aqi: Double?
    public var id: String { ts }
    enum CodingKeys: String, CodingKey { case ts, aqi; case tempC = "temp_c"; case uvIndex = "uv_index" }
}
public struct KpForecastPoint: Decodable, Sendable, Identifiable {
    public let ts: String
    public let kp: Double?
    public let predicted: Bool
    public var id: String { ts }
}

// MARK: - User-labeled places (home / hospital / hotel / mall / work)
//
// The reverse-geocoder gives a raw POI name ("Hospital Sírio-Libanês"), but for an N-of-1
// experiment what matters is the user's OWN label of a recurring place ("plantão", "minha
// casa"). A LabeledPlace is matched to an observation by radius, and its name overrides the
// POI so every weather/ambient row is tagged with a place the user actually reasons about.
// Persisted locally in UserDefaults (JSON) — never leaves the device except as the resolved
// `place` string already uploaded with each observation.

public struct LabeledPlace: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var category: String   // key into PlaceCategory
    public var lat: Double
    public var lon: Double
    public var radiusM: Double
    public init(id: UUID = UUID(), name: String, category: String, lat: Double, lon: Double, radiusM: Double = 120) {
        self.id = id; self.name = name; self.category = category
        self.lat = lat; self.lon = lon; self.radiusM = radiusM
    }
}

/// The fixed vocabulary the user asked for, each with a glyph + a sensible default name.
public enum PlaceCategory: String, CaseIterable, Sendable {
    case casa, hospital, hotel, shopping, trabalho, outro
    public var label: String {
        switch self {
        case .casa: return "Casa"; case .hospital: return "Hospital"; case .hotel: return "Hotel"
        case .shopping: return "Shopping"; case .trabalho: return "Trabalho"; case .outro: return "Outro"
        }
    }
    public var glyph: String {
        switch self {
        case .casa: return "house.fill"; case .hospital: return "cross.case.fill"; case .hotel: return "bed.double.fill"
        case .shopping: return "bag.fill"; case .trabalho: return "briefcase.fill"; case .outro: return "mappin"
        }
    }
}

/// Thread-safe singleton store. Read from the geocoder (background) + the labeling UI (main),
/// so all access is serialized under a lock. Small (a handful of places) — full rewrite on save.
public final class PlaceLabelStore: @unchecked Sendable {
    public static let shared = PlaceLabelStore()
    private let key = "beagle.labeledPlaces.v1"
    private let lock = NSLock()
    private var cache: [LabeledPlace]

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([LabeledPlace].self, from: data) {
            cache = decoded
        } else { cache = [] }
    }

    public func all() -> [LabeledPlace] { lock.lock(); defer { lock.unlock() }; return cache }

    public func add(_ p: LabeledPlace) {
        lock.lock(); cache.removeAll { $0.id == p.id }; cache.append(p); persist(); lock.unlock()
    }
    public func remove(_ id: UUID) {
        lock.lock(); cache.removeAll { $0.id == id }; persist(); lock.unlock()
    }
    private func persist() { // called under lock
        if let data = try? JSONEncoder().encode(cache) { UserDefaults.standard.set(data, forKey: key) }
    }

    /// Nearest labeled place whose radius contains (lat,lon), or nil. Nearest wins on overlap.
    public func match(lat: Double, lon: Double) -> LabeledPlace? {
        lock.lock(); let places = cache; lock.unlock()
        var best: (LabeledPlace, Double)? = nil
        for p in places {
            let d = Self.haversineMeters(lat, lon, p.lat, p.lon)
            if d <= p.radiusM, best == nil || d < best!.1 { best = (p, d) }
        }
        return best?.0
    }

    /// Great-circle distance in meters (Foundation re-exports the math funcs; no CoreLocation dep).
    public static func haversineMeters(_ aLat: Double, _ aLon: Double, _ bLat: Double, _ bLon: Double) -> Double {
        let R = 6_371_000.0
        let dLat = (bLat - aLat) * .pi / 180, dLon = (bLon - aLon) * .pi / 180
        let la1 = aLat * .pi / 180, la2 = bLat * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(la1) * cos(la2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * R * asin(min(1, sqrt(h)))
    }
}

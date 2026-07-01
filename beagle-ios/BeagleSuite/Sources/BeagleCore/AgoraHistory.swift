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
    public let audioDb: [HrvPoint]
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
    public var id: String { ts }
    enum CodingKeys: String, CodingKey {
        case ts, kp, dst, bz
        case solarWindSpeed = "solar_wind_speed"
    }
}

public struct WeatherPoint: Decodable, Sendable, Identifiable {
    public let ts: String
    public let tempC: Double?
    public let pressureHpa: Double?
    public let humidity: Double?
    public let uvIndex: Double?
    public var id: String { ts }
    enum CodingKeys: String, CodingKey {
        case ts, humidity
        case tempC = "temp_c"
        case pressureHpa = "pressure_hpa"
        case uvIndex = "uv_index"
    }
}

public struct HrvPoint: Decodable, Sendable, Identifiable {
    public let ts: String
    public let value: Double?
    public var id: String { ts }
}

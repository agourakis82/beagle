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

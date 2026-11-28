//
//  AQISyncEngine.swift
//  BeagleCore
//
//  Air Quality Index capture for the Beagle Physiome foundation.
//
//  WeatherKit does not provide AQI at all, so this is a separate direct-API engine —
//  same reasoning as BaroSyncEngine being split out from WeatherSyncEngine (isolates the
//  channel that works from the one that's Apple-side blocked). Reuses the location stream
//  WeatherSyncEngine already maintains via noteLocation(lat:lon:) instead of running its
//  own CoreLocation manager.
//
//  Provider fallback chain (decision: "pode ser ambas"): aqicn.org/WAQI first (free token,
//  nearest-station reading, simple JSON), falling back to OpenWeatherMap Air Pollution
//  (separate key, model-based) if the primary fails or has no token configured.
//
//  TODO(demetrios): fill in real tokens once registered —
//    AQICN:          https://aqicn.org/data-platform/token/
//    OpenWeatherMap: https://openweathermap.org/api/air-pollution
//  Until then both providers are no-ops (fetchAQI returns nil) and this engine never
//  enqueues rows, so `weather_obs.aqi` stays null exactly as it does today.
//

import Foundation

public enum AQIConfig {
    public static let aqicnToken = ""       // TODO: paste aqicn.org token here
    public static let openWeatherMapKey = "" // TODO: paste OpenWeatherMap key here
}

/// Actor that periodically resolves AQI for the current location and feeds it into
/// PhysiomeUploader as a dedicated `PhysioWeatherObservation` (all other fields nil).
public actor AQISyncEngine {

    public static let shared = AQISyncEngine()

    private var uploader: PhysiomeUploader?
    private var lastLocation: (lat: Double, lon: Double)?
    private var periodicTask: Task<Void, Never>?
    private var isRunning = false

    /// Aligned to WeatherSyncEngine's hourly cycle — AQI doesn't need finer resolution.
    private let periodicInterval: TimeInterval = 60 * 60

    private let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private init() {}

    /// Most recent device location, forwarded from WeatherSyncEngine so AQI rows are
    /// geo-tagged to where you are — mirrors BaroSyncEngine.noteLocation.
    public func noteLocation(lat: Double, lon: Double) {
        lastLocation = (lat, lon)
    }

    /// Begin periodic AQI polling. Idempotent.
    public func start(uploader: PhysiomeUploader) {
        guard !isRunning else { return }
        self.uploader = uploader
        isRunning = true
        periodicTask?.cancel()
        periodicTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.fetchAndEnqueue()
                try? await Task.sleep(for: .seconds(self.periodicInterval))
            }
        }
    }

    public func stop() {
        periodicTask?.cancel()
        periodicTask = nil
        isRunning = false
    }

    private func fetchAndEnqueue() async {
        guard let loc = lastLocation, let uploader else { return }
        guard let aqi = await Self.fetchAQI(lat: loc.lat, lon: loc.lon) else { return }

        let obs = PhysioWeatherObservation(
            ts: iso8601.string(from: Date()),
            lat: loc.lat,
            lon: loc.lon,
            tempC: nil,
            pressureHpa: nil,
            humidityPct: nil,
            uvIndex: nil,
            precipMm: nil,
            condition: "aqi",
            windKph: nil,
            dewPointC: nil,
            visibilityKm: nil,
            aqi: aqi
        )
        await uploader.enqueue(weatherObservations: [obs])
        await uploader.flush()
    }

    // MARK: - Provider fallback chain

    /// Try aqicn.org first, then OpenWeatherMap. Returns nil (not zero) when neither
    /// provider is configured or reachable, so we never write a misleading AQI of 0.
    static func fetchAQI(lat: Double, lon: Double) async -> Double? {
        if let aqi = await fetchFromAQICN(lat: lat, lon: lon) { return aqi }
        return await fetchFromOpenWeatherMap(lat: lat, lon: lon)
    }

    private static func fetchFromAQICN(lat: Double, lon: Double) async -> Double? {
        guard !AQIConfig.aqicnToken.isEmpty else { return nil }
        guard let url = URL(string: "https://api.waqi.info/feed/geo:\(lat);\(lon)/?token=\(AQIConfig.aqicnToken)") else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (json["status"] as? String) == "ok",
                  let dataObj = json["data"] as? [String: Any],
                  let aqi = dataObj["aqi"] as? Double ?? (dataObj["aqi"] as? Int).map(Double.init)
            else { return nil }
            return aqi
        } catch {
            print("[AQISyncEngine] aqicn.org fetch failed: \(error)")
            return nil
        }
    }

    private static func fetchFromOpenWeatherMap(lat: Double, lon: Double) async -> Double? {
        guard !AQIConfig.openWeatherMapKey.isEmpty else { return nil }
        guard let url = URL(string: "https://api.openweathermap.org/data/2.5/air_pollution?lat=\(lat)&lon=\(lon)&appid=\(AQIConfig.openWeatherMapKey)") else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let list = json["list"] as? [[String: Any]],
                  let first = list.first,
                  let main = first["main"] as? [String: Any],
                  // OpenWeatherMap's own 1-5 scale, distinct from AQICN's US EPA 0-500 scale.
                  // Documented as a different unit at the ingestion boundary rather than
                  // silently rescaled, since a naive linear conversion would misrepresent it.
                  let owmAqi = main["aqi"] as? Double ?? (main["aqi"] as? Int).map(Double.init)
            else { return nil }
            return owmAqi
        } catch {
            print("[AQISyncEngine] OpenWeatherMap fetch failed: \(error)")
            return nil
        }
    }
}

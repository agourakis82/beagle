//
//  WeatherSyncEngine.swift
//  BeagleCore
//
//  WeatherKit sync layer for the Beagle Physiome foundation.
//
//  Fetches current conditions + hourly/daily forecast at the device's current
//  location using WeatherKit.WeatherService. Observations are handed to
//  PhysiomeUploader which queues them for POST /api/physiome/ingest.
//
//  Trigger strategies:
//   1. Periodic timer — once per hour while the app is foregrounded.
//   2. Significant location change — when CoreLocation fires a significant update.
//   Both paths converge into fetchAndEnqueue(uploader:).
//
//  Entitlements required (add to BeagleCockpit.entitlements in Xcode):
//    com.apple.developer.weatherkit = true
//
//  Privacy strings required (add to Info.plist in Xcode):
//    NSLocationWhenInUseUsageDescription
//    NSLocationAlwaysAndWhenInUseUsageDescription (for significant-change delivery)
//
//  Attribution: WeatherKit data must be attributed per Apple's guidelines.
//  Add "Weather" attribution UI wherever weather data is displayed in the app.
//

import Foundation
import CoreLocation
#if canImport(WeatherKit)
import WeatherKit

// MARK: - Weather observation model

/// A single weather observation ready to be sent to /api/physiome/ingest.
public struct PhysioWeatherObservation: Sendable, Codable, Equatable {
    /// ISO-8601 timestamp of observation.
    public let ts: String
    public let lat: Double
    public let lon: Double
    // Optional so a barometer-only observation (pressure from CMAltimeter) can omit the
    // fields it doesn't measure instead of writing misleading zeros for temp/humidity/UV.
    public let tempC: Double?
    public let pressureHpa: Double?
    public let humidityPct: Double?
    public let uvIndex: Double?
    public let precipMm: Double?
    public let condition: String
    /// Wind speed in km/h.
    public let windKph: Double?
    /// Dew point in °C.
    public let dewPointC: Double?
    /// Visibility in kilometres.
    public let visibilityKm: Double?
    /// Air Quality Index (US EPA scale), from AQISyncEngine — WeatherKit doesn't provide this.
    public let aqi: Double?
    /// AMBIENT (device barometer) pressure hPa — the user's true local pressure, distinct from
    /// the Open-Meteo station pressureHpa. altitudeM from CMAltimeter. city/place reverse-geocoded.
    public let ambientPressureHpa: Double?
    public let altitudeM: Double?
    public let city: String?
    public let place: String?

    enum CodingKeys: String, CodingKey {
        case ts, lat, lon
        case tempC        = "temp_c"
        case pressureHpa  = "pressure_hpa"
        case humidityPct  = "humidity"
        case uvIndex      = "uv_index"
        case precipMm     = "precip_mm"
        case condition
        case windKph      = "wind_kph"
        case dewPointC    = "dew_point_c"
        case visibilityKm = "visibility_km"
        case aqi
        case ambientPressureHpa = "ambient_pressure_hpa"
        case altitudeM = "altitude_m"
        case city, place
    }

    public init(
        ts: String, lat: Double, lon: Double,
        tempC: Double?, pressureHpa: Double?, humidityPct: Double?, uvIndex: Double?,
        precipMm: Double?, condition: String, windKph: Double?, dewPointC: Double?,
        visibilityKm: Double?, aqi: Double? = nil,
        ambientPressureHpa: Double? = nil, altitudeM: Double? = nil, city: String? = nil, place: String? = nil
    ) {
        self.ts = ts; self.lat = lat; self.lon = lon
        self.tempC = tempC; self.pressureHpa = pressureHpa; self.humidityPct = humidityPct
        self.uvIndex = uvIndex; self.precipMm = precipMm; self.condition = condition
        self.windKph = windKph; self.dewPointC = dewPointC; self.visibilityKm = visibilityKm
        self.aqi = aqi
        self.ambientPressureHpa = ambientPressureHpa; self.altitudeM = altitudeM; self.city = city; self.place = place
    }
}

// MARK: - Engine

/// Actor that owns WeatherKit fetches and location monitoring.
/// Thread-safe by Swift actor isolation. Requires WeatherKit entitlement.
public actor WeatherSyncEngine: NSObject {

    // MARK: - Shared

    public static let shared = WeatherSyncEngine()

    // MARK: - State

    private let service = WeatherService.shared
    // Core Location must run on a thread with a run loop (the main thread). This actor's
    // executor is a background thread with NO run loop, so a CLLocationManager owned here
    // never delivers callbacks — which is exactly why weather never uploaded. The manager
    // lives in a @MainActor provider instead.
    private var locationProvider: WeatherLocationProvider?
    private var periodicTask: Task<Void, Never>?
    private var lastLocation: CLLocation?
    private var lastFetch: Date?
    /// Retained so the CLLocationManagerDelegate can trigger fetches without
    /// needing the caller to pass the uploader through the delegate callback.
    private var currentUploader: PhysiomeUploader?

    /// Minimum interval between fetches (prevents hammering on rapid location events).
    private let minFetchInterval: TimeInterval = 20 * 60   // 20 minutes
    /// Periodic background fetch interval while foregrounded.
    private let periodicInterval: TimeInterval = 60 * 60   // 1 hour

    private let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    // MARK: - Lifecycle

    private override init() {
        super.init()
    }

    /// Start periodic fetching and significant-location-change monitoring.
    /// Call from your SceneDelegate/App @main after location permission is granted.
    public func start(uploader: PhysiomeUploader) {
        currentUploader = uploader
        // Spin up the location provider on the main actor (where Core Location works) and
        // feed fixes back into this actor.
        Task { @MainActor in
            let provider = WeatherLocationProvider()
            provider.onLocation = { [weak self] loc in
                Task { await self?.handleNewLocation(loc) }
            }
            provider.start()
            await self.attach(provider)
        }

        // Kick off periodic timer.
        periodicTask?.cancel()
        periodicTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.seedLocationIfNeeded()
                await self.fetchAndEnqueue(uploader: uploader)
                try? await Task.sleep(for: .seconds(periodicInterval))
            }
        }
    }

    private func attach(_ provider: WeatherLocationProvider) { locationProvider = provider }

    /// If we still have no location (significant-change hasn't fired), request a one-shot fix
    /// so the hourly fetch has somewhere to read weather for.
    private func seedLocationIfNeeded() {
        guard lastLocation == nil, let provider = locationProvider else { return }
        Task { @MainActor in provider.requestOneShot() }
    }

    /// Stop all fetching and monitoring. Safe to call multiple times.
    public func stop() {
        periodicTask?.cancel()
        periodicTask = nil
        let provider = locationProvider
        Task { @MainActor in provider?.stop() }
    }

    // MARK: - Fetch

    /// Fetch current conditions + hourly/daily forecast, build observation structs,
    /// and hand them to the uploader. Debounced by minFetchInterval.
    public func fetchAndEnqueue(uploader: PhysiomeUploader) async {
        guard let location = lastLocation else {
            print("[WeatherSyncEngine] no location available yet, skipping fetch")
            return
        }
        if let last = lastFetch, Date().timeIntervalSince(last) < minFetchInterval {
            return
        }
        lastFetch = Date()

        do {
            // WeatherKit on-device fails with a runtime JWT error (Code=2) that no code change
            // fixes (Apple account/activation). Fetch via the server weather proxy instead:
            // Open-Meteo primary (keyless, has UV) + OpenWeatherMap fallback (key server-side only).
            let obs = try await fetchFromServerProxy(location: location)
            await uploader.enqueue(weatherObservations: [obs])
            await uploader.flush()
        } catch {
            print("[WeatherSyncEngine] weather fetch failed: \(error)")
        }
    }

    /// Fetch current conditions from the server weather proxy (replaces WeatherKit).
    private func fetchFromServerProxy(location: CLLocation) async throws -> PhysioWeatherObservation {
        let lat = location.coordinate.latitude, lon = location.coordinate.longitude
        let geo = await Self.reverseGeocode(location)
        let url = URL(string: "https://beagle.chiuratto.ai/api/physiome/weather?lat=\(lat)&lon=\(lon)")!
        var req = URLRequest(url: url); req.timeoutInterval = 20
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "WeatherSyncEngine", code: (resp as? HTTPURLResponse)?.statusCode ?? -1,
                          userInfo: [NSLocalizedDescriptionKey: "server weather HTTP error"])
        }
        let w = try JSONDecoder().decode(ServerWeather.self, from: data)
        return PhysioWeatherObservation(
            ts: w.ts ?? iso8601.string(from: Date()),
            lat: lat, lon: lon,
            tempC: w.temp_c, pressureHpa: w.pressure_hpa, humidityPct: w.humidity,
            uvIndex: w.uv_index, precipMm: w.precip, condition: w.source ?? "server-weather",
            windKph: nil, dewPointC: nil, visibilityKm: nil, aqi: w.aqi,
            city: geo.0, place: geo.1
        )
    }
    /// Reverse-geocode to (city, place). place prefers a named POI (areasOfInterest) so a
    /// hospital/hotel/mall/home shows its name; best-effort, nil on failure.
    private static func reverseGeocode(_ location: CLLocation) async -> (String?, String?) {
        guard let pm = try? await CLGeocoder().reverseGeocodeLocation(location), let p = pm.first else { return (nil, nil) }
        let city = p.locality ?? p.subAdministrativeArea ?? p.administrativeArea
        let place = p.areasOfInterest?.first ?? p.name
        return (city, place)
    }

    private struct ServerWeather: Decodable {
        let ts: String?; let temp_c: Double?; let humidity: Double?
        let pressure_hpa: Double?; let uv_index: Double?; let precip: Double?; let source: String?; let aqi: Double?
    }

    // MARK: - Model mapping

    private func buildObservations(from weather: Weather, location: CLLocation) -> [PhysioWeatherObservation] {
        var obs: [PhysioWeatherObservation] = []

        // Current conditions
        let current = weather.currentWeather
        obs.append(PhysioWeatherObservation(
            ts: iso8601.string(from: current.date),
            lat: location.coordinate.latitude,
            lon: location.coordinate.longitude,
            tempC: current.temperature.converted(to: .celsius).value,
            pressureHpa: current.pressure.converted(to: .hectopascals).value,
            humidityPct: current.humidity * 100,
            uvIndex: Double(current.uvIndex.value),
            precipMm: nil, // current weather doesn't have precipitation amount
            condition: current.condition.description,
            windKph: current.wind.speed.converted(to: .kilometersPerHour).value,
            dewPointC: current.dewPoint.converted(to: .celsius).value,
            visibilityKm: current.visibility.converted(to: .kilometers).value
        ))

        // Daily forecasts — take the next 7 days
        let dailyLimit = min(weather.dailyForecast.count, 7)
        for day in weather.dailyForecast.prefix(dailyLimit) {
            obs.append(PhysioWeatherObservation(
                ts: iso8601.string(from: day.date),
                lat: location.coordinate.latitude,
                lon: location.coordinate.longitude,
                tempC: day.highTemperature.converted(to: .celsius).value,
                pressureHpa: nil,  // not available at daily resolution
                humidityPct: (day.precipitationChance * 100), // proxy: use precip chance
                uvIndex: Double(day.uvIndex.value),
                precipMm: day.precipitationAmount.converted(to: .millimeters).value,
                condition: day.condition.description,
                windKph: nil,
                dewPointC: nil,
                visibilityKm: nil
            ))
        }

        // Hourly forecasts — take the next 24 hours
        let hourlyLimit = min(weather.hourlyForecast.count, 24)
        for hour in weather.hourlyForecast.prefix(hourlyLimit) {
            obs.append(PhysioWeatherObservation(
                ts: iso8601.string(from: hour.date),
                lat: location.coordinate.latitude,
                lon: location.coordinate.longitude,
                tempC: hour.temperature.converted(to: .celsius).value,
                pressureHpa: hour.pressure.converted(to: .hectopascals).value,
                humidityPct: hour.humidity * 100,
                uvIndex: Double(hour.uvIndex.value),
                precipMm: hour.precipitationAmount.converted(to: .millimeters).value,
                condition: hour.condition.description,
                windKph: hour.wind.speed.converted(to: .kilometersPerHour).value,
                dewPointC: hour.dewPoint.converted(to: .celsius).value,
                visibilityKm: hour.visibility.converted(to: .kilometers).value
            ))
        }

        return obs
    }

}

// MARK: - CLLocationManagerDelegate

/// The delegate is on the main thread (CLLocationManager requirement);
/// we immediately dispatch into the actor.
extension WeatherSyncEngine {

    fileprivate func handleNewLocation(_ location: CLLocation) async {
        lastLocation = location
        #if os(iOS)
        // Geo-tag the device barometer with the same location stream.
        await BaroSyncEngine.shared.noteLocation(
            lat: location.coordinate.latitude,
            lon: location.coordinate.longitude
        )
        #endif
        // Geo-tag AQI lookups with the same location stream.
        await AQISyncEngine.shared.noteLocation(
            lat: location.coordinate.latitude,
            lon: location.coordinate.longitude
        )
        if let uploader = currentUploader {
            await fetchAndEnqueue(uploader: uploader)
        }
    }
}

// MARK: - Location provider (main-actor — Core Location needs a run loop)

/// Owns the CLLocationManager on the main actor (so callbacks actually fire) and forwards
/// each fix to `onLocation`. Requests permission + an immediate one-shot fix so weather
/// starts flowing without waiting for the user to physically move ~500m.
@MainActor
final class WeatherLocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var onLocation: (@Sendable (CLLocation) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func start() {
        if manager.authorizationStatus == .notDetermined {
            #if os(macOS)
            manager.requestAlwaysAuthorization()
            #else
            manager.requestWhenInUseAuthorization()
            #endif
        }
        if CLLocationManager.significantLocationChangeMonitoringAvailable() {
            manager.startMonitoringSignificantLocationChanges()
        } else {
            manager.startUpdatingLocation()
        }
        manager.requestLocation()
    }

    func requestOneShot() { manager.requestLocation() }

    func stop() {
        manager.stopMonitoringSignificantLocationChanges()
        manager.stopUpdatingLocation()
    }

    nonisolated func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        guard let loc = locs.last else { return }
        Task { @MainActor in self.onLocation?(loc) }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        print("[WeatherLocation] error: \(error.localizedDescription)")
    }

    nonisolated func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        // Don't capture the passed manager (non-Sendable) into the main-actor hop — read our
        // own main-actor-isolated `manager`, which is the same object.
        Task { @MainActor in
            let s = self.manager.authorizationStatus
            #if os(macOS)
            let granted = (s == .authorizedAlways)
            #else
            let granted = (s == .authorizedAlways || s == .authorizedWhenInUse)
            #endif
            if granted { self.start() }
        }
    }
}
#endif

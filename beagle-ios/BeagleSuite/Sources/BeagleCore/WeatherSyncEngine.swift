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
    private let locationManager = CLLocationManager()
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
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        // Use significant-change monitoring — battery-friendly, suitable for weather.
        if CLLocationManager.significantLocationChangeMonitoringAvailable() {
            locationManager.startMonitoringSignificantLocationChanges()
        } else {
            locationManager.startUpdatingLocation()
        }

        // Kick off periodic timer.
        periodicTask?.cancel()
        periodicTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.fetchAndEnqueue(uploader: uploader)
                try? await Task.sleep(for: .seconds(periodicInterval))
            }
        }
    }

    /// Stop all fetching and monitoring. Safe to call multiple times.
    public func stop() {
        periodicTask?.cancel()
        periodicTask = nil
        locationManager.stopMonitoringSignificantLocationChanges()
        locationManager.stopUpdatingLocation()
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
            let weather = try await service.weather(for: location)
            let observations = buildObservations(from: weather, location: location)
            if !observations.isEmpty {
                await uploader.enqueue(weatherObservations: observations)
                await uploader.flush()
            }
        } catch {
            print("[WeatherSyncEngine] weather fetch failed: \(error)")
        }
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
extension WeatherSyncEngine: CLLocationManagerDelegate {

    /// Called by CLLocationManager on the main thread. Stores the new location
    /// and triggers a fetch using the uploader retained in `currentUploader`.
    nonisolated public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task {
            await self.handleNewLocation(location)
        }
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[WeatherSyncEngine] location error: \(error)")
    }

    nonisolated public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        // `.authorizedWhenInUse` doesn't exist on macOS (it uses `.authorizedAlways`).
        #if os(macOS)
        let granted = (status == .authorizedAlways)
        #else
        let granted = (status == .authorizedAlways || status == .authorizedWhenInUse)
        #endif
        if granted {
            if CLLocationManager.significantLocationChangeMonitoringAvailable() {
                manager.startMonitoringSignificantLocationChanges()
            }
        }
    }

    private func handleNewLocation(_ location: CLLocation) async {
        lastLocation = location
        #if os(iOS)
        // Geo-tag the device barometer with the same location stream.
        await BaroSyncEngine.shared.noteLocation(
            lat: location.coordinate.latitude,
            lon: location.coordinate.longitude
        )
        #endif
        if let uploader = currentUploader {
            await fetchAndEnqueue(uploader: uploader)
        }
    }
}
#endif

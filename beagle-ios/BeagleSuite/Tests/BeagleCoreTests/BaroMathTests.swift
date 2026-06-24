import Testing
import BeagleCore
import Foundation

// Pure-logic tests for the device-barometer throttle/conversion. Run on the iOS
// Simulator via the BeagleLogicTests scheme (the package's own `swift test` is a
// macOS-host build that is unrelated to this iOS-only logic).

@Test func baroKpaToHpa() {
    // CMAltimeter reports kPa; weather_obs stores hPa (×10).
    #expect(BaroMath.hPa(fromKPa: 101.3) == 1013.0)
    #expect(BaroMath.hPa(fromKPa: 100.0) == 1000.0)
}

@Test func baroEmitsAfterInterval() {
    // Enough time elapsed → emit even with no pressure change.
    #expect(BaroMath.shouldEmit(elapsed: 130, deltaHpa: 0))
}

@Test func baroEmitsOnPressureMove() {
    // A real pressure transition is captured promptly, before the interval.
    #expect(BaroMath.shouldEmit(elapsed: 5, deltaHpa: 0.5))
    #expect(BaroMath.shouldEmit(elapsed: 5, deltaHpa: -0.3))
}

@Test func baroSuppressesRedundantReadings() {
    // Neither enough time nor enough movement → skip (no weather_obs bloat).
    #expect(!BaroMath.shouldEmit(elapsed: 5, deltaHpa: 0.05))
}

import Testing
@testable import BeagleCore
import Foundation

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

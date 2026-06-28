// MINIMAL diag stub — used to bisect AttributeGraph cycle (2026-06-28).
import SwiftUI
import BeagleCore

struct AuroraPresence: View {
    let breathRate: Double?
    let weather: SpaceWeatherStore.Snapshot?
    let size: Size
    enum Size { case greeter, header }

    private var diameter: CGFloat { size == .greeter ? 220 : 86 }

    var body: some View {
        Circle()
            .fill(Color.gray.opacity(0.3))
            .frame(width: diameter, height: diameter)
            .accessibilityHidden(true)
    }
}

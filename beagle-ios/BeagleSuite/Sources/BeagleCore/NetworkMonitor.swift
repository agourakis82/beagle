import Foundation
import Network
import Observation

/// Observable connectivity signal. `isOnline` flips with the real network path so the companion
/// can route to the cloud when reachable and the on-device model when not, and flush its outbox
/// the moment connectivity returns. MainActor-isolated (→ Sendable), so the NWPathMonitor's
/// @Sendable update handler can capture it and hop back to the main actor to mutate state.
@MainActor
@Observable
public final class NetworkMonitor {
    public static let shared = NetworkMonitor()
    public private(set) var isOnline: Bool = true
    /// Called on an offline→online transition (e.g. to trigger an outbox flush).
    @ObservationIgnored public var onReconnect: (() -> Void)?

    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private let queue = DispatchQueue(label: "dev.sounio.networkmonitor")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                let was = self.isOnline
                self.isOnline = online
                if online && !was { self.onReconnect?() }
            }
        }
        monitor.start(queue: queue)
    }
}

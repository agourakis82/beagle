import Foundation
import Observation

/// One place that says "the app was asked to go somewhere".
///
/// It exists because the destination and the thing that knows about the URL live in different
/// views: `BeagleCockpitApp` receives `onOpenURL`, while the screen that can actually present the
/// Frota is `BeagleSurface` (iPhone) or the iPad sidebar. Rather than thread a binding through
/// every layer, the URL handler parks a request here and whoever can honour it consumes it.
///
/// This is what a Live Activity, a Shortcut, or a notification tap will use to jump straight to
/// "who needs you" — the whole point of the facho-no-bolso idea.
@MainActor
@Observable
public final class DeepLinkRouter {
    public static let shared = DeepLinkRouter()

    /// Where the app has been asked to go. Cleared by whoever honours it, so a destination is
    /// never presented twice (a re-presented sheet would fight the user's own navigation).
    public private(set) var pending: Destination?

    public enum Destination: String, Sendable, CaseIterable {
        case frota      // Mission Control: who needs you
        case oficina    // dev half: is it green / what broke / where am I
        case work       // the older agent deck
    }

    private init() {}

    /// Parse a `beagle://` URL into a destination, or nil if it is not one of ours.
    /// Accepts both `beagle://frota` (host) and `beagle:///frota` (path), because the two forms
    /// are trivially easy to mix up when writing a Shortcut by hand.
    public static func destination(for url: URL) -> Destination? {
        guard url.scheme == "beagle" else { return nil }
        let token = url.host ?? url.pathComponents.first(where: { $0 != "/" }) ?? ""
        return Destination(rawValue: token.lowercased())
    }

    public func request(_ destination: Destination) { pending = destination }

    /// DEBUG-only: honour a launch argument so a screen can be opened from a script, with no
    /// tap and no system "Abrir com…" prompt (iOS always prompts for URL opens from SpringBoard).
    /// This is how UI screenshots and smoke tests reach a screen deterministically:
    ///
    ///     xcrun simctl launch <udid> dev.sounio.cockpit -beagleOpen frota
    ///
    /// `-key value` launch arguments land in UserDefaults automatically. Release builds ignore
    /// this entirely — it must never be a way into the app on a real device.
    public func applyLaunchArgumentIfPresent() {
        #if DEBUG
        guard
            let raw = UserDefaults.standard.string(forKey: "beagleOpen"),
            let d = Destination(rawValue: raw.lowercased())
        else { return }
        request(d)
        #endif
    }


    /// Take the pending destination, if any, and clear it in the same step.
    public func consume() -> Destination? {
        defer { pending = nil }
        return pending
    }

    /// Handle a URL end-to-end. Returns true when it was ours.
    @discardableResult
    public func open(_ url: URL) -> Bool {
        guard let d = Self.destination(for: url) else { return false }
        request(d)
        return true
    }
}

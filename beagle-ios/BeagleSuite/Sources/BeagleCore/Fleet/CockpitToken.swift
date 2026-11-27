import Foundation

/// Where the cockpit token comes from, in order of preference.
///
/// The iOS app reads it from `Secrets.plist` inside its bundle. The macOS Mission Control is a
/// package executable — it has NO bundle, so that lookup returns nothing and every call 401s with
/// what looks like a network problem. This resolver adds the two sources a desktop tool should
/// have, without changing anything the Companion depends on.
///
/// A token is required (not optional) since the cockpit stopped accepting the forgeable
/// `tailscale-user-login` header on write paths — and a terminal socket is a write path.
public enum CockpitToken {
    /// Environment variable, for `swift run` and CI.
    public static let environmentKey = "BEAGLE_COCKPIT_TOKEN"
    /// A file on the operator's machine, `chmod 600`. Not in the repo, not in a bundle.
    public static var fileURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".beagle/cockpit-token")
    }

    /// Token read once from the app bundle's `Secrets.plist` (gitignored).
    /// Empty when running outside an `.app` bundle (e.g. `SounioMissionControl`, `swift test`).
    public static let bundledToken: String = {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let token = dict["COCKPIT_MOBILE_TOKEN"] as? String,
              !token.isEmpty, !token.hasPrefix("COLE-AQUI")
        else {
            return ""
        }
        return token
    }()

    /// The first source that yields a non-empty token, or nil. Never logs the value.
    public static func resolve(explicit: String? = nil) -> String? {
        if let explicit, !explicit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return explicit.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if !bundledToken.isEmpty { return bundledToken }

        if let env = ProcessInfo.processInfo.environment[environmentKey],
           !env.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return env.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let data = try? Data(contentsOf: fileURL),
           case let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return text
        }

        return nil
    }

    /// A human-readable reason when there is no token — so the UI can say what to DO instead of
    /// showing a generic connection failure.
    public static var missingReason: String {
        "Sem token do cockpit. Defina \(environmentKey) ou crie ~/.beagle/cockpit-token (chmod 600)."
    }
}

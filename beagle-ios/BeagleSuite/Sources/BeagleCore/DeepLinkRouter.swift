import Foundation
import Observation

/// Payload for Companion-specific deep links, Action Button intents, Control Center controls,
/// and CoreSpotlight search result taps.
public struct CompanionLaunchAction: Sendable, Equatable {
    public var conversationId: String?
    public var initialPrompt: String?
    public var autoSendPrompt: Bool
    public var startHandsFreeVoice: Bool
    public var continuousVoiceSession: Bool
    public var openNewConversation: Bool

    public init(
        conversationId: String? = nil,
        initialPrompt: String? = nil,
        autoSendPrompt: Bool = false,
        startHandsFreeVoice: Bool = false,
        continuousVoiceSession: Bool = false,
        openNewConversation: Bool = false
    ) {
        self.conversationId = conversationId
        self.initialPrompt = initialPrompt
        self.autoSendPrompt = autoSendPrompt
        self.startHandsFreeVoice = startHandsFreeVoice
        self.continuousVoiceSession = continuousVoiceSession
        self.openNewConversation = openNewConversation
    }
}

/// One place that says "the app was asked to go somewhere".
///
/// It exists because the destination and the thing that knows about the URL live in different
/// views: `BeagleCockpitApp` receives `onOpenURL`, while the screen that can actually present the
/// Frota is `BeagleSurface` (iPhone) or the iPad sidebar. Rather than thread a binding through
/// every layer, the URL handler parks a request here and whoever can honour it consumes it.
///
/// This is what a Live Activity, Action Button Shortcut, Spotlight tap, or Control Center button
/// uses to jump straight into voice, a conversation thread, or Mission Control.
@MainActor
@Observable
public final class DeepLinkRouter {
    public static let shared = DeepLinkRouter()

    /// Where the app has been asked to go. Cleared by whoever honours it, so a destination is
    /// never presented twice (a re-presented sheet would fight the user's own navigation).
    public private(set) var pending: Destination?

    /// Target for `beagle://project/{slug}` and `beagle://project/{slug}/agent/{kind}` deep links
    /// as well as Handoff/Spotlight project activities.
    public struct ProjectLaunchTarget: Hashable, Sendable, Identifiable {
        public let slug: String
        public let agentKind: String?

        public var id: String {
            if let agentKind, !agentKind.isEmpty {
                return "\(slug)/\(agentKind)"
            }
            return slug
        }

        public init(slug: String, agentKind: String? = nil) {
            self.slug = slug
            self.agentKind = agentKind
        }
    }

    /// Optional fine-grained Companion action (open specific Spotlight conversation, arm hands-free
    /// voice from Action Button, or prefill/send a prompt).
    public private(set) var pendingCompanionAction: CompanionLaunchAction?

    /// Pending project deep link parked until the active layout (iPhone sheet or iPad NavigationStack)
    /// mounts and consumes it — safe across cold starts before catalog refresh completes.
    public private(set) var pendingProject: ProjectLaunchTarget?

    public enum Destination: String, Sendable, CaseIterable {
        case chat       // Companion chat (e.g. from Share Sheet `beagle://chat`, Action Button, Spotlight)
        case capture    // Quick thought capture sheet (`beagle://capture`)
        case fundo      // Modo Fundo / Deep Exploration (`beagle://fundo`)
        case sintese    // Síntese Matinal Diária (`beagle://sintese`)
        case frota      // Mission Control: who needs you
        case oficina    // dev half: is it green / what broke / where am I
        case work       // the older agent deck
    }

    private init() {}

    /// Parse a `beagle://` URL into a destination, or nil if it is not one of ours.
    /// Accepts both `beagle://frota` (host) and `beagle:///frota` (path), because the two forms
    /// are trivially easy to mix up when writing a Shortcut by hand.
    public static func destination(for url: URL) -> Destination? {
        guard url.scheme?.lowercased() == "beagle" else { return nil }
        let token = (url.host ?? url.pathComponents.first(where: { $0 != "/" }) ?? "").lowercased()
        switch token {
        case "voice", "ask", "new", "conversation":
            return .chat
        case "deep", "godeep", "modo-fundo":
            return .fundo
        case "morning", "daily", "daily-synthesis":
            return .sintese
        default:
            return Destination(rawValue: token)
        }
    }

    /// Extract a `CompanionLaunchAction` if the `beagle://` URL carries voice, prompt, or thread parameters.
    public static func companionAction(for url: URL) -> CompanionLaunchAction? {
        guard url.scheme?.lowercased() == "beagle" else { return nil }
        let hostToken = (url.host ?? "").lowercased()
        let pathParts = url.pathComponents.filter { $0 != "/" }
        let primaryToken = hostToken.isEmpty ? (pathParts.first?.lowercased() ?? "") : hostToken
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        func queryValue(_ names: [String]) -> String? {
            for name in names {
                if let val = queryItems.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })?.value,
                   !val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return val.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            return nil
        }

        func queryBool(_ name: String, defaultValue: Bool = false) -> Bool {
            guard let raw = queryValue([name])?.lowercased() else { return defaultValue }
            return raw == "1" || raw == "true" || raw == "yes" || raw == "sim"
        }

        switch primaryToken {
        case "voice":
            let prompt = queryValue(["q", "prompt", "text"])
            return CompanionLaunchAction(
                initialPrompt: prompt,
                autoSendPrompt: prompt != nil && queryBool("send", defaultValue: false),
                startHandsFreeVoice: true,
                continuousVoiceSession: queryBool("continuous", defaultValue: true)
            )

        case "new":
            let prompt = queryValue(["q", "prompt", "text"])
            return CompanionLaunchAction(
                initialPrompt: prompt,
                autoSendPrompt: prompt != nil && queryBool("send", defaultValue: false),
                startHandsFreeVoice: queryBool("voice"),
                continuousVoiceSession: queryBool("continuous", defaultValue: false),
                openNewConversation: true
            )

        case "ask":
            let prompt = queryValue(["q", "prompt", "text"])
            let shouldSend = queryBool("send", defaultValue: true)
            return CompanionLaunchAction(
                initialPrompt: prompt,
                autoSendPrompt: prompt != nil && shouldSend,
                startHandsFreeVoice: prompt == nil || queryBool("voice"),
                continuousVoiceSession: queryBool("continuous", defaultValue: false)
            )

        case "conversation":
            let idFromPath: String? = {
                if !hostToken.isEmpty {
                    return pathParts.first
                }
                return pathParts.count >= 2 ? pathParts[1] : nil
            }()
            let convId = idFromPath ?? queryValue(["id", "conversation"])
            guard let convId, !convId.isEmpty else { return nil }
            return CompanionLaunchAction(
                conversationId: convId,
                startHandsFreeVoice: queryBool("voice"),
                continuousVoiceSession: queryBool("continuous", defaultValue: false)
            )

        case "chat":
            let convId = queryValue(["conversation", "id"])
            let prompt = queryValue(["q", "prompt", "text"])
            let startVoice = queryBool("voice")
            let continuous = queryBool("continuous")
            let isNew = queryBool("new")
            let autoSend = queryBool("send", defaultValue: false)
            if convId != nil || prompt != nil || startVoice || continuous || isNew {
                return CompanionLaunchAction(
                    conversationId: convId,
                    initialPrompt: prompt,
                    autoSendPrompt: prompt != nil && autoSend,
                    startHandsFreeVoice: startVoice || continuous,
                    continuousVoiceSession: continuous,
                    openNewConversation: isNew
                )
            }
            return nil

        default:
            return nil
        }
    }

    /// Parse a project deep link:
    /// - `beagle://project/{slug}` or `beagle:///project/{slug}`
    /// - `beagle://project/{slug}/agent/{kind}` or `beagle:///project/{slug}/agent/{kind}`
    public static func projectTarget(for url: URL) -> ProjectLaunchTarget? {
        guard url.scheme?.lowercased() == "beagle" else { return nil }
        let hostToken = (url.host ?? "").lowercased()
        let pathParts = url.pathComponents
            .filter { $0 != "/" }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let remainder: [String]
        if hostToken == "project" {
            remainder = pathParts
        } else if hostToken.isEmpty, let first = pathParts.first, first.lowercased() == "project" {
            remainder = Array(pathParts.dropFirst())
        } else {
            return nil
        }

        guard let slug = remainder.first, !slug.isEmpty else { return nil }
        let agentKind: String?
        if remainder.count >= 3, remainder[1].lowercased() == "agent", !remainder[2].isEmpty {
            agentKind = remainder[2]
        } else {
            agentKind = nil
        }
        return ProjectLaunchTarget(slug: slug, agentKind: agentKind)
    }

    public func request(_ destination: Destination) { pending = destination }

    public func requestCompanionAction(_ action: CompanionLaunchAction) {
        pendingCompanionAction = action
        pending = .chat
    }

    public func requestProject(_ target: ProjectLaunchTarget) {
        let trimmedSlug = target.slug.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSlug.isEmpty else { return }
        let trimmedAgent = target.agentKind?.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingProject = ProjectLaunchTarget(
            slug: trimmedSlug,
            agentKind: (trimmedAgent?.isEmpty == false) ? trimmedAgent : nil
        )
    }

    /// DEBUG-only: honour a launch argument so a screen can be opened from a script, with no
    /// tap and no system "Abrir com…" prompt (iOS always prompts for URL opens from SpringBoard).
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

    /// Take the pending Companion launch action, if any, and clear it in the same step.
    public func consumeCompanionAction() -> CompanionLaunchAction? {
        defer { pendingCompanionAction = nil }
        return pendingCompanionAction
    }

    /// Take the pending project target, if any, and clear it in the same step.
    public func consumeProject() -> ProjectLaunchTarget? {
        defer { pendingProject = nil }
        return pendingProject
    }

    /// Handle a URL end-to-end. Returns true when it was ours.
    @discardableResult
    public func open(_ url: URL) -> Bool {
        if let companionAction = Self.companionAction(for: url) {
            requestCompanionAction(companionAction)
            return true
        }
        if let projectTarget = Self.projectTarget(for: url) {
            requestProject(projectTarget)
            return true
        }
        guard let d = Self.destination(for: url) else { return false }
        request(d)
        return true
    }
}

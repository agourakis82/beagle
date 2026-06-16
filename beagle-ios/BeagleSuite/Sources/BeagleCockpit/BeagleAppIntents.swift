//
//  BeagleAppIntents.swift
//  BeagleCockpit
//
//  App Intents for Siri, Action Button, Apple Pencil squeeze, Shortcuts, and Spotlight.
//  Surfaces the exocortex's core actions as system-level intents.
//

import AppIntents
import BeagleCore

// MARK: - 1. Capture Thought

struct CaptureThoughtIntent: AppIntent {
    static let title: LocalizedStringResource = "Capture Thought"
    static let description: IntentDescription = "Capture a thought to cluster GraphRAG++ memory"
    static let openAppWhenRun = false

    @Parameter(title: "Thought")
    var text: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = await BeagleClient.shared.captureThought(text: text, source: "siri")

        if let refined = result.value?.response, !refined.isEmpty {
            // Also persist to the cockpit idea store
            _ = await CockpitClient.shared.saveIdea(
                slug: "sounio",
                text: text,
                source: "siri",
                refinedText: refined
            )
            return .result(dialog: "Captured and refined: \(refined)")
        }

        // Offline fallback: save raw to cockpit
        _ = await CockpitClient.shared.saveIdea(
            slug: "sounio",
            text: text,
            source: "siri-offline"
        )
        return .result(dialog: "Thought captured locally: \(text)")
    }
}

// MARK: - 2. Go Deeper

struct GoDeepIntent: AppIntent {
    static let title: LocalizedStringResource = "Go Deeper"
    static let description: IntentDescription = "Explore a topic deeply with multiple reasoning modalities"
    static let openAppWhenRun = true

    @Parameter(title: "Topic")
    var topic: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Kick off the deep research pipeline; the app opens to show results
        let result = await BeagleClient.shared.deepResearch(query: topic)

        if let hypothesis = result.value?.bestHypothesis, !hypothesis.isEmpty {
            return .result(dialog: "Deep exploration complete: \(String(hypothesis.prefix(200)))")
        }
        if let error = result.error {
            return .result(dialog: "Deep exploration started for: \(topic) (cluster response: \(error))")
        }
        return .result(dialog: "Opening deep exploration for: \(topic)")
    }
}

// MARK: - 3. Cluster Status

struct ClusterStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Cluster Status"
    static let description: IntentDescription = "Check the status of the Beagle computing cluster"
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let summary = await CockpitClient.shared.mobileSummary()

        if let data = summary.value {
            var parts: [String] = []

            if let health = data.clusterHealth, !health.isEmpty {
                parts.append("Cluster: \(health)")
            }
            if let agents = data.activeAgentsCount, agents > 0 {
                parts.append("\(agents) active agent\(agents == 1 ? "" : "s")")
            }
            if let sessions = data.activeSessionsCount, sessions > 0 {
                parts.append("\(sessions) session\(sessions == 1 ? "" : "s")")
            }

            if parts.isEmpty {
                return .result(dialog: "Cluster is reachable, no details available")
            }
            let summary = parts.joined(separator: ". ") + "."
            return .result(dialog: IntentDialog(stringLiteral: summary))
        }

        // Fallback: check basic reachability via beagle-server
        let reachable = await BeagleClient.shared.isReachable()
        if reachable {
            return .result(dialog: "Beagle server is reachable but cockpit summary unavailable")
        }
        return .result(dialog: "Could not reach cluster")
    }
}

// MARK: - 4. Check Readiness

struct CheckReadinessIntent: AppIntent {
    static let title: LocalizedStringResource = "Check Readiness"
    static let description: IntentDescription = "Check your cognitive readiness based on HRV and sleep"
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // PhysioStore is @MainActor. MUST refresh before reading — a bare
        // PhysioStore().cognitivePosture is always empty (no HealthKit query has run).
        let store = await MainActor.run { PhysioStore() }
        await store.refresh(requestAuthorization: true)
        let posture = await MainActor.run { store.cognitivePosture }

        if let readiness = posture.readiness {
            let pct = Int(readiness * 100)
            let intensity = posture.suggestedIntensity.rawValue
            var response = "Cognitive readiness: \(pct)%. Suggested intensity: \(intensity)."

            if let hrv = posture.hrv {
                response += " HRV: \(Int(hrv))ms."
            }
            if let sleep = posture.sleepQuality {
                response += " Sleep quality: \(Int(sleep * 100))%."
            }

            return .result(dialog: "\(response)")
        }

        return .result(dialog: "No physiological data available yet. Open the app to authorize HealthKit access.")
    }
}

// MARK: - App Shortcuts Provider

struct BeagleShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureThoughtIntent(),
            phrases: [
                "Capture a thought in \(.applicationName)",
                "Save an idea to \(.applicationName)",
                "Remember this in \(.applicationName)"
            ],
            shortTitle: "Capture Thought",
            systemImageName: "brain.head.profile"
        )
        AppShortcut(
            intent: GoDeepIntent(),
            phrases: [
                "Go deeper in \(.applicationName)",
                "Explore deeply in \(.applicationName)"
            ],
            shortTitle: "Go Deeper",
            systemImageName: "sparkles"
        )
        AppShortcut(
            intent: ClusterStatusIntent(),
            phrases: [
                "Check cluster in \(.applicationName)",
                "Cluster status in \(.applicationName)"
            ],
            shortTitle: "Cluster Status",
            systemImageName: "server.rack"
        )
        AppShortcut(
            intent: CheckReadinessIntent(),
            phrases: [
                "Check my readiness in \(.applicationName)",
                "How am I doing in \(.applicationName)"
            ],
            shortTitle: "Check Readiness",
            systemImageName: "heart.text.clipboard"
        )
    }
}

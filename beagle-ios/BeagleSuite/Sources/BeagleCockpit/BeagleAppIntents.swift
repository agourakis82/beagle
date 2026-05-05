//
//  BeagleAppIntents.swift
//  BeagleCockpit
//
//  App Intents for Siri, Action Button, Apple Pencil squeeze, Shortcuts, and Spotlight.
//  Surfaces the exocortex's core actions as system-level intents.
//

import AppIntents
import BeagleCore
import Foundation

// MARK: - Project Entity

struct ProjectEntity: AppEntity, Identifiable, Sendable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Project"
    static let defaultQuery = ProjectQuery()

    let id: String
    let slug: String
    let posture: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(slug)",
            subtitle: "posture: \(posture)"
        )
    }

    init(id: String, slug: String, posture: String) {
        self.id = id
        self.slug = slug
        self.posture = posture
    }
}

struct ProjectQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ProjectEntity] {
        let catalog = await CockpitClient.shared.catalog()
        return catalog.value?.projects?
            .filter { identifiers.contains($0.projectSlug) }
            .map { ProjectEntity(id: $0.projectSlug, slug: $0.projectSlug, posture: $0.posture.displayLabel) } ?? []
    }

    func suggestedEntities() async throws -> [ProjectEntity] {
        let catalog = await CockpitClient.shared.catalog()
        return catalog.value?.projects?.map {
            ProjectEntity(id: $0.projectSlug, slug: $0.projectSlug, posture: $0.posture.displayLabel)
        } ?? []
    }
}

// MARK: - Project Operations

struct ShowProjectStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Project Status"
    static let description: IntentDescription = "Display the current status of a sovereign project"
    static let openAppWhenRun = true

    @Parameter(title: "Project")
    var project: ProjectEntity

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let mission = await CockpitClient.shared.missionControl(slug: project.slug)
        let posture = mission.value?.project?.posture.displayLabel ?? project.posture
        let workspace = mission.value?.project?.workspacePod == nil ? "standby" : "live"
        return .result(dialog: "\(project.slug) is \(posture), workspace \(workspace).")
    }
}

struct ActivateHabitatIntent: AppIntent {
    static let title: LocalizedStringResource = "Activate Project Habitat"
    static let description: IntentDescription = "Wake a project habitat so you can start working"

    @Parameter(title: "Project")
    var project: ProjectEntity

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = await CockpitClient.shared.executeAction(slug: project.slug, actionId: "activate-habitat")
        if let output = result.value?.output, !output.isEmpty {
            return .result(dialog: "Activated \(project.slug): \(output)")
        }
        if let error = result.error {
            return .result(dialog: "Failed to activate \(project.slug): \(error)")
        }
        return .result(dialog: "Activating habitat for \(project.slug).")
    }
}

struct StandbyHabitatIntent: AppIntent {
    static let title: LocalizedStringResource = "Standby Project Habitat"
    static let description: IntentDescription = "Put a project habitat on standby"

    @Parameter(title: "Project")
    var project: ProjectEntity

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = await CockpitClient.shared.executeAction(slug: project.slug, actionId: "standby-habitat")
        if let output = result.value?.output, !output.isEmpty {
            return .result(dialog: "Standby \(project.slug): \(output)")
        }
        if let error = result.error {
            return .result(dialog: "Failed to standby \(project.slug): \(error)")
        }
        return .result(dialog: "Putting \(project.slug) habitat on standby.")
    }
}

struct LatestResearchRunIntent: AppIntent {
    static let title: LocalizedStringResource = "Latest Research Run"
    static let description: IntentDescription = "Show the most recent research activity for a project"
    static let openAppWhenRun = true

    @Parameter(title: "Project")
    var project: ProjectEntity

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let research = await CockpitClient.shared.researchOperations(slug: project.slug)
        if let error = research.error {
            return .result(dialog: "Could not load research operations for \(project.slug): \(error)")
        }
        return .result(dialog: "Latest research operations for \(project.slug) are loading.")
    }
}

// MARK: - 1. Capture Thought

struct CaptureThoughtIntent: AppIntent {
    static let title: LocalizedStringResource = "Capture Thought"
    static let description: IntentDescription = "Capture a thought to the Beagle exocortex"
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
        // PhysioStore is @MainActor, so we read from it on the main actor
        let posture = await MainActor.run {
            let store = PhysioStore()
            return store.cognitivePosture
        }

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

// MARK: - 5. Flow State

struct FlowStateIntent: AppIntent {
    static let title: LocalizedStringResource = "Flow State"
    static let description: IntentDescription = "Check your current cognitive flow state"
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let state = await BeagleClient.shared.cognitiveState()
        if let hrv = state.value?.hrv {
            let ms = hrv.latestMs ?? 0
            return .result(dialog: "HRV: \(Int(ms)) ms. You're in \(hrv.displayFlowState) state.")
        }
        return .result(dialog: "Could not read flow state. Check Apple Watch and Beagle server connectivity.")
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
            intent: ShowProjectStatusIntent(),
            phrases: [
                "Show \(.applicationName) project status",
                "\(.applicationName) status of \(\.$project)"
            ],
            shortTitle: "Project Status",
            systemImageName: "folder.fill"
        )
        AppShortcut(
            intent: ActivateHabitatIntent(),
            phrases: [
                "\(.applicationName) activate \(\.$project) habitat",
                "Wake \(\.$project) in \(.applicationName)"
            ],
            shortTitle: "Activate Habitat",
            systemImageName: "play.circle.fill"
        )
        AppShortcut(
            intent: StandbyHabitatIntent(),
            phrases: [
                "\(.applicationName) standby \(\.$project) habitat",
                "Put \(\.$project) on standby in \(.applicationName)"
            ],
            shortTitle: "Standby Habitat",
            systemImageName: "pause.circle.fill"
        )
        AppShortcut(
            intent: LatestResearchRunIntent(),
            phrases: [
                "\(.applicationName) latest research for \(\.$project)",
                "Show last run in \(.applicationName)"
            ],
            shortTitle: "Latest Research",
            systemImageName: "flask.fill"
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
        AppShortcut(
            intent: FlowStateIntent(),
            phrases: [
                "\(.applicationName) flow state",
                "What's my flow in \(.applicationName)"
            ],
            shortTitle: "Flow State",
            systemImageName: "heart.fill"
        )
    }
}

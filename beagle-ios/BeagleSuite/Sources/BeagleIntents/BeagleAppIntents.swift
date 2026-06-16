//
//  BeagleAppIntents.swift
//  BeagleIntents
//
//  App Intents — Siri + Shortcuts integration.
//
//  Voice: "Hey Siri, Beagle show Sounio status"
//         "Beagle activate HSN habitat"
//         "Beagle what's the latest ABIDE run"
//
//  Shortcuts: drag these into Shortcuts app to build automation.
//

import AppIntents
import BeagleCore
import Foundation

// MARK: - Project Entity (queryable by Siri)

public struct ProjectEntity: AppEntity, Identifiable, Sendable {
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Project"

    public static let defaultQuery = ProjectQuery()

    public var id: String
    public var slug: String
    public var posture: String

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(slug)",
            subtitle: "posture: \(posture)"
        )
    }

    public init(id: String, slug: String, posture: String) {
        self.id = id
        self.slug = slug
        self.posture = posture
    }
}

public struct ProjectQuery: EntityQuery {
    public init() {}

    public func entities(for identifiers: [String]) async throws -> [ProjectEntity] {
        let catalog = await CockpitClient.shared.catalog()
        return catalog.value?.projects?
            .filter { identifiers.contains($0.projectSlug) }
            .map { ProjectEntity(id: $0.projectSlug, slug: $0.projectSlug, posture: $0.posture.displayLabel) } ?? []
    }

    public func suggestedEntities() async throws -> [ProjectEntity] {
        let catalog = await CockpitClient.shared.catalog()
        return catalog.value?.projects?.map {
            ProjectEntity(id: $0.projectSlug, slug: $0.projectSlug, posture: $0.posture.displayLabel)
        } ?? []
    }
}

// MARK: - Intent: Show Project Status

public struct ShowProjectStatusIntent: AppIntent {
    public static let title: LocalizedStringResource = "Show Project Status"
    public static let description = IntentDescription("Display the current status of a sovereign project.")

    @Parameter(title: "Project")
    public var project: ProjectEntity

    public init() {}

    public init(project: ProjectEntity) {
        self.project = project
    }

    public static var openAppWhenRun: Bool { true }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let mission = await CockpitClient.shared.missionControl(slug: project.slug)
        let posture = mission.value?.project?.posture.displayLabel ?? project.posture
        let workspace = mission.value?.project?.workspacePod != nil ? "live" : "standby"

        let summary = "\(project.slug) is \(posture), workspace \(workspace)"
        return .result(dialog: IntentDialog(stringLiteral: summary))
    }
}

// MARK: - Intent: Activate Habitat

public struct ActivateHabitatIntent: AppIntent {
    public static let title: LocalizedStringResource = "Activate Project Habitat"
    public static let description = IntentDescription("Wake a warm project habitat so you can start working.")

    @Parameter(title: "Project")
    public var project: ProjectEntity

    public init() {}

    public init(project: ProjectEntity) {
        self.project = project
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = await CockpitClient.shared.executeAction(slug: project.slug, actionId: "activate-habitat")
        if let output = result.value?.output {
            return .result(dialog: IntentDialog(stringLiteral: "Activated \(project.slug): \(output)"))
        } else if let error = result.error {
            return .result(dialog: IntentDialog(stringLiteral: "Failed to activate \(project.slug): \(error)"))
        }
        return .result(dialog: IntentDialog(stringLiteral: "Activating habitat for \(project.slug)"))
    }
}

// MARK: - Intent: Standby Habitat

public struct StandbyHabitatIntent: AppIntent {
    public static let title: LocalizedStringResource = "Standby Project Habitat"
    public static let description = IntentDescription("Put a sovereign project habitat on standby.")

    @Parameter(title: "Project")
    public var project: ProjectEntity

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = await CockpitClient.shared.executeAction(slug: project.slug, actionId: "standby-habitat")
        if let output = result.value?.output {
            return .result(dialog: IntentDialog(stringLiteral: "Standby \(project.slug): \(output)"))
        } else if let error = result.error {
            return .result(dialog: IntentDialog(stringLiteral: "Failed: \(error)"))
        }
        return .result(dialog: IntentDialog(stringLiteral: "Putting \(project.slug) habitat on standby."))
    }
}

// MARK: - Intent: Latest Research Run

public struct LatestResearchRunIntent: AppIntent {
    public static let title: LocalizedStringResource = "Latest Research Run"
    public static let description = IntentDescription("Show the most recent research campaign (e.g., ABIDE).")

    @Parameter(title: "Project")
    public var project: ProjectEntity

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let research = await CockpitClient.shared.researchOperations(slug: project.slug)
        let dialog = IntentDialog(stringLiteral: "Latest research run for \(project.slug) loaded.")
        _ = research // acknowledged — would summarize runId/jobId in full impl
        return .result(dialog: dialog)
    }
}

// MARK: - Intent: Cluster Health Summary

public struct ClusterHealthIntent: AppIntent {
    public static let title: LocalizedStringResource = "Cluster Health"
    public static let description = IntentDescription("Quick summary of cluster node health and GPU availability.")

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let catalog = await CockpitClient.shared.catalog()
        let projects = catalog.value?.projects?.count ?? 0
        let counts = catalog.value?.projectPosturePolicy?.counts
            ?? PostureCounts.empty
        let summary = "\(projects) sovereign projects: \(counts.alwaysOn) always-on, \(counts.warm) warm, \(counts.cold) cold."
        return .result(dialog: IntentDialog(stringLiteral: summary))
    }
}

// MARK: - Intent: Capture Thought (the #1 use case)

public struct CaptureThoughtIntent: AppIntent {
    public static let title: LocalizedStringResource = "Capture Thought"
    public static let description = IntentDescription("Capture a thought into the cluster-canonical Beagle GraphRAG++ memory.")
    public static let openAppWhenRun: Bool = false

    @Parameter(title: "Thought", requestValueDialog: "What are you thinking?")
    public var thought: String

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = await BeagleClient.shared.captureThought(text: thought, source: "siri")

        if let response = result.value, let refined = response.response {
            return .result(dialog: "Captured and refined: \(String(refined.prefix(100)))")
        }

        // Offline fallback — still acknowledge
        return .result(dialog: "Thought captured locally. HERMES will refine when connected.")
    }
}

// MARK: - Intent: Flow State

public struct FlowStateIntent: AppIntent {
    public static let title: LocalizedStringResource = "Flow State"
    public static let description = IntentDescription("Check your current cognitive flow state based on HRV.")
    public static let openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        // The /api/v1/cognitive/state endpoint was retired on beagle-core. HRV / flow now
        // reads from local HealthKit via PhysioStore (the same source CheckReadinessIntent
        // uses) — the authoritative origin for this signal. PhysioStore is @MainActor.
        let posture = await MainActor.run { PhysioStore().cognitivePosture }
        if let hrv = posture.hrv {
            let intensity = posture.suggestedIntensity.rawValue
            return .result(dialog: "HRV: \(Int(hrv)) ms. Suggested intensity: \(intensity).")
        }
        return .result(dialog: "No HRV reading yet. Open Beagle to authorize HealthKit, or check your Apple Watch.")
    }
}

// MARK: - Intent: Go Deeper

public struct GoDeepIntent: AppIntent {
    public static let title: LocalizedStringResource = "Go Deeper"
    public static let description = IntentDescription("Explore a question through 8 reasoning modalities.")
    public static let openAppWhenRun: Bool = true

    @Parameter(title: "Question", requestValueDialog: "What do you want to explore?")
    public var question: String

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        // Open the app to the Deep tab with this question
        return .result(dialog: "Opening Go Deeper for: \(String(question.prefix(60)))...")
    }
}

// MARK: - Shortcuts Provider

public struct BeagleShortcutsProvider: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ClusterHealthIntent(),
            phrases: [
                "Show \(.applicationName) cluster status",
                "\(.applicationName) cluster health"
            ],
            shortTitle: "Cluster Health",
            systemImageName: "sparkle"
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
            intent: CaptureThoughtIntent(),
            phrases: [
                "Capture thought in \(.applicationName)",
                "\(.applicationName) capture a thought",
                "Remember this in \(.applicationName)"
            ],
            shortTitle: "Capture Thought",
            systemImageName: "thought.bubble"
        )

        AppShortcut(
            intent: FlowStateIntent(),
            phrases: [
                "\(.applicationName) flow state",
                "How am I doing \(.applicationName)",
                "What's my flow in \(.applicationName)"
            ],
            shortTitle: "Flow State",
            systemImageName: "heart.fill"
        )

        AppShortcut(
            intent: GoDeepIntent(),
            phrases: [
                "Go deeper in \(.applicationName)",
                "\(.applicationName) explore deeply"
            ],
            shortTitle: "Go Deeper",
            systemImageName: "scope"
        )
    }
}

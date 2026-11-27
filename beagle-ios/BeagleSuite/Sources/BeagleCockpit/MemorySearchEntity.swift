import AppIntents
import BeagleCore
import CoreSpotlight
import Observation
import SwiftUI

/// A rebuildable index of the cluster's recent public memory episodes.
struct MemorySearchEntity: IndexedEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Memory")
    static let defaultQuery = MemorySearchQuery()

    let id: String
    let title: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }

    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = defaultAttributeSet
        attributes.title = title
        attributes.contentDescription = "Memory in Beagle"
        return attributes
    }
}

struct MemorySearchQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [MemorySearchEntity] {
        let episodes = try await MemorySearchIndex.episodes()
        return identifiers.compactMap { id in
            episodes.first { $0.id == id }.map {
                MemorySearchEntity(id: $0.id, title: $0.title ?? "Memory")
            }
        }
    }

    func suggestedEntities() async throws -> [MemorySearchEntity] {
        try await MemorySearchIndex.episodes().map {
            MemorySearchEntity(id: $0.id, title: $0.title ?? "Memory")
        }
    }
}

struct OpenMemoryIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Memory"
    @Parameter(title: "Memory") var target: MemorySearchEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        MemorySearchNavigation.shared.episodeID = target.id
        return .result()
    }
}

@MainActor
@Observable
final class MemorySearchNavigation {
    static let shared = MemorySearchNavigation()
    var episodeID: String?
}

enum MemorySearchIndex {
    @MainActor private static var isRefreshing = false
    enum LookupError: LocalizedError {
        case unavailable
        var errorDescription: String? { "The cluster could not be reached. Try again when connected." }
    }

    static func episodes() async throws -> [MemoryEpisode] {
        let result = await BeagleClient.shared.memoryGraphRecent(limit: 50)
        guard let value = result.value else { throw LookupError.unavailable }
        // Spotlight is system-visible. Only records explicitly marked public are donated.
        return value.episodes.filter { $0.privacyClass == "public" }
    }

    @MainActor
    static func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let records = try await episodes()
            let entities = records.map { MemorySearchEntity(id: $0.id, title: $0.title ?? "Memory") }
            // This is a bounded recent-record index, not a full archive.
            try await CSSearchableIndex.default().deleteAppEntities(ofType: MemorySearchEntity.self)
            try await CSSearchableIndex.default().indexAppEntities(entities)
        } catch {
            // Do not replace the existing projection with an empty index during an outage.
        }
    }
}

struct MemorySearchDetailView: View {
    let episodeID: String
    @Environment(\.dismiss) private var dismiss
    @State private var episode: MemoryEpisode?
    @State private var status = "Loading memory…"

    var body: some View {
        NavigationStack {
            Form {
                if let episode {
                    Text(episode.title ?? "Memory").font(.headline)
                    LabeledContent("Source", value: episode.source)
                    LabeledContent("Created", value: episode.createdAt)
                    LabeledContent("Reference", value: episode.sourceRef)
                    if !episode.tags.isEmpty {
                        Text(episode.tags.joined(separator: ", "))
                    }
                } else {
                    Text(status)
                    Button("Retry") { Task { await load() } }
                }
            }
            .navigationTitle("Memory")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task(id: episodeID) { await load() }
    }

    private func load() async {
        do {
            let records = try await MemorySearchIndex.episodes()
            episode = records.first { $0.id == episodeID }
            if episode == nil {
                status = "This memory is no longer in the recent public index."
                try? await CSSearchableIndex.default().deleteAppEntities(
                    identifiedBy: [episodeID], ofType: MemorySearchEntity.self
                )
            }
        } catch {
            status = error.localizedDescription
        }
    }
}

// MARK: - Canonical Research Run Spotlight Entity (Backed by GET /api/mobile/v1/runs/:runId)

struct ResearchRunSearchEntity: IndexedEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Research Run")
    static let defaultQuery = ResearchRunSearchQuery()

    let id: String
    let campaignName: String
    let projectSlug: String
    let status: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(campaignName)",
            subtitle: "\(projectSlug) · \(status)"
        )
    }

    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = defaultAttributeSet
        attributes.title = campaignName
        attributes.contentDescription = "Beagle research run (\(projectSlug) · \(status))"
        return attributes
    }
}

struct ResearchRunSearchQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ResearchRunSearchEntity] {
        var resolved: [ResearchRunSearchEntity] = []
        var staleIDs: [String] = []

        for id in identifiers {
            switch await CockpitClient.shared.lookupCanonicalResearchRun(runId: id) {
            case .found(let run):
                resolved.append(
                    ResearchRunSearchEntity(
                        id: run.runId,
                        campaignName: run.campaignName,
                        projectSlug: run.projectSlug,
                        status: run.status
                    )
                )
            case .deleted, .notFound:
                staleIDs.append(id)
            case .unavailable(let reason):
                throw ResearchRunSearchIndex.LookupError.unavailable(reason)
            }
        }

        if !staleIDs.isEmpty {
            try? await CSSearchableIndex.default().deleteAppEntities(
                identifiedBy: staleIDs,
                ofType: ResearchRunSearchEntity.self
            )
        }
        return resolved
    }

    func suggestedEntities() async throws -> [ResearchRunSearchEntity] {
        []
    }
}

struct OpenResearchRunIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Research Run"
    @Parameter(title: "Research Run") var target: ResearchRunSearchEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        ResearchRunSearchNavigation.shared.runID = target.id
        return .result()
    }
}

@MainActor
@Observable
final class ResearchRunSearchNavigation {
    static let shared = ResearchRunSearchNavigation()
    var runID: String?
}

enum ResearchRunSearchIndex {
    enum LookupError: LocalizedError {
        case unavailable(String)
        var errorDescription: String? {
            switch self {
            case .unavailable(let reason):
                return "Research run unavailable while offline (\(reason))."
            }
        }
    }

    static func donate(
        runId: String,
        campaignName: String,
        projectSlug: String,
        status: String
    ) async {
        let entity = ResearchRunSearchEntity(
            id: runId,
            campaignName: campaignName,
            projectSlug: projectSlug,
            status: status
        )
        try? await CSSearchableIndex.default().indexAppEntities([entity])
    }
}

struct ResearchRunSearchDetailView: View {
    let runID: String
    @Environment(\.dismiss) private var dismiss
    @State private var run: CanonicalResearchRunRecord?
    @State private var statusMessage = "Consultando run canônico no cluster…"

    var body: some View {
        NavigationStack {
            Form {
                if let run {
                    Text(run.campaignName).font(.headline)
                    LabeledContent("Run ID", value: run.runId)
                    LabeledContent("Projeto", value: run.projectSlug)
                    LabeledContent("Status", value: run.status)
                    if let phase = run.phase, !phase.isEmpty {
                        LabeledContent("Fase", value: phase)
                    }
                    LabeledContent("Progresso", value: "\(run.stepCurrent) / \(run.stepTotal)")
                    if let startedAt = run.startedAt {
                        LabeledContent("Início", value: startedAt)
                    }
                    if let completedAt = run.completedAt {
                        LabeledContent("Conclusão", value: completedAt)
                    }
                    if let error = run.error, !error.isEmpty {
                        Text(error).foregroundStyle(.red)
                    }
                } else {
                    Text(statusMessage)
                    Button("Tentar novamente") { Task { await load() } }
                }
            }
            .navigationTitle("Research Run")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fechar") { dismiss() }
                }
            }
        }
        .task(id: runID) { await load() }
    }

    private func load() async {
        switch await CockpitClient.shared.lookupCanonicalResearchRun(runId: runID) {
        case .found(let record):
            run = record
        case .deleted:
            run = nil
            statusMessage = "Este run científico foi removido do cluster."
            try? await CSSearchableIndex.default().deleteAppEntities(
                identifiedBy: [runID],
                ofType: ResearchRunSearchEntity.self
            )
        case .notFound:
            run = nil
            statusMessage = "Run científico não encontrado no índice canônico."
            try? await CSSearchableIndex.default().deleteAppEntities(
                identifiedBy: [runID],
                ofType: ResearchRunSearchEntity.self
            )
        case .unavailable(let reason):
            statusMessage = "Cluster indisponível no momento (\(reason))."
        }
    }
}

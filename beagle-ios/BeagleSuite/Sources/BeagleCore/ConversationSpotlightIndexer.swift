//
//  ConversationSpotlightIndexer.swift
//  BeagleCore
//
//  Indexação nativa no CoreSpotlight de conversas do Companion, incluindo títulos,
//  mensagens, resumos episódicos, OCR Apple Vision de fotos, texto extraído de PDFs
//  e abstracts científicos (PubMed / DOI / arXiv) salvos na conversa.
//

import Foundation
#if canImport(CoreSpotlight) && !os(watchOS)
import CoreSpotlight
import UniformTypeIdentifiers
#endif

// MARK: - Snapshot Sendable para Indexação Spotlight

public struct SpotlightMessageTurn: Sendable, Equatable {
    public let role: String
    public let content: String
    public let attachmentDigest: String?
    public let hasImage: Bool

    public init(
        role: String,
        content: String,
        attachmentDigest: String? = nil,
        hasImage: Bool = false
    ) {
        self.role = role
        self.content = content
        self.attachmentDigest = attachmentDigest
        self.hasImage = hasImage
    }
}

public struct SpotlightConversationSnapshot: Sendable, Equatable {
    public let conversationId: String
    public let title: String
    public let projectSlug: String
    public let updatedAt: Date
    public let rollingSummary: String?
    public let turns: [SpotlightMessageTurn]

    public init(
        conversationId: String,
        title: String,
        projectSlug: String,
        updatedAt: Date,
        rollingSummary: String? = nil,
        turns: [SpotlightMessageTurn]
    ) {
        self.conversationId = conversationId
        self.title = title
        self.projectSlug = projectSlug
        self.updatedAt = updatedAt
        self.rollingSummary = rollingSummary
        self.turns = turns
    }
}

public struct SpotlightSearchablePayload: Sendable, Equatable {
    public let uniqueIdentifier: String
    public let title: String
    public let summaryDescription: String
    public let fullTextCorpus: String
    public let keywords: [String]
}

// MARK: - CoreSpotlight Indexer Actor

public actor ConversationSpotlightIndexer {
    public static let shared = ConversationSpotlightIndexer()

    public nonisolated static let domainIdentifier = "dev.sounio.cockpit.conversations"
    public nonisolated static let identifierPrefix = "beagle.conversation."

    public init() {}

    // MARK: - Deterministic Identifier Mapping

    public nonisolated static func spotlightIdentifier(for conversationId: String) -> String {
        "\(identifierPrefix)\(conversationId)"
    }

    public nonisolated static func conversationId(fromSpotlightIdentifier raw: String) -> String? {
        guard raw.hasPrefix(identifierPrefix) else { return nil }
        let extracted = String(raw.dropFirst(identifierPrefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        return extracted.isEmpty ? nil : extracted
    }

    // MARK: - Pure Payload Builder (Testable across all platforms)

    public nonisolated static func buildSearchablePayload(
        from snapshot: SpotlightConversationSnapshot,
        maxCorpusChars: Int = 12_000
    ) -> SpotlightSearchablePayload {
        let cleanTitle: String = {
            let trimmed = snapshot.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && trimmed != "Nova conversa" {
                return trimmed
            }
            if let firstUser = snapshot.turns.first(where: { $0.role == "user" })?.content
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !firstUser.isEmpty {
                return String(firstUser.replacingOccurrences(of: "\n", with: " ").prefix(56))
            }
            return "Conversa no Beagle"
        }()

        var hasPDF = false
        var hasImage = false
        var hasScience = false

        var corpusParts: [String] = [cleanTitle]
        if let roll = snapshot.rollingSummary?.trimmingCharacters(in: .whitespacesAndNewlines), !roll.isEmpty {
            corpusParts.append(roll)
        }

        for turn in snapshot.turns {
            if turn.hasImage { hasImage = true }
            let trimmedContent = turn.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedContent.isEmpty {
                if trimmedContent.contains("📄") || trimmedContent.localizedCaseInsensitiveContains(".pdf") {
                    hasPDF = true
                }
                if trimmedContent.localizedCaseInsensitiveContains("PMID")
                    || trimmedContent.localizedCaseInsensitiveContains("doi.org/")
                    || trimmedContent.localizedCaseInsensitiveContains("arXiv:") {
                    hasScience = true
                }
                corpusParts.append(trimmedContent)
            }
            if let digest = turn.attachmentDigest?.trimmingCharacters(in: .whitespacesAndNewlines), !digest.isEmpty {
                if digest.hasPrefix("PDF anexado") || digest.localizedCaseInsensitiveContains("[Pág.") {
                    hasPDF = true
                }
                if digest.localizedCaseInsensitiveContains("PubMed")
                    || digest.localizedCaseInsensitiveContains("DOI")
                    || digest.localizedCaseInsensitiveContains("arXiv") {
                    hasScience = true
                }
                if digest.localizedCaseInsensitiveContains("OCR") || digest.localizedCaseInsensitiveContains("Cena") {
                    hasImage = true
                }
                corpusParts.append(digest)
            }
        }

        let joinedCorpus = corpusParts.joined(separator: "\n")
        let cappedCorpus = joinedCorpus.count > maxCorpusChars
            ? String(joinedCorpus.prefix(maxCorpusChars))
            : joinedCorpus

        var badges: [String] = []
        if hasPDF { badges.append("📄 PDF") }
        if hasImage { badges.append("📷 Imagem") }
        if hasScience { badges.append("🔬 Artigo") }

        let latestSnippet: String = {
            if let lastAssistant = snapshot.turns.last(where: { $0.role == "assistant" && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                return Self.cleanPreviewSnippet(lastAssistant.content, maxLen: 220)
            }
            if let lastUser = snapshot.turns.last(where: { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                return Self.cleanPreviewSnippet(lastUser.content, maxLen: 220)
            }
            if let roll = snapshot.rollingSummary, !roll.isEmpty {
                return Self.cleanPreviewSnippet(roll, maxLen: 220)
            }
            return "Conversa salva no Beagle Cockpit"
        }()

        let summaryDescription = badges.isEmpty
            ? latestSnippet
            : "\(badges.joined(separator: " · ")) — \(latestSnippet)"

        var keywords: [String] = ["Beagle", "Companion", "Conversa", snapshot.projectSlug]
        if hasPDF { keywords.append(contentsOf: ["PDF", "Documento", "Exame"]) }
        if hasImage { keywords.append(contentsOf: ["Imagem", "Foto", "OCR"]) }
        if hasScience { keywords.append(contentsOf: ["PubMed", "DOI", "arXiv", "Artigo Científico"]) }

        return SpotlightSearchablePayload(
            uniqueIdentifier: Self.spotlightIdentifier(for: snapshot.conversationId),
            title: cleanTitle,
            summaryDescription: summaryDescription,
            fullTextCorpus: cappedCorpus,
            keywords: keywords
        )
    }

    private nonisolated static func cleanPreviewSnippet(_ raw: String, maxLen: Int) -> String {
        var text = raw
        if let sep = text.range(of: "\n---\n") {
            let after = text[sep.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            if !after.isEmpty { text = after }
        }
        let squashed = text
            .replacingOccurrences(of: #"[#*`_>]+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if squashed.count <= maxLen { return squashed }
        return String(squashed.prefix(maxLen)) + "…"
    }

    // MARK: - CoreSpotlight Operations

    public func index(_ snapshot: SpotlightConversationSnapshot) async {
        guard !snapshot.turns.isEmpty || !(snapshot.rollingSummary ?? "").isEmpty else { return }
        #if canImport(CoreSpotlight) && !os(watchOS)
        let item = Self.makeSearchableItem(from: snapshot)
        try? await CSSearchableIndex.default().indexSearchableItems([item])
        #endif
    }

    public func indexBatch(_ snapshots: [SpotlightConversationSnapshot]) async {
        let nonEmpty = snapshots.filter { !$0.turns.isEmpty || !($0.rollingSummary ?? "").isEmpty }
        guard !nonEmpty.isEmpty else { return }
        #if canImport(CoreSpotlight) && !os(watchOS)
        let items = nonEmpty.map { Self.makeSearchableItem(from: $0) }
        try? await CSSearchableIndex.default().indexSearchableItems(items)
        #endif
    }

    public func removeConversation(id: String) async {
        #if canImport(CoreSpotlight) && !os(watchOS)
        let identifier = Self.spotlightIdentifier(for: id)
        try? await CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [identifier])
        #endif
    }

    public func removeAllConversations() async {
        #if canImport(CoreSpotlight) && !os(watchOS)
        try? await CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [Self.domainIdentifier])
        #endif
    }

    #if canImport(CoreSpotlight) && !os(watchOS)
    private nonisolated static func makeSearchableItem(from snapshot: SpotlightConversationSnapshot) -> CSSearchableItem {
        let payload = buildSearchablePayload(from: snapshot)
        let attrs = CSSearchableItemAttributeSet(contentType: .text)
        attrs.title = payload.title
        attrs.displayName = payload.title
        attrs.contentDescription = payload.summaryDescription
        attrs.textContent = payload.fullTextCorpus
        attrs.keywords = payload.keywords
        attrs.contentModificationDate = snapshot.updatedAt
        attrs.relatedUniqueIdentifier = snapshot.conversationId

        let item = CSSearchableItem(
            uniqueIdentifier: payload.uniqueIdentifier,
            domainIdentifier: domainIdentifier,
            attributeSet: attrs
        )
        // Keep conversations searchable in Spotlight for 180 days between updates
        item.expirationDate = Date(timeIntervalSinceNow: 180 * 24 * 3600)
        return item
    }
    #endif
}

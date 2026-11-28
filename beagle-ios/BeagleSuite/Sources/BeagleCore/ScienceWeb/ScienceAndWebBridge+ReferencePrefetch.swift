//
//  ScienceAndWebBridge+ReferencePrefetch.swift
//  BeagleCore
//
//  Extração automática e prefetch de URLs, DOIs, PMIDs e arXiv IDs presentes no prompt.
//

import Foundation

// MARK: - 1. Automatic Prompt Reference Extractor & Prefetcher

extension ScienceAndWebBridge {
    public nonisolated static func extractReferences(
        from text: String,
        maxCount: Int = 2
    ) -> [DetectedWebReference] {
        guard !text.isEmpty, maxCount > 0 else { return [] }
        var found: [DetectedWebReference] = []
        var seen: Set<String> = []

        func appendUnique(_ ref: DetectedWebReference) {
            guard found.count < maxCount else { return }
            if seen.insert(ref.cacheKey).inserted {
                found.append(ref)
            }
        }

        // 1) Explicit HTTP(S) URLs
        if let urlRegex = try? NSRegularExpression(pattern: #"https?://[^\s<>"\)\]]+"#, options: [.caseInsensitive]) {
            let nsRange = NSRange(text.startIndex..., in: text)
            for match in urlRegex.matches(in: text, options: [], range: nsRange) {
                guard let range = Range(match.range, in: text) else { continue }
                let cleaned = Self.trimTrailingPunctuation(String(text[range]))
                if let url = URL(string: cleaned), let host = url.host, host.contains(".") {
                    if let pmid = Self.extractPMID(fromURL: url) {
                        appendUnique(.pmid(pmid))
                    } else if let doi = Self.extractDOI(fromURL: url) {
                        appendUnique(.doi(doi))
                    } else if let arxiv = Self.extractArXivID(fromURL: url) {
                        appendUnique(.arxiv(arxiv))
                    } else {
                        appendUnique(.url(url))
                    }
                }
            }
        }

        // 2) Standalone DOIs (10.xxxx/...)
        if found.count < maxCount,
           let doiRegex = try? NSRegularExpression(pattern: #"\b(10\.\d{4,9}/[-._;()/:A-Za-z0-9]+)"#, options: []) {
            let nsRange = NSRange(text.startIndex..., in: text)
            for match in doiRegex.matches(in: text, options: [], range: nsRange) {
                guard let range = Range(match.range(at: 1), in: text) else { continue }
                let doi = Self.trimTrailingPunctuation(String(text[range]))
                if !doi.isEmpty {
                    appendUnique(.doi(doi))
                }
            }
        }

        // 3) Explicit PMID: 12345678
        if found.count < maxCount,
           let pmidRegex = try? NSRegularExpression(pattern: #"\bPMID\s*:?\s*(\d{5,9})\b"#, options: [.caseInsensitive]) {
            let nsRange = NSRange(text.startIndex..., in: text)
            for match in pmidRegex.matches(in: text, options: [], range: nsRange) {
                guard let range = Range(match.range(at: 1), in: text) else { continue }
                appendUnique(.pmid(String(text[range])))
            }
        }

        // 4) Explicit arXiv:2405.12345
        if found.count < maxCount,
           let arxivRegex = try? NSRegularExpression(pattern: #"\barXiv\s*:?\s*(\d{4}\.\d{4,5}(?:v\d+)?)\b"#, options: [.caseInsensitive]) {
            let nsRange = NSRange(text.startIndex..., in: text)
            for match in arxivRegex.matches(in: text, options: [], range: nsRange) {
                guard let range = Range(match.range(at: 1), in: text) else { continue }
                appendUnique(.arxiv(String(text[range])))
            }
        }

        return found
    }

    /// Prefetches any URLs / DOIs / PMIDs / arXiv IDs pasted or shared in the user's message so all models
    /// (including Local Sem Censura MLX, Cluster Stream, MoE, GPT, and Claude) immediately see the content.
    public func prefetchContextForPrompt(
        _ text: String,
        maxCharsPerItem: Int = 10_000
    ) async -> (contextBlock: String, executedTools: [String])? {
        let refs = Self.extractReferences(from: text, maxCount: 2)
        guard !refs.isEmpty else { return nil }

        var blocks: [String] = []
        var toolsUsed: [String] = []

        for ref in refs {
            switch ref {
            case .pmid(let pmid):
                if let articles = try? await fetchPubMedArticles(pmids: [pmid]), let first = articles.first {
                    blocks.append("### Artigo PubMed detectado no turno\n" + first.formattedMarkdown())
                    if !toolsUsed.contains("beagle_search_pubmed") { toolsUsed.append("beagle_search_pubmed") }
                }
            case .doi(let doi):
                let resolved = await lookupDOI(doi)
                if !resolved.isEmpty && !resolved.hasPrefix("Não foi possível") {
                    blocks.append("### Obra científica (DOI) detectada no turno\n" + String(resolved.prefix(maxCharsPerItem)))
                    if !toolsUsed.contains("beagle_lookup_scientific_work") { toolsUsed.append("beagle_lookup_scientific_work") }
                }
            case .arxiv(let arxivId):
                if let papers = try? await queryArXiv(searchQuery: nil, idList: [arxivId], maxResults: 1),
                   let first = papers.first {
                    blocks.append("### Preprint arXiv detectado no turno\n" + first.formattedMarkdown())
                    if !toolsUsed.contains("beagle_lookup_scientific_work") { toolsUsed.append("beagle_lookup_scientific_work") }
                }
            case .url(let url):
                let pageText = await readURL(url, maxChars: maxCharsPerItem)
                if !pageText.isEmpty && !pageText.hasPrefix("Erro ao acessar") {
                    blocks.append("### Conteúdo extraído do link compartilhado (\(url.absoluteString))\n" + pageText)
                    if !toolsUsed.contains("beagle_read_url") { toolsUsed.append("beagle_read_url") }
                }
            }
        }

        guard !blocks.isEmpty else { return nil }
        let combined = "## Leitura ao Vivo de Links / Artigos deste Turno\n\n" + blocks.joined(separator: "\n\n---\n\n")
        return (combined, toolsUsed)
    }
}

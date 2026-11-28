//
//  ScienceWebTypes.swift
//  BeagleCore
//
//  Modelos estruturados para referências detectadas, artigos PubMed e preprints arXiv.
//

import Foundation

// MARK: - Detected Prompt References (URLs, DOIs, PMIDs, arXiv IDs)

public enum DetectedWebReference: Sendable, Equatable {
    case url(URL)
    case doi(String)
    case pmid(String)
    case arxiv(String)

    public var cacheKey: String {
        switch self {
        case .url(let u): return "url:\(u.absoluteString)"
        case .doi(let d): return "doi:\(d.lowercased())"
        case .pmid(let p): return "pmid:\(p)"
        case .arxiv(let a): return "arxiv:\(a.lowercased())"
        }
    }
}

// MARK: - Structured Models

public struct PubMedArticle: Sendable, Equatable {
    public let pmid: String
    public let doi: String?
    public let title: String
    public let authors: [String]
    public let journal: String
    public let pubYear: String
    public let publicationTypes: [String]
    public let abstractText: String

    public var pubmedURL: String { "https://pubmed.ncbi.nlm.nih.gov/\(pmid)/" }

    public func formattedMarkdown(index: Int? = nil) -> String {
        let prefix = index.map { "\($0). " } ?? ""
        var header = "\(prefix)**\(title)**"
        var meta: [String] = []
        if !authors.isEmpty {
            let shown = authors.prefix(4).joined(separator: ", ")
            meta.append(authors.count > 4 ? "\(shown) et al." : shown)
        }
        if !journal.isEmpty { meta.append("*\(journal)*") }
        if !pubYear.isEmpty { meta.append("(\(pubYear))") }
        if !publicationTypes.isEmpty {
            meta.append("[\(publicationTypes.prefix(2).joined(separator: ", "))]")
        }
        var links: [String] = ["[PMID \(pmid)](\(pubmedURL))"]
        if let doi, !doi.isEmpty {
            links.append("[DOI \(doi)](https://doi.org/\(doi))")
        }
        header += "\n   " + (meta + links).joined(separator: " · ")
        if !abstractText.isEmpty {
            let trimmedAbs = abstractText.count > 2_400
                ? String(abstractText.prefix(2_400)) + "…"
                : abstractText
            header += "\n   **Abstract:** \(trimmedAbs)"
        }
        return header
    }
}

public struct ArXivPaper: Sendable, Equatable {
    public let arxivId: String
    public let title: String
    public let authors: [String]
    public let published: String
    public let summary: String
    public var absURL: String { "https://arxiv.org/abs/\(arxivId)" }
    public var pdfURL: String { "https://arxiv.org/pdf/\(arxivId).pdf" }

    public func formattedMarkdown(index: Int? = nil) -> String {
        let prefix = index.map { "\($0). " } ?? ""
        let authorLine = authors.isEmpty
            ? ""
            : (authors.count > 4 ? authors.prefix(4).joined(separator: ", ") + " et al." : authors.joined(separator: ", "))
        let year = String(published.prefix(10))
        let cleanSummary = summary.count > 2_200 ? String(summary.prefix(2_200)) + "…" : summary
        return """
        \(prefix)**\(title)**
           \(authorLine) · (\(year)) · [arXiv:\(arxivId)](\(absURL)) · [PDF](\(pdfURL))
           **Abstract:** \(cleanSummary)
        """
    }
}

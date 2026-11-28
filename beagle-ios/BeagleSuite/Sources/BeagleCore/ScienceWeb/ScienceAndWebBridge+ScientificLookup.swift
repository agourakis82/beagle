//
//  ScienceAndWebBridge+ScientificLookup.swift
//  BeagleCore
//
//  Resolução de DOI/Crossref, EuropePMC e arXiv + parser Atom XML do arXiv.
//

import Foundation

// MARK: - 3. DOI / Crossref / EuropePMC / arXiv Lookup

extension ScienceAndWebBridge {
    public func lookupScientificWork(identifierOrQuery: String, source: String = "auto") async -> String {
        let raw = identifierOrQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "Informe um DOI, PMID, arXiv ID ou consulta científica." }

        // Normalize URL wrappers if passed directly
        if let url = URL(string: raw), url.scheme?.hasPrefix("http") == true {
            if let pmid = Self.extractPMID(fromURL: url),
               let arts = try? await fetchPubMedArticles(pmids: [pmid]),
               let first = arts.first {
                return "## Artigo PubMed\n\n" + first.formattedMarkdown(index: 1)
            }
            if let doi = Self.extractDOI(fromURL: url) {
                return await lookupDOI(doi)
            }
            if let arxivId = Self.extractArXivID(fromURL: url),
               let papers = try? await queryArXiv(searchQuery: nil, idList: [arxivId], maxResults: 1),
               let first = papers.first {
                return "## Preprint arXiv\n\n" + first.formattedMarkdown(index: 1)
            }
        }

        if raw.uppercased().hasPrefix("PMID") {
            let digits = raw.filter(\.isNumber)
            if !digits.isEmpty,
               let arts = try? await fetchPubMedArticles(pmids: [digits]),
               let first = arts.first {
                return "## Artigo PubMed\n\n" + first.formattedMarkdown(index: 1)
            }
        }

        if source == "doi" || raw.hasPrefix("10.") || raw.lowercased().hasPrefix("doi:") {
            let cleanDOI = raw
                .replacingOccurrences(of: "doi:", with: "", options: [.caseInsensitive, .anchored])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return await lookupDOI(cleanDOI)
        }

        if source == "arxiv" || raw.lowercased().hasPrefix("arxiv:") || Self.looksLikeArXivID(raw) {
            let cleanArxiv = raw
                .replacingOccurrences(of: "arxiv:", with: "", options: [.caseInsensitive, .anchored])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            do {
                let papers = Self.looksLikeArXivID(cleanArxiv)
                    ? try await queryArXiv(searchQuery: nil, idList: [cleanArxiv], maxResults: 1)
                    : try await queryArXiv(searchQuery: cleanArxiv, idList: [], maxResults: 5)
                if !papers.isEmpty {
                    let body = papers.enumerated().map { i, p in p.formattedMarkdown(index: i + 1) }.joined(separator: "\n\n")
                    return "## Resultados arXiv (\(papers.count))\n\n\(body)"
                }
            } catch {
                // fall through to EuropePMC
            }
        }

        // EuropePMC + arXiv combined search for general scientific queries
        async let epmcTask = searchEuropePMC(query: raw, maxResults: 4)
        async let arxivTask = try? queryArXiv(searchQuery: raw, idList: [], maxResults: 3)
        let epmcText = await epmcTask
        let arxivPapers = (await arxivTask) ?? []

        var sections: [String] = []
        if !epmcText.isEmpty {
            sections.append(epmcText)
        }
        if !arxivPapers.isEmpty {
            let formatted = arxivPapers.enumerated()
                .map { i, p in p.formattedMarkdown(index: i + 1) }
                .joined(separator: "\n\n")
            sections.append("### Preprints arXiv relacionados\n\n" + formatted)
        }
        return sections.isEmpty
            ? "Nenhuma obra científica encontrada para '\(raw)'."
            : sections.joined(separator: "\n\n---\n\n")
    }

    public func lookupDOI(_ rawDOI: String) async -> String {
        let doi = Self.trimTrailingPunctuation(rawDOI.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !doi.isEmpty else { return "DOI vazio." }

        guard let encoded = doi.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.crossref.org/works/\(encoded)") else {
            return "DOI inválido: \(doi)"
        }

        var title = ""
        var journal = ""
        var year = ""
        var authors: [String] = []
        var abstractText = ""
        var citations: Int?
        var pdfLink: String?

        if let (data, resp) = try? await session.data(from: url),
           let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let msg = root["message"] as? [String: Any] {
            title = ((msg["title"] as? [String])?.first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            journal = ((msg["container-title"] as? [String])?.first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            citations = msg["is-referenced-by-count"] as? Int

            if let issued = msg["issued"] as? [String: Any],
               let parts = issued["date-parts"] as? [[Int]],
               let firstYear = parts.first?.first {
                year = String(firstYear)
            }
            if let authorArr = msg["author"] as? [[String: Any]] {
                authors = authorArr.compactMap { a in
                    let family = (a["family"] as? String) ?? ""
                    let given = (a["given"] as? String) ?? ""
                    let combined = [family, given.prefix(1).description].filter { !$0.isEmpty }.joined(separator: " ")
                    return combined.isEmpty ? nil : combined
                }
            }
            if let rawAbs = msg["abstract"] as? String, !rawAbs.isEmpty {
                abstractText = Self.extractReadableText(from: rawAbs, maxChars: 2_600)
            }
            if let links = msg["link"] as? [[String: Any]] {
                pdfLink = links.first(where: { ($0["content-type"] as? String)?.contains("pdf") == true })?["URL"] as? String
            }
        }

        // Enrich missing abstract via EuropePMC DOI search (very common when Crossref omits abstract)
        if abstractText.isEmpty {
            var comps = URLComponents(string: "https://www.ebi.ac.uk/europepmc/webservices/rest/search")!
            comps.queryItems = [
                URLQueryItem(name: "query", value: "DOI:\"\(doi)\""),
                URLQueryItem(name: "resultType", value: "core"),
                URLQueryItem(name: "format", value: "json")
            ]
            if let epmcURL = comps.url,
               let (data, resp) = try? await session.data(from: epmcURL),
               let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let resultList = json["resultList"] as? [String: Any],
               let results = resultList["result"] as? [[String: Any]],
               let first = results.first {
                if title.isEmpty { title = (first["title"] as? String) ?? "" }
                if journal.isEmpty { journal = (first["journalTitle"] as? String) ?? "" }
                if year.isEmpty { year = (first["pubYear"] as? String) ?? "" }
                if let epmcAbs = first["abstractText"] as? String, !epmcAbs.isEmpty {
                    abstractText = Self.extractReadableText(from: epmcAbs, maxChars: 2_600)
                }
            }
        }

        guard !title.isEmpty || !abstractText.isEmpty else {
            return "Não foi possível resolver metadados para o DOI \(doi)."
        }

        let shownAuthors = authors.isEmpty
            ? ""
            : (authors.count > 5 ? authors.prefix(5).joined(separator: ", ") + " et al." : authors.joined(separator: ", "))
        var metaParts: [String] = []
        if !shownAuthors.isEmpty { metaParts.append(shownAuthors) }
        if !journal.isEmpty { metaParts.append("*\(journal)*") }
        if !year.isEmpty { metaParts.append("(\(year))") }
        if let citations { metaParts.append("\(citations) citações") }
        metaParts.append("[DOI \(doi)](https://doi.org/\(doi))")
        if let pdfLink, !pdfLink.isEmpty {
            metaParts.append("[PDF](\(pdfLink))")
        }

        var lines: [String] = [
            "**\(title.isEmpty ? doi : title)**",
            metaParts.joined(separator: " · ")
        ]
        if !abstractText.isEmpty {
            lines.append("**Abstract:** \(abstractText)")
        }
        return lines.joined(separator: "\n")
    }

    private func searchEuropePMC(query: String, maxResults: Int) async -> String {
        var comps = URLComponents(string: "https://www.ebi.ac.uk/europepmc/webservices/rest/search")!
        comps.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "resultType", value: "core"),
            URLQueryItem(name: "pageSize", value: String(min(max(maxResults, 1), 6))),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = comps.url,
              let (data, resp) = try? await session.data(from: url),
              let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let resultList = json["resultList"] as? [String: Any],
              let results = resultList["result"] as? [[String: Any]],
              !results.isEmpty else {
            return ""
        }

        var items: [String] = []
        for (idx, r) in results.enumerated() {
            let title = (r["title"] as? String) ?? "Sem título"
            let authorStr = (r["authorString"] as? String) ?? ""
            let journal = (r["journalTitle"] as? String) ?? ""
            let year = (r["pubYear"] as? String) ?? ""
            let pmid = (r["pmid"] as? String) ?? ""
            let doi = (r["doi"] as? String) ?? ""
            let absRaw = (r["abstractText"] as? String) ?? ""
            let absClean = absRaw.isEmpty ? "" : Self.extractReadableText(from: absRaw, maxChars: 1_800)

            var meta: [String] = []
            if !authorStr.isEmpty { meta.append(authorStr) }
            if !journal.isEmpty { meta.append("*\(journal)*") }
            if !year.isEmpty { meta.append("(\(year))") }
            if !pmid.isEmpty { meta.append("[PMID \(pmid)](https://pubmed.ncbi.nlm.nih.gov/\(pmid)/)") }
            if !doi.isEmpty { meta.append("[DOI \(doi)](https://doi.org/\(doi))") }

            var entry = "\(idx + 1). **\(title)**\n   \(meta.joined(separator: " · "))"
            if !absClean.isEmpty {
                entry += "\n   **Abstract:** \(absClean)"
            }
            items.append(entry)
        }

        return "### Literatura Biomédica (EuropePMC)\n\n" + items.joined(separator: "\n\n")
    }

    public func queryArXiv(searchQuery: String?, idList: [String], maxResults: Int = 4) async throws -> [ArXivPaper] {
        var comps = URLComponents(string: "https://export.arxiv.org/api/query")!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "max_results", value: String(min(max(maxResults, 1), 6)))
        ]
        if !idList.isEmpty {
            items.append(URLQueryItem(name: "id_list", value: idList.joined(separator: ",")))
        } else if let searchQuery, !searchQuery.isEmpty {
            items.append(URLQueryItem(name: "search_query", value: "all:\(searchQuery)"))
            items.append(URLQueryItem(name: "sortBy", value: "relevance"))
        }
        comps.queryItems = items
        guard let url = comps.url else { throw URLError(.badURL) }
        let (data, resp) = try await session.data(from: url)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return Self.parseArXivAtomXML(data)
    }

    public nonisolated static func parseArXivAtomXML(_ data: Data) -> [ArXivPaper] {
        let delegate = ArXivXMLParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        _ = parser.parse()
        return delegate.papers
    }
}

// MARK: - arXiv Atom XML Parser Delegate

private final class ArXivXMLParserDelegate: NSObject, XMLParserDelegate {
    var papers: [ArXivPaper] = []

    private var stack: [String] = []
    private var currentText = ""

    private var inEntry = false
    private var rawId = ""
    private var title = ""
    private var summary = ""
    private var published = ""
    private var authors: [String] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        stack.append(elementName)
        currentText = ""
        if elementName == "entry" {
            inEntry = true
            rawId = ""
            title = ""
            summary = ""
            published = ""
            authors = []
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let trimmed = currentText
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let parent = stack.dropLast().last ?? ""

        if inEntry {
            switch elementName {
            case "id":
                if parent == "entry" { rawId = trimmed }
            case "title":
                if parent == "entry" { title = trimmed }
            case "summary":
                if parent == "entry" { summary = trimmed }
            case "published":
                if parent == "entry" { published = trimmed }
            case "name":
                if parent == "author" && !trimmed.isEmpty { authors.append(trimmed) }
            case "entry":
                let cleanId: String = {
                    if let range = rawId.range(of: "/abs/") {
                        return String(rawId[range.upperBound...])
                    }
                    return rawId
                }()
                if !cleanId.isEmpty && !title.isEmpty {
                    papers.append(ArXivPaper(
                        arxivId: cleanId,
                        title: title,
                        authors: authors,
                        published: published,
                        summary: summary
                    ))
                }
                inEntry = false
            default:
                break
            }
        }

        _ = stack.popLast()
        currentText = ""
    }
}

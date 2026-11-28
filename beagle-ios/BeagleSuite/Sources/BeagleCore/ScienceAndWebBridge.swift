//
//  ScienceAndWebBridge.swift
//  BeagleCore
//
//  Pesquisa científica primária (PubMed NCBI E-utilities com abstracts estruturados,
//  DOI/Crossref, EuropePMC, arXiv) + leitor universal de links/páginas/PDFs online
//  + busca web ao vivo (OpenAI web_search_preview + DuckDuckGo fallback).
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

// MARK: - Main Bridge Actor

public actor ScienceAndWebBridge {
    public static let shared = ScienceAndWebBridge()

    public nonisolated static let toolNames: Set<String> = [
        "beagle_search_pubmed",
        "beagle_lookup_scientific_work",
        "beagle_read_url",
        "beagle_web_search"
    ]

    public nonisolated static func isScienceOrWebTool(_ name: String) -> Bool {
        toolNames.contains(name)
    }

    private let session: URLSession
    private let allowOpenAIHostedSearch: Bool

    public init(session: URLSession? = nil, allowOpenAIHostedSearch: Bool = true) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 16
            config.timeoutIntervalForResource = 32
            config.httpAdditionalHeaders = [
                "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) BeagleCockpit/1.0",
                "Accept-Language": "pt-BR,pt;q=0.9,en-US;q=0.8,en;q=0.7"
            ]
            self.session = URLSession(configuration: config)
        }
        self.allowOpenAIHostedSearch = allowOpenAIHostedSearch
    }

    // MARK: - OpenAI / Anthropic Tool Schemas

    public nonisolated static func openAIToolDefinitions() -> [[String: Any]] {
        [
            [
                "type": "function",
                "function": [
                    "name": "beagle_search_pubmed",
                    "description": "Busca artigos científicos biomédicos reais diretamente no PubMed (NCBI E-utilities), retornando PMID, DOI, autores, periódico, ano, tipo de estudo (RCT, meta-análise, revisão) e o ABSTRACT completo.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "query": [
                                "type": "string",
                                "description": "Consulta científica em inglês para o PubMed (suporta MeSH, autores, operadores AND/OR, ex: 'ketamine treatment resistant depression randomized trial')."
                            ],
                            "max_results": [
                                "type": "integer",
                                "description": "Número de artigos com abstract completo (1 a 8, padrão 5)."
                            ],
                            "sort": [
                                "type": "string",
                                "enum": ["relevance", "pub_date"],
                                "description": "Ordenação: 'relevance' (relevância) ou 'pub_date' (mais recentes primeiro)."
                            ],
                            "min_year": [
                                "type": "integer",
                                "description": "Ano mínimo opcional de publicação (ex: 2023)."
                            ]
                        ],
                        "required": ["query"]
                    ]
                ]
            ],
            [
                "type": "function",
                "function": [
                    "name": "beagle_lookup_scientific_work",
                    "description": "Resolve um DOI (ex: '10.1056/NEJMoa...'), PMID, identificador arXiv (ex: '2405.12345') ou busca artigos/preprints no Crossref, EuropePMC e arXiv com metadados completos, citações e abstract.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "identifier_or_query": [
                                "type": "string",
                                "description": "DOI ('10.xxxx/...'), PMID ('38412345'), arXiv ID ('2405.12345') ou termos de busca científica."
                            ],
                            "source": [
                                "type": "string",
                                "enum": ["auto", "doi", "arxiv", "europepmc"],
                                "description": "Fonte preferencial ('auto' detecta DOI/PMID/arXiv automaticamente)."
                            ]
                        ],
                        "required": ["identifier_or_query"]
                    ]
                ]
            ],
            [
                "type": "function",
                "function": [
                    "name": "beagle_read_url",
                    "description": "Acessa e extrai o texto limpo de qualquer URL (página web, artigo científico, link do PubMed/DOI/arXiv ou PDF online) diretamente no dispositivo.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "url": [
                                "type": "string",
                                "description": "URL completa http:// ou https:// para ler."
                            ]
                        ],
                        "required": ["url"]
                    ]
                ]
            ],
            [
                "type": "function",
                "function": [
                    "name": "beagle_web_search",
                    "description": "Executa busca na web ao vivo para diretrizes recentes, notícias, documentação técnica, fatos atuais ou páginas públicas com URLs reais para citação.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "query": [
                                "type": "string",
                                "description": "Consulta de busca na web."
                            ]
                        ],
                        "required": ["query"]
                    ]
                ]
            ]
        ]
    }

    // MARK: - Unified Dispatcher

    public func execute(name: String, args: [String: Any]) async -> String {
        switch name {
        case "beagle_search_pubmed":
            let query = (args["query"] as? String) ?? ""
            let maxResults = Self.intArg(args["max_results"]) ?? 5
            let sort = (args["sort"] as? String) ?? "relevance"
            let minYear = Self.intArg(args["min_year"])
            return await searchPubMed(query: query, maxResults: maxResults, sort: sort, minYear: minYear)

        case "beagle_lookup_scientific_work":
            let q = (args["identifier_or_query"] as? String) ?? (args["query"] as? String) ?? (args["doi"] as? String) ?? ""
            let src = (args["source"] as? String) ?? "auto"
            return await lookupScientificWork(identifierOrQuery: q, source: src)

        case "beagle_read_url":
            let rawURL = (args["url"] as? String) ?? ""
            return await readURLString(rawURL)

        case "beagle_web_search":
            let query = (args["query"] as? String) ?? ""
            return await webSearch(query: query)

        default:
            return "Ferramenta científica/web desconhecida: \(name)"
        }
    }

    private nonisolated static func intArg(_ raw: Any?) -> Int? {
        if let i = raw as? Int { return i }
        if let d = raw as? Double { return Int(d) }
        if let s = raw as? String { return Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }

    // MARK: - 1. Automatic Prompt Reference Extractor & Prefetcher

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
        if let urlRegex = try? NSRegularExpression(pattern: #"https?://[^\s<>\"\)\]]+"#, options: [.caseInsensitive]) {
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

    // MARK: - 2. Direct PubMed NCBI E-Utilities (esearch + efetch XML)

    public func searchPubMed(
        query: String,
        maxResults: Int = 5,
        sort: String = "relevance",
        minYear: Int? = nil
    ) async -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Informe uma consulta para buscar no PubMed." }

        // Handle direct PMID passed to searchPubMed
        if trimmed.allSatisfy(\.isNumber), trimmed.count >= 5,
           let direct = try? await fetchPubMedArticles(pmids: [trimmed]),
           let article = direct.first {
            return "## Resultado PubMed (PMID \(trimmed))\n\n" + article.formattedMarkdown(index: 1)
        }

        let clampedMax = min(max(maxResults, 1), 8)
        let effectiveQuery: String = {
            if let minYear, minYear >= 1900, minYear <= 2100 {
                return "(\(trimmed)) AND (\(minYear):3000[dp])"
            }
            return trimmed
        }()

        do {
            var searchComps = URLComponents(string: "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi")!
            searchComps.queryItems = [
                URLQueryItem(name: "db", value: "pubmed"),
                URLQueryItem(name: "term", value: effectiveQuery),
                URLQueryItem(name: "retmode", value: "json"),
                URLQueryItem(name: "retmax", value: String(clampedMax)),
                URLQueryItem(name: "sort", value: sort == "pub_date" ? "pub_date" : "relevance"),
                URLQueryItem(name: "tool", value: "BeagleCockpit")
            ]
            guard let searchURL = searchComps.url else {
                throw URLError(.badURL)
            }

            let (searchData, searchResp) = try await session.data(from: searchURL)
            guard let http = searchResp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            guard let root = try JSONSerialization.jsonObject(with: searchData) as? [String: Any],
                  let esearch = root["esearchresult"] as? [String: Any] else {
                throw URLError(.cannotParseResponse)
            }

            let totalCount = (esearch["count"] as? String) ?? "0"
            let idList = (esearch["idlist"] as? [String]) ?? []
            if idList.isEmpty {
                return "Nenhum artigo encontrado no PubMed (NCBI) para: '\(trimmed)'."
            }

            let articles = try await fetchPubMedArticles(pmids: idList)
            if articles.isEmpty {
                return "PubMed encontrou PMIDs (\(idList.joined(separator: ", "))), mas não retornou detalhes."
            }

            let formatted = articles.enumerated()
                .map { idx, art in art.formattedMarkdown(index: idx + 1) }
                .joined(separator: "\n\n")

            return """
            ## PubMed (NCBI E-utilities · \(articles.count) de \(totalCount) resultados para "\(trimmed)")

            \(formatted)
            """
        } catch {
            // Fallback to cluster PubMed proxy if direct internet to nih.gov is blocked
            let fallback = await BeagleClient.shared.searchPubMed(query: trimmed)
            if let text = fallback.value?.response, !text.isEmpty {
                return text
            }
            return "Não foi possível consultar o PubMed agora (\(error.localizedDescription))."
        }
    }

    public func fetchPubMedArticles(pmids: [String]) async throws -> [PubMedArticle] {
        let cleanIDs = pmids.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !cleanIDs.isEmpty else { return [] }

        var fetchComps = URLComponents(string: "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi")!
        fetchComps.queryItems = [
            URLQueryItem(name: "db", value: "pubmed"),
            URLQueryItem(name: "id", value: cleanIDs.joined(separator: ",")),
            URLQueryItem(name: "retmode", value: "xml"),
            URLQueryItem(name: "tool", value: "BeagleCockpit")
        ]
        guard let fetchURL = fetchComps.url else { throw URLError(.badURL) }
        let (xmlData, resp) = try await session.data(from: fetchURL)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return Self.parsePubMedXML(xmlData)
    }

    public nonisolated static func parsePubMedXML(_ data: Data) -> [PubMedArticle] {
        let delegate = PubMedXMLParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        _ = parser.parse()
        return delegate.articles
    }

    // MARK: - 3. DOI / Crossref / EuropePMC / arXiv Lookup

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

    // MARK: - 4. Universal URL & Online PDF Reader

    public func readURLString(_ raw: String, maxChars: Int = 16_000) async -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Informe uma URL para leitura." }
        let normalized = trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")
            ? trimmed
            : "https://\(trimmed)"
        guard let url = URL(string: normalized) else {
            return "URL inválida: \(trimmed)"
        }
        return await readURL(url, maxChars: maxChars)
    }

    public func readURL(_ url: URL, maxChars: Int = 16_000) async -> String {
        // Smart scientific URL routing first
        if let pmid = Self.extractPMID(fromURL: url),
           let arts = try? await fetchPubMedArticles(pmids: [pmid]),
           let first = arts.first {
            return first.formattedMarkdown()
        }
        if let doi = Self.extractDOI(fromURL: url) {
            let resolved = await lookupDOI(doi)
            if !resolved.hasPrefix("Não foi possível") {
                return resolved
            }
        }
        if let arxivId = Self.extractArXivID(fromURL: url), !url.path.lowercased().contains("/pdf/") {
            if let papers = try? await queryArXiv(searchQuery: nil, idList: [arxivId], maxResults: 1),
               let first = papers.first {
                return first.formattedMarkdown()
            }
        }

        var req = URLRequest(url: url)
        req.setValue("text/html,application/xhtml+xml,application/pdf,application/json,text/plain;q=0.9,*/*;q=0.5", forHTTPHeaderField: "Accept")

        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                return "Erro ao acessar \(url.absoluteString): resposta inválida."
            }
            guard (200..<400).contains(http.statusCode) else {
                return "Erro ao acessar \(url.absoluteString): HTTP \(http.statusCode)."
            }
            // Guard against huge binary blobs (> 14 MB)
            let cappedData = data.count > 14_000_000 ? data.prefix(14_000_000) : data[...]
            let bodyData = Data(cappedData)

            let contentType = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
            let isPDF = contentType.contains("application/pdf")
                || url.pathExtension.lowercased() == "pdf"
                || bodyData.prefix(5) == Data("%PDF-".utf8)

            if isPDF {
                let fileName = url.lastPathComponent.isEmpty ? "documento_online.pdf" : url.lastPathComponent
                if let extracted = await ChatDocumentPayload.extract(from: bodyData, fileName: fileName) {
                    return extracted.promptBlock(maxChars: maxChars)
                }
                return "PDF baixado de \(url.absoluteString), mas não foi possível extrair texto legível."
            }

            let decodedString = String(data: bodyData, encoding: .utf8)
                ?? String(data: bodyData, encoding: .isoLatin1)
                ?? String(decoding: bodyData, as: UTF8.self)

            if contentType.contains("application/json") {
                let trimmedJSON = decodedString.trimmingCharacters(in: .whitespacesAndNewlines)
                return String(trimmedJSON.prefix(maxChars))
            }

            if contentType.contains("text/plain") && !decodedString.contains("<html") {
                return String(decodedString.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxChars))
            }

            let readable = Self.extractReadableText(from: decodedString, sourceURL: url, maxChars: maxChars)
            return readable.isEmpty
                ? "Página carregada (\(url.absoluteString)), mas sem texto estático extraível (pode exigir JavaScript dinâmico)."
                : readable
        } catch {
            return "Erro ao acessar \(url.absoluteString): \(error.localizedDescription)"
        }
    }

    // MARK: - 5. Live Web Search (OpenAI web_search_preview + DuckDuckGo HTML fallback)

    public func webSearch(query: String) async -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Informe os termos de busca na web." }

        // Tier 1: High-precision OpenAI Responses web_search_preview when key is present
        if allowOpenAIHostedSearch && DirectBrainCredentials.hasOpenAI {
            if let openAIResult = await performOpenAIHostedWebSearch(query: trimmed),
               !openAIResult.isEmpty {
                return openAIResult
            }
        }

        // Tier 2: Direct keyless DuckDuckGo HTML search
        if let ddgResult = await performDuckDuckGoSearch(query: trimmed), !ddgResult.isEmpty {
            return ddgResult
        }

        return "Nenhum resultado de busca web retornado para '\(trimmed)'."
    }

    private func performOpenAIHostedWebSearch(query: String) async -> String? {
        let apiKey = DirectBrainCredentials.openAIKey
        guard !apiKey.isEmpty,
              let url = URL(string: "https://api.openai.com/v1/responses") else { return nil }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 18
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let payload: [String: Any] = [
            "model": OpenAIModelCatalog.defaultFastModel,
            "reasoning": ["effort": "low"],
            "tools": [["type": "web_search"]],
            "tool_choice": "required",
            "input": "Pesquise na web e sintetize fatos verificáveis, datas e links exatos das fontes para: \(query)"
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        req.httpBody = body

        guard let (data, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let output = root["output"] as? [[String: Any]] else {
            return nil
        }

        var texts: [String] = []
        var citations: [String] = []
        var seenURLs: Set<String> = []

        for item in output {
            guard let contentArr = item["content"] as? [[String: Any]] else { continue }
            for part in contentArr {
                if let t = part["text"] as? String, !t.isEmpty {
                    texts.append(t)
                }
                if let anns = part["annotations"] as? [[String: Any]] {
                    for ann in anns where (ann["type"] as? String) == "url_citation" {
                        let u = (ann["url"] as? String) ?? ""
                        let title = (ann["title"] as? String) ?? u
                        if !u.isEmpty, seenURLs.insert(u).inserted {
                            citations.append("- [\(title)](\(u))")
                        }
                    }
                }
            }
        }

        let mainText = texts.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !mainText.isEmpty else { return nil }
        if citations.isEmpty {
            return "## Busca Web ao Vivo\n\n\(mainText)"
        }
        return """
        ## Busca Web ao Vivo

        \(mainText)

        ### Fontes Verificadas
        \(citations.joined(separator: "\n"))
        """
    }

    private func performDuckDuckGoSearch(query: String) async -> String? {
        var comps = URLComponents(string: "https://html.duckduckgo.com/html/")!
        comps.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = comps.url,
              let (data, resp) = try? await session.data(from: url),
              let http = resp as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let html = String(data: data, encoding: .utf8) else {
            return nil
        }
        let parsed = Self.parseDuckDuckGoHTML(html, maxResults: 6)
        guard !parsed.isEmpty else { return nil }
        let formatted = parsed.enumerated().map { idx, item in
            "\(idx + 1). **[\(item.title)](\(item.url))**\(item.snippet.isEmpty ? "" : "\n   \(item.snippet)")"
        }.joined(separator: "\n\n")
        return "## Resultados da Web para \"\(query)\"\n\n\(formatted)"
    }

    public nonisolated static func parseDuckDuckGoHTML(
        _ html: String,
        maxResults: Int = 6
    ) -> [(title: String, url: String, snippet: String)] {
        guard let linkRegex = try? NSRegularExpression(
            pattern: #"<a[^>]*class="[^"]*result__a[^"]*"[^>]*href="([^"]+)"[^>]*>([\s\S]*?)</a>"#,
            options: [.caseInsensitive]
        ) else { return [] }

        let snippetRegex = try? NSRegularExpression(
            pattern: #"<a[^>]*class="[^"]*result__snippet[^"]*"[^>]*>([\s\S]*?)</a>|<div[^>]*class="[^"]*result__snippet[^"]*"[^>]*>([\s\S]*?)</div>"#,
            options: [.caseInsensitive]
        )

        let nsRange = NSRange(html.startIndex..., in: html)
        let linkMatches = linkRegex.matches(in: html, options: [], range: nsRange)
        let snippetMatches = snippetRegex?.matches(in: html, options: [], range: nsRange) ?? []

        var results: [(title: String, url: String, snippet: String)] = []
        for (i, m) in linkMatches.prefix(maxResults).enumerated() {
            guard let hrefRange = Range(m.range(at: 1), in: html),
                  let titleRange = Range(m.range(at: 2), in: html) else { continue }
            let rawHref = decodeHTMLEntities(String(html[hrefRange]))
            let resolvedURL = unwrapDuckDuckGoRedirect(rawHref)
            let cleanTitle = stripTagsAndWhitespace(String(html[titleRange]))
            var cleanSnippet = ""
            if i < snippetMatches.count {
                let sm = snippetMatches[i]
                if let r1 = Range(sm.range(at: 1), in: html) {
                    cleanSnippet = stripTagsAndWhitespace(String(html[r1]))
                } else if let r2 = Range(sm.range(at: 2), in: html) {
                    cleanSnippet = stripTagsAndWhitespace(String(html[r2]))
                }
            }
            if !cleanTitle.isEmpty, !resolvedURL.isEmpty {
                results.append((cleanTitle, resolvedURL, cleanSnippet))
            }
        }
        return results
    }

    // MARK: - Pure HTML -> Readable Markdown/Text Extractor

    public nonisolated static func extractReadableText(
        from html: String,
        sourceURL: URL? = nil,
        maxChars: Int = 18_000
    ) -> String {
        guard !html.isEmpty else { return "" }
        var s = html

        // Extract <title> and <meta description> before stripping head
        var pageTitle = ""
        if let titleRegex = try? NSRegularExpression(pattern: #"<title[^>]*>([\s\S]*?)</title>"#, options: [.caseInsensitive]),
           let m = titleRegex.firstMatch(in: s, options: [], range: NSRange(s.startIndex..., in: s)),
           let r = Range(m.range(at: 1), in: s) {
            pageTitle = stripTagsAndWhitespace(String(s[r]))
        }

        var metaDesc = ""
        if let metaRegex = try? NSRegularExpression(
            pattern: #"<meta[^>]+(?:name|property)=["'](?:description|og:description)["'][^>]+content=["']([^"']+)["']"#,
            options: [.caseInsensitive]
        ),
           let m = metaRegex.firstMatch(in: s, options: [], range: NSRange(s.startIndex..., in: s)),
           let r = Range(m.range(at: 1), in: s) {
            metaDesc = decodeHTMLEntities(String(s[r])).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Remove non-content blocks
        let noisyPatterns = [
            #"<!--[\s\S]*?-->"#,
            #"<script\b[^>]*>[\s\S]*?</script>"#,
            #"<style\b[^>]*>[\s\S]*?</style>"#,
            #"<svg\b[^>]*>[\s\S]*?</svg>"#,
            #"<noscript\b[^>]*>[\s\S]*?</noscript>"#,
            #"<head\b[^>]*>[\s\S]*?</head>"#,
            #"<nav\b[^>]*>[\s\S]*?</nav>"#,
            #"<footer\b[^>]*>[\s\S]*?</footer>"#
        ]
        for pattern in noisyPatterns {
            if let rx = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                s = rx.stringByReplacingMatches(in: s, options: [], range: NSRange(s.startIndex..., in: s), withTemplate: " ")
            }
        }

        // Preserve structural line breaks and headings
        let replacements: [(String, String)] = [
            (#"<h1\b[^>]*>"#, "\n\n# "),
            (#"<h2\b[^>]*>"#, "\n\n## "),
            (#"<h3\b[^>]*>"#, "\n\n### "),
            (#"<h[4-6]\b[^>]*>"#, "\n\n#### "),
            (#"</h[1-6]>"#, "\n"),
            (#"<li\b[^>]*>"#, "\n- "),
            (#"<br\s*/?>"#, "\n"),
            (#"</(?:p|div|section|article|tr|blockquote)>"#, "\n\n"),
            (#"</(?:td|th)>"#, " | ")
        ]
        for (pat, rep) in replacements {
            if let rx = try? NSRegularExpression(pattern: pat, options: [.caseInsensitive]) {
                s = rx.stringByReplacingMatches(in: s, options: [], range: NSRange(s.startIndex..., in: s), withTemplate: rep)
            }
        }

        // Strip remaining HTML tags
        if let tagRx = try? NSRegularExpression(pattern: #"<[^>]+>"#, options: []) {
            s = tagRx.stringByReplacingMatches(in: s, options: [], range: NSRange(s.startIndex..., in: s), withTemplate: " ")
        }

        s = decodeHTMLEntities(s)

        // Normalize horizontal spaces & collapse blank lines
        let cleanedLines: [String] = s
            .components(separatedBy: .newlines)
            .map { line in
                line.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
            }

        var compactLines: [String] = []
        var previousBlank = false
        for line in cleanedLines {
            if line.isEmpty {
                if !previousBlank && !compactLines.isEmpty {
                    compactLines.append("")
                }
                previousBlank = true
            } else {
                compactLines.append(line)
                previousBlank = false
            }
        }

        var headerParts: [String] = []
        if !pageTitle.isEmpty {
            headerParts.append("**Título:** \(pageTitle)")
        }
        if let sourceURL {
            headerParts.append("**URL:** \(sourceURL.absoluteString)")
        }
        if !metaDesc.isEmpty && !compactLines.joined(separator: " ").contains(metaDesc.prefix(60)) {
            headerParts.append("**Descrição:** \(metaDesc)")
        }

        let bodyText = compactLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let full = headerParts.isEmpty ? bodyText : (headerParts.joined(separator: "\n") + "\n\n" + bodyText)
        if full.count <= maxChars {
            return full
        }
        return String(full.prefix(maxChars)) + "\n… [conteúdo da página truncado em \(maxChars) caracteres]"
    }

    // MARK: - URL / Entity Helpers

    private nonisolated static func trimTrailingPunctuation(_ raw: String) -> String {
        var s = raw
        let trailing = CharacterSet(charactersIn: ".,;:!?'\")]}>")
        while let last = s.unicodeScalars.last, trailing.contains(last) {
            s.unicodeScalars.removeLast()
        }
        return s
    }

    private nonisolated static func extractPMID(fromURL url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              host.contains("pubmed.ncbi.nlm.nih.gov") || host.contains("ncbi.nlm.nih.gov") else {
            return nil
        }
        let parts = url.pathComponents.filter { $0 != "/" }
        if host.contains("pubmed.ncbi.nlm.nih.gov"),
           let first = parts.first, first.allSatisfy(\.isNumber), first.count >= 5 {
            return first
        }
        if parts.count >= 2, parts[0].lowercased() == "pubmed",
           parts[1].allSatisfy(\.isNumber), parts[1].count >= 5 {
            return parts[1]
        }
        return nil
    }

    private nonisolated static func extractDOI(fromURL url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              host == "doi.org" || host == "dx.doi.org" else { return nil }
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return path.hasPrefix("10.") ? path : nil
    }

    private nonisolated static func extractArXivID(fromURL url: URL) -> String? {
        guard let host = url.host?.lowercased(), host.contains("arxiv.org") else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2, (parts[0] == "abs" || parts[0] == "pdf") else { return nil }
        let idPart = parts[1].replacingOccurrences(of: ".pdf", with: "")
        return idPart.isEmpty ? nil : idPart
    }

    private nonisolated static func looksLikeArXivID(_ raw: String) -> Bool {
        guard let rx = try? NSRegularExpression(pattern: #"^\d{4}\.\d{4,5}(?:v\d+)?$"#) else { return false }
        return rx.firstMatch(in: raw, options: [], range: NSRange(raw.startIndex..., in: raw)) != nil
    }

    private nonisolated static func unwrapDuckDuckGoRedirect(_ href: String) -> String {
        if let comps = URLComponents(string: href.hasPrefix("//") ? "https:\(href)" : href),
           let uddg = comps.queryItems?.first(where: { $0.name == "uddg" })?.value,
           !uddg.isEmpty {
            return uddg
        }
        if href.hasPrefix("//") { return "https:\(href)" }
        return href
    }

    private nonisolated static func stripTagsAndWhitespace(_ raw: String) -> String {
        var s = raw
        if let rx = try? NSRegularExpression(pattern: #"<[^>]+>"#, options: []) {
            s = rx.stringByReplacingMatches(in: s, options: [], range: NSRange(s.startIndex..., in: s), withTemplate: " ")
        }
        s = decodeHTMLEntities(s)
        return s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func decodeHTMLEntities(_ input: String) -> String {
        guard input.contains("&") else { return input }
        var s = input
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&mdash;", with: "—")
            .replacingOccurrences(of: "&ndash;", with: "–")
            .replacingOccurrences(of: "&hellip;", with: "…")

        if let decRx = try? NSRegularExpression(pattern: #"&#(\d{1,7});"#) {
            let matches = decRx.matches(in: s, options: [], range: NSRange(s.startIndex..., in: s)).reversed()
            for m in matches {
                if let numRange = Range(m.range(at: 1), in: s),
                   let fullRange = Range(m.range, in: s),
                   let code = UInt32(s[numRange]),
                   let scalar = UnicodeScalar(code) {
                    s.replaceSubrange(fullRange, with: String(scalar))
                }
            }
        }
        if let hexRx = try? NSRegularExpression(pattern: #"&#x([0-9a-fA-F]{1,6});"#) {
            let matches = hexRx.matches(in: s, options: [], range: NSRange(s.startIndex..., in: s)).reversed()
            for m in matches {
                if let hexRange = Range(m.range(at: 1), in: s),
                   let fullRange = Range(m.range, in: s),
                   let code = UInt32(s[hexRange], radix: 16),
                   let scalar = UnicodeScalar(code) {
                    s.replaceSubrange(fullRange, with: String(scalar))
                }
            }
        }
        return s
    }
}

// MARK: - XML Parsers (PubMed & arXiv)

private final class PubMedXMLParserDelegate: NSObject, XMLParserDelegate {
    var articles: [PubMedArticle] = []

    private var stack: [String] = []
    private var currentText = ""

    private var pmid = ""
    private var doi: String?
    private var title = ""
    private var journal = ""
    private var pubYear = ""
    private var authors: [String] = []
    private var lastName = ""
    private var initials = ""
    private var pubTypes: [String] = []
    private var abstractSections: [String] = []
    private var currentAbstractLabel: String?
    private var currentArticleIdType: String?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        stack.append(elementName)
        currentText = ""

        if elementName == "PubmedArticle" {
            pmid = ""
            doi = nil
            title = ""
            journal = ""
            pubYear = ""
            authors = []
            pubTypes = []
            abstractSections = []
        } else if elementName == "Author" {
            lastName = ""
            initials = ""
        } else if elementName == "AbstractText" {
            currentAbstractLabel = attributeDict["Label"] ?? attributeDict["NlmCategory"]
        } else if elementName == "ArticleId" {
            currentArticleIdType = attributeDict["IdType"]
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
        let grandParent = stack.dropLast(2).last ?? ""

        switch elementName {
        case "PMID":
            if parent == "MedlineCitation" && pmid.isEmpty {
                pmid = trimmed
            }
        case "ArticleTitle":
            if parent == "Article" {
                title = trimmed
            }
        case "Title":
            if parent == "Journal" && journal.isEmpty {
                journal = trimmed
            }
        case "ISOAbbreviation":
            if parent == "Journal" && !trimmed.isEmpty {
                journal = trimmed
            }
        case "Year":
            if parent == "PubDate" && pubYear.isEmpty {
                pubYear = trimmed
            }
        case "MedlineDate":
            if parent == "PubDate" && pubYear.isEmpty {
                pubYear = String(trimmed.prefix(4))
            }
        case "LastName":
            if parent == "Author" { lastName = trimmed }
        case "Initials":
            if parent == "Author" { initials = trimmed }
        case "Author":
            let full = [lastName, initials].filter { !$0.isEmpty }.joined(separator: " ")
            if !full.isEmpty { authors.append(full) }
        case "PublicationType":
            if !trimmed.isEmpty && trimmed != "Journal Article" {
                pubTypes.append(trimmed)
            }
        case "AbstractText":
            if !trimmed.isEmpty {
                if let label = currentAbstractLabel, !label.isEmpty, label.uppercased() != "UNLABELLED" {
                    abstractSections.append("\(label.capitalized): \(trimmed)")
                } else {
                    abstractSections.append(trimmed)
                }
            }
            currentAbstractLabel = nil
        case "ArticleId":
            // Capture only the article's own DOI under PubmedData/ArticleIdList, never reference DOIs
            if currentArticleIdType == "doi", parent == "ArticleIdList", grandParent == "PubmedData", doi == nil {
                doi = trimmed
            }
            currentArticleIdType = nil
        case "PubmedArticle":
            if !pmid.isEmpty && !title.isEmpty {
                articles.append(PubMedArticle(
                    pmid: pmid,
                    doi: doi,
                    title: title,
                    authors: authors,
                    journal: journal,
                    pubYear: pubYear,
                    publicationTypes: pubTypes,
                    abstractText: abstractSections.joined(separator: " ")
                ))
            }
        default:
            break
        }

        _ = stack.popLast()
        currentText = ""
    }
}

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

//
//  ScienceAndWebBridge+PubMed.swift
//  BeagleCore
//
//  Busca direta no PubMed via NCBI E-utilities (esearch + efetch XML) e parser XML.
//

import Foundation

// MARK: - 2. Direct PubMed NCBI E-Utilities (esearch + efetch XML)

extension ScienceAndWebBridge {
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
}

// MARK: - PubMed XML Parser Delegate

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

//
//  ScienceAndWebBridge+WebReaderAndSearch.swift
//  BeagleCore
//
//  Leitor universal de URLs/PDFs online e busca web ao vivo (OpenAI + DuckDuckGo).
//

import Foundation

// MARK: - 4. Universal URL & Online PDF Reader

extension ScienceAndWebBridge {
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
}

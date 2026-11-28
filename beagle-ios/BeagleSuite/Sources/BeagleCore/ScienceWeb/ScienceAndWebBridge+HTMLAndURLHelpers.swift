//
//  ScienceAndWebBridge+HTMLAndURLHelpers.swift
//  BeagleCore
//
//  Extrator puro de HTML para Markdown/texto legível e utilitários de URL e entidades HTML.
//

import Foundation

// MARK: - Pure HTML -> Readable Markdown/Text Extractor

extension ScienceAndWebBridge {
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

    internal nonisolated static func trimTrailingPunctuation(_ raw: String) -> String {
        var s = raw
        let trailing = CharacterSet(charactersIn: ".,;:!?'\")]}>")
        while let last = s.unicodeScalars.last, trailing.contains(last) {
            s.unicodeScalars.removeLast()
        }
        return s
    }

    internal nonisolated static func extractPMID(fromURL url: URL) -> String? {
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

    internal nonisolated static func extractDOI(fromURL url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              host == "doi.org" || host == "dx.doi.org" else { return nil }
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return path.hasPrefix("10.") ? path : nil
    }

    internal nonisolated static func extractArXivID(fromURL url: URL) -> String? {
        guard let host = url.host?.lowercased(), host.contains("arxiv.org") else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2, (parts[0] == "abs" || parts[0] == "pdf") else { return nil }
        let idPart = parts[1].replacingOccurrences(of: ".pdf", with: "")
        return idPart.isEmpty ? nil : idPart
    }

    internal nonisolated static func looksLikeArXivID(_ raw: String) -> Bool {
        guard let rx = try? NSRegularExpression(pattern: #"^\d{4}\.\d{4,5}(?:v\d+)?$"#) else { return false }
        return rx.firstMatch(in: raw, options: [], range: NSRange(raw.startIndex..., in: raw)) != nil
    }

    internal nonisolated static func unwrapDuckDuckGoRedirect(_ href: String) -> String {
        if let comps = URLComponents(string: href.hasPrefix("//") ? "https:\(href)" : href),
           let uddg = comps.queryItems?.first(where: { $0.name == "uddg" })?.value,
           !uddg.isEmpty {
            return uddg
        }
        if href.hasPrefix("//") { return "https:\(href)" }
        return href
    }

    internal nonisolated static func stripTagsAndWhitespace(_ raw: String) -> String {
        var s = raw
        if let rx = try? NSRegularExpression(pattern: #"<[^>]+>"#, options: []) {
            s = rx.stringByReplacingMatches(in: s, options: [], range: NSRange(s.startIndex..., in: s), withTemplate: " ")
        }
        s = decodeHTMLEntities(s)
        return s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    internal nonisolated static func decodeHTMLEntities(_ input: String) -> String {
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

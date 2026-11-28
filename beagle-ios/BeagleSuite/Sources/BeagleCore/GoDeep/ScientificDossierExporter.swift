//
//  ScientificDossierExporter.swift
//  BeagleCore
//
//  Citation harvesting, BibTeX generation/enrichment, Markdown assembly,
//  and CoreGraphics/CoreText vector A4 PDF rendering for GoDeep scientific dossiers.
//

import Foundation
import CoreGraphics
import CoreText

// ============================================================================
// MARK: - Scientific Dossier Exporter (.md · .bib · Vector .pdf)
// ============================================================================

public enum ScientificDossierExporter {

    public struct HarvestedCitation: Codable, Sendable, Equatable, Identifiable {
        public let key: String
        public let title: String
        public let url: String
        public let doi: String?
        public let pmid: String?
        public let arxivId: String?
        public let year: String?

        public var id: String { key }

        public init(
            key: String,
            title: String,
            url: String,
            doi: String? = nil,
            pmid: String? = nil,
            arxivId: String? = nil,
            year: String? = nil
        ) {
            self.key = key
            self.title = title
            self.url = url
            self.doi = doi
            self.pmid = pmid
            self.arxivId = arxivId
            self.year = year
        }
    }

    /// Harvests verified scientific references (DOI, PMID, arXiv, and URLs) across all
    /// Modo Fundo modalities, executive synthesis, and Mesa-Redonda voices.
    public static func harvestCitations(
        prompt: String,
        modalityStates: [ModalityState],
        synthesis: String?,
        roundTable: RoundTableResult? = nil
    ) -> [HarvestedCitation] {
        var collected: [HarvestedCitation] = []
        var seenCanonical: Set<String> = []
        var usedKeys: Set<String> = []

        func register(
            rawTitle: String?,
            rawURL: String?,
            explicitDOI: String? = nil,
            explicitPMID: String? = nil,
            explicitArxiv: String? = nil
        ) {
            let cleanedDOI = explicitDOI.map(cleanIdentifier) ?? extractFirstDOI(in: rawURL ?? "")
            let cleanedPMID = explicitPMID.map(cleanIdentifier) ?? extractFirstPMID(in: rawURL ?? "")
            let cleanedArxiv = explicitArxiv.map(cleanIdentifier) ?? extractFirstArxiv(in: rawURL ?? "")

            let resolvedURL: String = {
                if let u = rawURL?.trimmingCharacters(in: .whitespacesAndNewlines), !u.isEmpty {
                    return cleanTrailingPunctuation(u)
                }
                if let doi = cleanedDOI { return "https://doi.org/\(doi)" }
                if let pmid = cleanedPMID { return "https://pubmed.ncbi.nlm.nih.gov/\(pmid)/" }
                if let arxiv = cleanedArxiv { return "https://arxiv.org/abs/\(arxiv)" }
                return ""
            }()

            let canonical: String = {
                if let doi = cleanedDOI?.lowercased(), !doi.isEmpty { return "doi:\(doi)" }
                if let pmid = cleanedPMID, !pmid.isEmpty { return "pmid:\(pmid)" }
                if let arxiv = cleanedArxiv?.lowercased(), !arxiv.isEmpty { return "arxiv:\(arxiv)" }
                return "url:\(resolvedURL.lowercased())"
            }()

            guard !resolvedURL.isEmpty, seenCanonical.insert(canonical).inserted else { return }

            let fallbackTitle: String = {
                if let doi = cleanedDOI { return "Artigo DOI \(doi)" }
                if let pmid = cleanedPMID { return "Estudo PubMed PMID \(pmid)" }
                if let arxiv = cleanedArxiv { return "Preprint arXiv:\(arxiv)" }
                return resolvedURL
            }()

            let title = (rawTitle?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap {
                $0.isEmpty ? nil : $0
            } ?? fallbackTitle

            let year = extractYear(from: "\(title) \(resolvedURL) \(cleanedArxiv ?? "")")

            let baseKey: String = {
                if let pmid = cleanedPMID { return "pmid\(pmid)" }
                if let arxiv = cleanedArxiv {
                    let digits = arxiv.replacingOccurrences(of: ".", with: "_").replacingOccurrences(of: "/", with: "_")
                    return "arxiv_\(digits)"
                }
                if let doi = cleanedDOI {
                    let slug = doi.lowercased()
                        .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "_", options: .regularExpression)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
                    return "doi_\(String(slug.prefix(28)))"
                }
                return "beagle_ref_\(collected.count + 1)"
            }()

            var uniqueKey = baseKey
            var suffix = 2
            while !usedKeys.insert(uniqueKey).inserted {
                uniqueKey = "\(baseKey)_\(suffix)"
                suffix += 1
            }

            collected.append(
                HarvestedCitation(
                    key: uniqueKey,
                    title: title,
                    url: resolvedURL,
                    doi: cleanedDOI,
                    pmid: cleanedPMID,
                    arxivId: cleanedArxiv,
                    year: year
                )
            )
        }

        // 1. Structured citations from Astra & Rosalind
        for state in modalityStates {
            guard let result = state.result else { continue }
            switch result {
            case .astraDeep(let t), .rosalindBio(let t):
                for cit in t.value?.citations ?? [] {
                    register(rawTitle: cit.title, rawURL: cit.url)
                }
            default:
                break
            }
        }

        // 2. Corpus text across prompt, modalities, synthesis, and Round Table
        var corpusChunks: [String] = [prompt]
        for state in modalityStates {
            if let result = state.result {
                switch result {
                case .astraDeep(let t), .rosalindBio(let t):
                    corpusChunks.append(t.value?.analysisMarkdown ?? result.summary)
                default:
                    corpusChunks.append(result.summary)
                }
            }
        }
        if let synthesis, !synthesis.isEmpty {
            corpusChunks.append(synthesis)
        }
        if let roundTable {
            for voice in roundTable.voices ?? [] {
                corpusChunks.append(voice.content)
            }
            if let rtSynth = roundTable.synthesis {
                corpusChunks.append(rtSynth)
            }
        }

        let fullCorpus = corpusChunks.joined(separator: "\n\n")

        // 2a. Markdown links [Title](https://...)
        if let mdRegex = try? NSRegularExpression(pattern: #"\[([^\]]+)\]\((https?://[^\s\)]+)\)"#) {
            let range = NSRange(fullCorpus.startIndex..., in: fullCorpus)
            for m in mdRegex.matches(in: fullCorpus, range: range) {
                guard let tRange = Range(m.range(at: 1), in: fullCorpus),
                      let uRange = Range(m.range(at: 2), in: fullCorpus) else { continue }
                register(
                    rawTitle: String(fullCorpus[tRange]),
                    rawURL: String(fullCorpus[uRange])
                )
            }
        }

        // 2b. Explicit DOIs (10.xxxx/...)
        if let doiRegex = try? NSRegularExpression(pattern: #"(?i)\b(10\.\d{4,9}/[-._;()/:A-Za-z0-9]+)"#) {
            let range = NSRange(fullCorpus.startIndex..., in: fullCorpus)
            for m in doiRegex.matches(in: fullCorpus, range: range) {
                guard let dRange = Range(m.range(at: 1), in: fullCorpus) else { continue }
                let doi = cleanIdentifier(String(fullCorpus[dRange]))
                register(rawTitle: nil, rawURL: "https://doi.org/\(doi)", explicitDOI: doi)
            }
        }

        // 2c. Explicit PMIDs (PMID: 12345678 or pubmed URLs)
        if let pmidRegex = try? NSRegularExpression(pattern: #"(?i)(?:PMID[:\s#]*|pubmed\.ncbi\.nlm\.nih\.gov/)(\d{5,9})\b"#) {
            let range = NSRange(fullCorpus.startIndex..., in: fullCorpus)
            for m in pmidRegex.matches(in: fullCorpus, range: range) {
                guard let pRange = Range(m.range(at: 1), in: fullCorpus) else { continue }
                let pmid = String(fullCorpus[pRange])
                register(rawTitle: nil, rawURL: "https://pubmed.ncbi.nlm.nih.gov/\(pmid)/", explicitPMID: pmid)
            }
        }

        // 2d. Explicit arXiv IDs (arXiv:2603.12345 or arxiv.org/abs/2603.12345)
        if let arxivRegex = try? NSRegularExpression(pattern: #"(?i)(?:arXiv[:\s]*|arxiv\.org/(?:abs|pdf)/)(\d{4}\.\d{4,5}(?:v\d+)?)"#) {
            let range = NSRange(fullCorpus.startIndex..., in: fullCorpus)
            for m in arxivRegex.matches(in: fullCorpus, range: range) {
                guard let aRange = Range(m.range(at: 1), in: fullCorpus) else { continue }
                let arxiv = String(fullCorpus[aRange])
                register(rawTitle: nil, rawURL: "https://arxiv.org/abs/\(arxiv)", explicitArxiv: arxiv)
            }
        }

        return collected
    }

    /// Generates clean deterministic BibTeX (.bib) from harvested citations.
    public static func buildBibTeX(
        prompt: String,
        citations: [HarvestedCitation],
        generatedAt: Date = .now
    ) -> String {
        let iso = ISO8601DateFormatter().string(from: generatedAt)
        let currentYear = String(Calendar.current.component(.year, from: generatedAt))
        var lines: [String] = [
            "% Dossie Cientifico Beagle Exocortex (Modo Fundo)",
            "% Consulta: \(prompt.replacingOccurrences(of: "\n", with: " "))",
            "% Gerado em: \(iso)",
            ""
        ]

        if citations.isEmpty {
            lines.append("""
            @misc{beagle_dossier_\(currentYear),
              title = {\(escapeBibTeX("Dossiê Modo Fundo: \(String(prompt.prefix(90)))"))},
              year = {\(currentYear)},
              note = {Gerado pelo Beagle Exocortex (GPT-6.2 Astra / GPT-Rosalind)}
            }
            """)
            return lines.joined(separator: "\n")
        }

        for cit in citations {
            lines.append(formatFallbackBibTeXEntry(cit, defaultYear: currentYear))
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    /// Enriches DOIs via content-negotiation (`https://doi.org/<doi>` -> `application/x-bibtex`)
    /// with a short timeout, falling back seamlessly to deterministic BibTeX entries offline.
    public static func buildEnrichedBibTeX(
        prompt: String,
        citations: [HarvestedCitation],
        session: URLSession = .shared,
        generatedAt: Date = .now
    ) async -> String {
        guard !citations.isEmpty else {
            return buildBibTeX(prompt: prompt, citations: [], generatedAt: generatedAt)
        }

        let iso = ISO8601DateFormatter().string(from: generatedAt)
        let currentYear = String(Calendar.current.component(.year, from: generatedAt))

        var enrichedByKey: [String: String] = [:]
        let doiCitations = Array(citations.filter { $0.doi != nil }.prefix(6))

        await withTaskGroup(of: (String, String?).self) { group in
            for cit in doiCitations {
                guard let doi = cit.doi,
                      let encoded = doi.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                      let url = URL(string: "https://doi.org/\(encoded)") else { continue }
                let key = cit.key
                group.addTask {
                    var req = URLRequest(url: url, timeoutInterval: 3.5)
                    req.setValue("application/x-bibtex; charset=utf-8", forHTTPHeaderField: "Accept")
                    guard let (data, resp) = try? await session.data(for: req),
                          let http = resp as? HTTPURLResponse,
                          (200..<300).contains(http.statusCode),
                          let text = String(data: data, encoding: .utf8)?
                              .trimmingCharacters(in: .whitespacesAndNewlines),
                          text.hasPrefix("@") else {
                        return (key, nil)
                    }
                    return (key, text)
                }
            }
            for await (key, bib) in group {
                if let bib { enrichedByKey[key] = bib }
            }
        }

        var lines: [String] = [
            "% Dossie Cientifico Beagle Exocortex (Modo Fundo)",
            "% Consulta: \(prompt.replacingOccurrences(of: "\n", with: " "))",
            "% Gerado em: \(iso)",
            ""
        ]

        for cit in citations {
            if let official = enrichedByKey[cit.key] {
                lines.append(official)
            } else {
                lines.append(formatFallbackBibTeXEntry(cit, defaultYear: currentYear))
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    /// Builds a complete publication-grade Markdown scientific dossier.
    public static func buildMarkdown(
        prompt: String,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        modalityStates: [ModalityState],
        hypotheses: [QuantumHypothesisEngine.Hypothesis] = [],
        interference: QuantumHypothesisEngine.InterferenceResult? = nil,
        synthesis: String?,
        roundTable: RoundTableResult? = nil,
        simulationOutput: String? = nil
    ) -> String {
        let citations = harvestCitations(
            prompt: prompt,
            modalityStates: modalityStates,
            synthesis: synthesis,
            roundTable: roundTable
        )
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: completedAt ?? startedAt ?? .now)
        let activeLenses = modalityStates.compactMap { $0.isResolved ? $0.modality.displayName : nil }

        var md: [String] = [
            "# Dossiê Científico — Beagle Modo Fundo",
            "",
            "- **Questão Investigada**: \(prompt)",
            "- **Gerado em**: \(timestamp)",
            "- **Lentes Concluídas**: \(activeLenses.isEmpty ? "Em execução" : activeLenses.joined(separator: " · "))",
            "- **Referências Verificadas**: \(citations.count)"
        ]

        if let s = startedAt, let e = completedAt {
            let secs = String(format: "%.1fs", max(0, e.timeIntervalSince(s)))
            md.append("- **Tempo de Deliberação**: \(secs)")
        }
        md.append("")

        if let synthesis, !synthesis.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            md.append("## Síntese Executiva")
            md.append("")
            md.append(synthesis.trimmingCharacters(in: .whitespacesAndNewlines))
            md.append("")
        }

        if let sim = simulationOutput?.trimmingCharacters(in: .whitespacesAndNewlines), !sim.isEmpty {
            md.append("## Simulação & Execução Agêntica Verificada")
            md.append("")
            md.append(sim)
            md.append("")
        }

        if !hypotheses.isEmpty {
            md.append("## Superposição Quântica de Hipóteses")
            md.append("")
            for hyp in hypotheses.sorted(by: { $0.probability > $1.probability }) {
                let prob = String(format: "%.0f%%", hyp.probability * 100)
                let stateLabel = hyp.isCollapsed ? "colapsada" : "superposta"
                md.append("- **[\(prob) · \(stateLabel)] \(hyp.perspective)**: \(hyp.text)")
            }
            if let interference, !interference.novelEmergent.isEmpty {
                md.append("")
                md.append("### Tensões e Insights Emergentes")
                for item in interference.novelEmergent {
                    md.append("- \(item)")
                }
            }
            md.append("")
        }

        let resolvedStates = modalityStates.filter { $0.result != nil }
        if !resolvedStates.isEmpty {
            md.append("## Lentes Analíticas")
            md.append("")
            for state in resolvedStates {
                guard let result = state.result else { continue }
                let durationNote = state.durationMs.map { " (\($0) ms)" } ?? ""
                md.append("### \(state.modality.displayName)\(durationNote)")
                md.append("")
                switch result {
                case .astraDeep(let t), .rosalindBio(let t):
                    md.append(t.value?.analysisMarkdown ?? result.summary)
                default:
                    md.append(result.summary)
                }
                md.append("")
            }
        }

        if let roundTable {
            let pciBadge = roundTable.pciScore.map { String(format: " (Φ = %.2f)", $0) } ?? ""
            md.append("## Mesa-Redonda Epistêmica\(pciBadge)")
            md.append("")
            for voice in roundTable.voices ?? [] {
                md.append("### \(voice.name)")
                md.append(voice.content)
                md.append("")
            }
            if let rtSynthesis = roundTable.synthesis, !rtSynthesis.isEmpty {
                md.append("### Síntese de Interferência da Mesa")
                md.append(rtSynthesis)
                md.append("")
            }
        }

        if !citations.isEmpty {
            md.append("## Referências Verificadas (DOI · PMID · arXiv)")
            md.append("")
            for (index, cit) in citations.enumerated() {
                var tags: [String] = []
                if let doi = cit.doi { tags.append("DOI: `\(doi)`") }
                if let pmid = cit.pmid { tags.append("PMID: `\(pmid)`") }
                if let arxiv = cit.arxivId { tags.append("arXiv: `\(arxiv)`") }
                let tagSuffix = tags.isEmpty ? "" : " — " + tags.joined(separator: " · ")
                md.append("\(index + 1). [\(cit.title)](\(cit.url)) (`\(cit.key)`)\(tagSuffix)")
            }
            md.append("")
        }

        return md.joined(separator: "\n")
    }

    /// Renders a multi-page vector A4 PDF dossier using CoreGraphics + CoreText
    /// (works identically on iOS, iPadOS, and macOS).
    public static func renderPDFData(
        title: String,
        subtitle: String? = nil,
        markdownBody: String,
        citations: [HarvestedCitation] = []
    ) -> Data {
        let pdfData = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 595.28, height: 841.89) // A4 points
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return Data()
        }

        let attrString = buildAttributedDossier(
            title: title,
            subtitle: subtitle,
            markdownBody: markdownBody
        )

        let framesetter = CTFramesetterCreateWithAttributedString(attrString as CFAttributedString)
        let totalLength = attrString.length
        var currentIndex: CFIndex = 0
        var pageNumber = 1

        let marginX: CGFloat = 48
        let textBottomY: CGFloat = 54
        let textTopMargin: CGFloat = 58
        let textRect = CGRect(
            x: marginX,
            y: textBottomY,
            width: mediaBox.width - marginX * 2,
            height: mediaBox.height - textBottomY - textTopMargin
        )

        let headerFont = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, 8.5, nil)
        let footerFont = CTFontCreateWithName("HelveticaNeue" as CFString, 8.5, nil)
        let slateColor = makeSRGBColor(0.38, 0.44, 0.52, 1.0)
        let tealRule = makeSRGBColor(0.08, 0.55, 0.58, 0.35)

        while currentIndex < totalLength || pageNumber == 1 {
            ctx.beginPDFPage(nil)

            // Header bar
            drawSingleLine(
                "BEAGLE EXOCÓRTEX · DOSSIÊ CIENTÍFICO MODO FUNDO",
                font: headerFont,
                color: slateColor,
                at: CGPoint(x: marginX, y: mediaBox.height - 36),
                in: ctx
            )
            ctx.setStrokeColor(tealRule)
            ctx.setLineWidth(0.6)
            ctx.move(to: CGPoint(x: marginX, y: mediaBox.height - 42))
            ctx.addLine(to: CGPoint(x: mediaBox.width - marginX, y: mediaBox.height - 42))
            ctx.strokePath()

            // Main body frame
            let path = CGPath(rect: textRect, transform: nil)
            let frameRange = CFRange(location: currentIndex, length: 0)
            let frame = CTFramesetterCreateFrame(framesetter, frameRange, path, nil)
            CTFrameDraw(frame, ctx)

            // Footer
            let refLabel = citations.isEmpty ? "" : " · \(citations.count) ref(s) verificada(s)"
            drawSingleLine(
                "Página \(pageNumber)\(refLabel)",
                font: footerFont,
                color: slateColor,
                at: CGPoint(x: marginX, y: 28),
                in: ctx
            )

            ctx.endPDFPage()

            let visible = CTFrameGetVisibleStringRange(frame)
            if visible.length <= 0 { break }
            currentIndex += visible.length
            pageNumber += 1
            if pageNumber > 80 { break } // safety bound
        }

        ctx.closePDF()
        return pdfData as Data
    }

    /// Writes exported data to a sanitized file in `temporaryDirectory` ready for ShareSheet / ShareLink.
    public static func writeTemporaryExportFile(
        prompt: String,
        fileExtension: String,
        data: Data
    ) throws -> URL {
        let slug = prompt
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "pt_BR"))
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let shortSlug = slug.isEmpty ? "modo-fundo" : String(slug.prefix(36))
        let filename = "dossie-beagle-\(shortSlug).\(fileExtension)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Private Formatting & Extraction Helpers

    private static func formatFallbackBibTeXEntry(_ cit: HarvestedCitation, defaultYear: String) -> String {
        let entryType = (cit.doi != nil || cit.pmid != nil || cit.arxivId != nil) ? "article" : "misc"
        var fields: [String] = [
            "  title = {\(escapeBibTeX(cit.title))}",
            "  year = {\(cit.year ?? defaultYear)}"
        ]
        if let doi = cit.doi {
            fields.append("  doi = {\(escapeBibTeX(doi))}")
        }
        if let pmid = cit.pmid {
            fields.append("  pmid = {\(escapeBibTeX(pmid))}")
        }
        if let arxiv = cit.arxivId {
            fields.append("  eprint = {\(escapeBibTeX(arxiv))}")
            fields.append("  archivePrefix = {arXiv}")
        }
        fields.append("  url = {\(escapeBibTeX(cit.url))}")
        fields.append("  note = {Verificado via Beagle Exocortex Modo Fundo}")
        return "@\(entryType){\(cit.key),\n\(fields.joined(separator: ",\n"))\n}"
    }

    private static func escapeBibTeX(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\\", with: "\\textbackslash ")
           .replacingOccurrences(of: "{", with: "\\{")
           .replacingOccurrences(of: "}", with: "\\}")
           .replacingOccurrences(of: "\n", with: " ")
    }

    private static func cleanTrailingPunctuation(_ s: String) -> String {
        var out = s.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = out.last, ".,;:)]>\"'".contains(last) {
            out.removeLast()
        }
        return out
    }

    private static func cleanIdentifier(_ s: String) -> String {
        cleanTrailingPunctuation(s)
    }

    private static func extractFirstDOI(in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"(?i)(10\.\d{4,9}/[-._;()/:A-Za-z0-9]+)"#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return cleanIdentifier(String(text[range]))
    }

    private static func extractFirstPMID(in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"(?i)(?:PMID[:\s#]*|pubmed\.ncbi\.nlm\.nih\.gov/)(\d{5,9})\b"#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    private static func extractFirstArxiv(in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"(?i)(?:arXiv[:\s]*|arxiv\.org/(?:abs|pdf)/)(\d{4}\.\d{4,5}(?:v\d+)?)"#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    private static func extractYear(from text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"\b(19\d{2}|20[0-3]\d)\b"#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    private static func drawSingleLine(
        _ text: String,
        font: CTFont,
        color: CGColor,
        at point: CGPoint,
        in ctx: CGContext
    ) {
        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
        ctx.saveGState()
        ctx.textMatrix = .identity
        ctx.textPosition = point
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    private static func makeSRGBColor(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1.0) -> CGColor {
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        var comps: [CGFloat] = [r, g, b, a]
        return CGColor(colorSpace: space, components: &comps)
            ?? CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: &comps)!
    }

    private static func buildAttributedDossier(
        title: String,
        subtitle: String?,
        markdownBody: String
    ) -> NSAttributedString {
        let out = NSMutableAttributedString()

        let titleFont = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, 18, nil)
        let subFont = CTFontCreateWithName("HelveticaNeue" as CFString, 10.5, nil)
        let h2Font = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, 13.5, nil)
        let h3Font = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, 11.5, nil)
        let bodyFont = CTFontCreateWithName("HelveticaNeue" as CFString, 10.5, nil)
        let boldFont = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, 10.5, nil)

        let inkPrimary = makeSRGBColor(0.09, 0.12, 0.16, 1.0)
        let inkHeading = makeSRGBColor(0.05, 0.34, 0.40, 1.0)
        let inkMuted = makeSRGBColor(0.35, 0.40, 0.47, 1.0)

        func makeParagraphStyle(lineSpacing: CGFloat, spacingBefore: CGFloat = 0, spacingAfter: CGFloat = 5) -> CTParagraphStyle {
            let ls = lineSpacing
            let sb = spacingBefore
            let sa = spacingAfter
            return withUnsafePointer(to: ls) { lsPtr in
                withUnsafePointer(to: sb) { sbPtr in
                    withUnsafePointer(to: sa) { saPtr in
                        let settings: [CTParagraphStyleSetting] = [
                            CTParagraphStyleSetting(spec: .lineSpacingAdjustment, valueSize: MemoryLayout<CGFloat>.size, value: lsPtr),
                            CTParagraphStyleSetting(spec: .paragraphSpacingBefore, valueSize: MemoryLayout<CGFloat>.size, value: sbPtr),
                            CTParagraphStyleSetting(spec: .paragraphSpacing, valueSize: MemoryLayout<CGFloat>.size, value: saPtr)
                        ]
                        return CTParagraphStyleCreate(settings, settings.count)
                    }
                }
            }
        }

        let titleStyle = makeParagraphStyle(lineSpacing: 3, spacingBefore: 0, spacingAfter: 6)
        out.append(NSAttributedString(string: "\(title)\n", attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): titleFont,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): inkPrimary,
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): titleStyle
        ]))

        if let subtitle, !subtitle.isEmpty {
            let subStyle = makeParagraphStyle(lineSpacing: 2, spacingBefore: 0, spacingAfter: 10)
            out.append(NSAttributedString(string: "\(subtitle)\n", attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): subFont,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): inkMuted,
                NSAttributedString.Key(kCTParagraphStyleAttributeName as String): subStyle
            ]))
        }

        let h2Style = makeParagraphStyle(lineSpacing: 2.5, spacingBefore: 10, spacingAfter: 4)
        let h3Style = makeParagraphStyle(lineSpacing: 2, spacingBefore: 7, spacingAfter: 3)
        let bodyStyle = makeParagraphStyle(lineSpacing: 2.5, spacingBefore: 0, spacingAfter: 4)

        for rawLine in markdownBody.components(separatedBy: "\n") {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("# ") {
                // Top title already rendered above
                continue
            } else if trimmed.hasPrefix("## ") {
                let text = String(trimmed.dropFirst(3))
                out.append(NSAttributedString(string: "\(text)\n", attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): h2Font,
                    NSAttributedString.Key(kCTForegroundColorAttributeName as String): inkHeading,
                    NSAttributedString.Key(kCTParagraphStyleAttributeName as String): h2Style
                ]))
            } else if trimmed.hasPrefix("### ") {
                let text = String(trimmed.dropFirst(4))
                out.append(NSAttributedString(string: "\(text)\n", attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): h3Font,
                    NSAttributedString.Key(kCTForegroundColorAttributeName as String): inkPrimary,
                    NSAttributedString.Key(kCTParagraphStyleAttributeName as String): h3Style
                ]))
            } else {
                var clean = trimmed
                if clean.hasPrefix("- ") || clean.hasPrefix("* ") {
                    clean = "• " + clean.dropFirst(2)
                }
                // Simplify markdown links [Title](URL) -> Title (URL)
                clean = clean.replacingOccurrences(
                    of: #"\[([^\]]+)\]\((https?://[^\s\)]+)\)"#,
                    with: "$1 ($2)",
                    options: .regularExpression
                )
                clean = clean.replacingOccurrences(of: "`", with: "")

                let lineAttr = NSMutableAttributedString()
                let parts = clean.components(separatedBy: "**")
                for (idx, part) in parts.enumerated() where !part.isEmpty {
                    let isBold = (idx % 2 == 1)
                    lineAttr.append(NSAttributedString(string: part, attributes: [
                        NSAttributedString.Key(kCTFontAttributeName as String): isBold ? boldFont : bodyFont,
                        NSAttributedString.Key(kCTForegroundColorAttributeName as String): inkPrimary,
                        NSAttributedString.Key(kCTParagraphStyleAttributeName as String): bodyStyle
                    ]))
                }
                lineAttr.append(NSAttributedString(string: "\n", attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): bodyFont,
                    NSAttributedString.Key(kCTParagraphStyleAttributeName as String): bodyStyle
                ]))
                out.append(lineAttr)
            }
        }

        return out
    }
}

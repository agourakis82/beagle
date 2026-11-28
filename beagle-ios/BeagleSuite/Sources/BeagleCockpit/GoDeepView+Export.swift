//
//  GoDeepView+Export.swift
//  BeagleCockpit
//
//  Scientific dossier export menu, Markdown / PDF / BibTeX export actions,
//  citation harvesting, and platform-native file sharing sheet.
//

import SwiftUI
import BeagleCore
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct ExportedDossierItem: Identifiable {
    let id = UUID()
    let url: URL
    let label: String

    internal init(url: URL, label: String) {
        self.url = url
        self.label = label
    }
}

extension GoDeepView {

    // MARK: - Export Toolbar Menu

    var dossierExportMenu: some View {
        Menu {
            Button {
                exportPDFDossier()
            } label: {
                Label("Exportar PDF Científico (.pdf)", systemImage: "doc.richtext.fill")
            }

            Button {
                exportMarkdownDossier()
            } label: {
                Label("Exportar Dossiê Markdown (.md)", systemImage: "doc.text.fill")
            }

            Button {
                Task { await exportBibTeXDossier() }
            } label: {
                Label("Exportar BibTeX Verificado (.bib)", systemImage: "books.vertical.fill")
            }

            Divider()

            Button {
                Task { await copyBibTeXToClipboard() }
            } label: {
                Label(
                    copiedBibTeXFeedback ? "BibTeX Copiado!" : "Copiar BibTeX (DOI/PMID/arXiv)",
                    systemImage: copiedBibTeXFeedback ? "checkmark.circle.fill" : "doc.on.doc"
                )
            }
        } label: {
            if isPreparingExport {
                ProgressView()
                    .controlSize(.small)
                    .tint(BeagleTheme.truthObserved)
            } else {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(BeagleTheme.truthObserved)
            }
        }
        .accessibilityIdentifier("godeep.toolbar.exportMenu")
    }

    // MARK: - Scientific Dossier Export (.pdf · .md · .bib)

    func currentHarvestedCitations() -> [ScientificDossierExporter.HarvestedCitation] {
        ScientificDossierExporter.harvestCitations(
            prompt: prompt,
            modalityStates: store.modalityStates,
            synthesis: store.synthesis,
            roundTable: roundTable.result
        )
    }

    private func currentDossierMarkdown() -> String {
        ScientificDossierExporter.buildMarkdown(
            prompt: prompt,
            startedAt: store.activeSession?.startedAt,
            completedAt: store.activeSession?.completedAt ?? .now,
            modalityStates: store.modalityStates,
            hypotheses: store.hypotheses,
            interference: store.interferenceResult,
            synthesis: store.synthesis,
            roundTable: roundTable.result,
            simulationOutput: store.simulationOutput
        )
    }

    func exportMarkdownDossier() {
        let md = currentDossierMarkdown()
        guard let data = md.data(using: .utf8),
              let url = try? ScientificDossierExporter.writeTemporaryExportFile(
                  prompt: prompt,
                  fileExtension: "md",
                  data: data
              ) else { return }
        exportedItem = ExportedDossierItem(url: url, label: "Dossiê Markdown")
    }

    func exportPDFDossier() {
        let citations = currentHarvestedCitations()
        let md = currentDossierMarkdown()
        let subtitle = "Questão: \(prompt) · \(citations.count) referência(s) verificada(s)"
        let pdfData = ScientificDossierExporter.renderPDFData(
            title: "Dossiê Científico — Beagle Modo Fundo",
            subtitle: subtitle,
            markdownBody: md,
            citations: citations
        )
        guard !pdfData.isEmpty,
              let url = try? ScientificDossierExporter.writeTemporaryExportFile(
                  prompt: prompt,
                  fileExtension: "pdf",
                  data: pdfData
              ) else { return }
        exportedItem = ExportedDossierItem(url: url, label: "Dossiê PDF")
    }

    func exportBibTeXDossier() async {
        isPreparingExport = true
        defer { isPreparingExport = false }
        let citations = currentHarvestedCitations()
        let bib = await ScientificDossierExporter.buildEnrichedBibTeX(
            prompt: prompt,
            citations: citations
        )
        guard let data = bib.data(using: .utf8),
              let url = try? ScientificDossierExporter.writeTemporaryExportFile(
                  prompt: prompt,
                  fileExtension: "bib",
                  data: data
              ) else { return }
        exportedItem = ExportedDossierItem(url: url, label: "BibTeX")
    }

    func copyBibTeXToClipboard() async {
        isPreparingExport = true
        let citations = currentHarvestedCitations()
        let bib = await ScientificDossierExporter.buildEnrichedBibTeX(
            prompt: prompt,
            citations: citations
        )
        isPreparingExport = false
        #if canImport(UIKit)
        UIPasteboard.general.string = bib
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(bib, forType: .string)
        #endif
        copiedBibTeXFeedback = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copiedBibTeXFeedback = false
        }
    }
}

// MARK: - Native File Share Sheet (.pdf / .md / .bib)

#if canImport(UIKit)
struct DossierShareSheet: UIViewControllerRepresentable {
    let url: URL

    internal init(url: URL) {
        self.url = url
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#else
struct DossierShareSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    internal init(url: URL) {
        self.url = url
    }

    var body: some View {
        VStack(spacing: BeagleSpacing.md) {
            Image(systemName: "doc.badge.arrow.up.fill")
                .font(.system(size: 32))
                .foregroundStyle(BeagleTheme.truthObserved)
            Text(url.lastPathComponent)
                .font(BeagleFont.headline.font)
            ShareLink(item: url) {
                Label("Compartilhar arquivo", systemImage: "square.and.arrow.up")
            }
            Button("Fechar") { dismiss() }
        }
        .padding(BeagleSpacing.xl)
    }
}
#endif

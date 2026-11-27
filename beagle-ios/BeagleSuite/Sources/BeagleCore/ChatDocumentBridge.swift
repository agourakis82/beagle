//
//  ChatDocumentBridge.swift
//  BeagleCore
//
//  Extração determinística de PDFs (artigos científicos, laudos, exames, prontuários)
//  com fallback automático de OCR (Apple Vision) para páginas escaneadas + miniatura
//  visual da 1ª página, além da caixa de entrada multimodal compartilhada com o
//  Share Sheet do iOS (`BeagleShare` via App Group `group.dev.sounio.cockpit`).
//

import Foundation
#if canImport(PDFKit) && !os(watchOS)
import PDFKit
import CoreGraphics
#endif
#if canImport(ImageIO) && canImport(UniformTypeIdentifiers)
import ImageIO
import UniformTypeIdentifiers
#endif
#if canImport(Vision) && !os(watchOS)
import Vision
#endif

// MARK: - PDF Document Payload

public struct ChatDocumentPayload: Sendable, Equatable {
    public let fileName: String
    public let pageCount: Int
    public let extractedText: String
    public let ocrUsedPages: Int
    public let coverJPEGData: Data?

    public init(
        fileName: String,
        pageCount: Int,
        extractedText: String,
        ocrUsedPages: Int = 0,
        coverJPEGData: Data? = nil
    ) {
        self.fileName = fileName
        self.pageCount = pageCount
        self.extractedText = extractedText
        self.ocrUsedPages = ocrUsedPages
        self.coverJPEGData = coverJPEGData
    }

    public var summaryBadge: String {
        let pag = pageCount == 1 ? "1 pág." : "\(pageCount) pág."
        if ocrUsedPages > 0 {
            return "\(fileName) · \(pag) · OCR"
        }
        return "\(fileName) · \(pag)"
    }

    public func promptBlock(maxChars: Int = 32_000) -> String {
        let trimmed = extractedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let body: String
        if trimmed.isEmpty {
            body = "(Nenhum texto selecionável pôde ser extraído; analise a renderização visual da página anexada.)"
        } else if trimmed.count > maxChars {
            body = String(trimmed.prefix(maxChars)) + "\n\n[… texto truncado após \(maxChars) caracteres de \(pageCount) páginas …]"
        } else {
            body = trimmed
        }
        return """
        ## Documento PDF anexado neste turno: \(fileName) (\(pageCount) páginas)
        \(body)
        """
    }

    public static func extract(from url: URL, maxPages: Int = 40, maxCharacters: Int = 36_000) async -> ChatDocumentPayload? {
        await Task.detached(priority: .userInitiated) {
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
            }
            guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
            let name = url.lastPathComponent.isEmpty ? "documento.pdf" : url.lastPathComponent
            return Self.extractSync(from: data, fileName: name, maxPages: maxPages, maxCharacters: maxCharacters)
        }.value
    }

    public static func extract(
        from pdfData: Data,
        fileName: String = "documento.pdf",
        maxPages: Int = 40,
        maxCharacters: Int = 36_000
    ) async -> ChatDocumentPayload? {
        await Task.detached(priority: .userInitiated) {
            Self.extractSync(from: pdfData, fileName: fileName, maxPages: maxPages, maxCharacters: maxCharacters)
        }.value
    }

    nonisolated public static func extractSync(
        from pdfData: Data,
        fileName: String = "documento.pdf",
        maxPages: Int = 40,
        maxCharacters: Int = 36_000
    ) -> ChatDocumentPayload? {
        guard !pdfData.isEmpty else { return nil }
        #if canImport(PDFKit) && !os(watchOS)
        guard let doc = PDFDocument(data: pdfData) else { return nil }
        let totalPages = doc.pageCount
        guard totalPages > 0 else { return nil }

        let coverJPEG: Data? = {
            guard let firstPage = doc.page(at: 0),
                  let cgImage = renderPageToCGImage(firstPage, maxDimension: 1568) else {
                return nil
            }
            return encodeJPEG(cgImage, quality: 0.84)
        }()

        let limitPages = min(totalPages, max(1, maxPages))
        var sections: [String] = []
        var totalChars = 0
        var ocrPages = 0

        for idx in 0..<limitPages {
            guard let page = doc.page(at: idx) else { continue }
            var pageText = (page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

            // Fallback inteligente de OCR via Apple Vision para PDFs escaneados (primeiras 6 páginas)
            if pageText.count < 24 && idx < 6 {
                if let cgImage = renderPageToCGImage(page, maxDimension: 1600) {
                    let ocr = recognizeText(in: cgImage)
                    if !ocr.isEmpty {
                        pageText = ocr
                        ocrPages += 1
                    }
                }
            }

            guard !pageText.isEmpty else { continue }
            let block = "[Pág. \(idx + 1)]\n\(pageText)"
            sections.append(block)
            totalChars += block.count
            if totalChars >= maxCharacters { break }
        }

        let joined = sections.joined(separator: "\n\n")
        let capped = joined.count > maxCharacters ? String(joined.prefix(maxCharacters)) : joined

        return ChatDocumentPayload(
            fileName: fileName,
            pageCount: totalPages,
            extractedText: capped,
            ocrUsedPages: ocrPages,
            coverJPEGData: coverJPEG
        )
        #else
        return nil
        #endif
    }

    #if canImport(PDFKit) && !os(watchOS)
    nonisolated private static func renderPageToCGImage(_ page: PDFPage, maxDimension: CGFloat) -> CGImage? {
        let rect = page.bounds(for: .mediaBox)
        guard rect.width > 1, rect.height > 1 else { return nil }
        let longest = max(rect.width, rect.height)
        let scale = min(2.5, max(1.0, maxDimension / longest))
        let width = max(1, Int((rect.width * scale).rounded()))
        let height = max(1, Int((rect.height * scale).rounded()))

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            return nil
        }

        ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.saveGState()
        ctx.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: ctx)
        ctx.restoreGState()
        return ctx.makeImage()
    }

    nonisolated private static func encodeJPEG(_ cgImage: CGImage, quality: Double) -> Data? {
        #if canImport(ImageIO) && canImport(UniformTypeIdentifiers)
        let mutableData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            mutableData as CFMutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        let props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(dest, cgImage, props as CFDictionary)
        guard CGImageDestinationFinalize(dest), mutableData.length > 0 else { return nil }
        return mutableData as Data
        #else
        return nil
        #endif
    }

    nonisolated private static func recognizeText(in cgImage: CGImage) -> String {
        #if canImport(Vision) && !os(watchOS)
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = true
        req.recognitionLanguages = ["pt-BR", "en-US"]
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([req])
        return (req.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #else
        return ""
        #endif
    }
    #endif
}

// MARK: - App Group Multimodal Chat Inbox (BeagleShare -> BeagleCockpit)

public struct SharedChatDraftItem: Codable, Sendable, Equatable {
    public let id: String
    public let createdAt: Date
    public let text: String
    public let urls: [String]
    public let imageFileName: String?
    public let pdfFileName: String?
    public let originalPDFName: String?

    public init(
        id: String = UUID().uuidString,
        createdAt: Date = .now,
        text: String,
        urls: [String] = [],
        imageFileName: String? = nil,
        pdfFileName: String? = nil,
        originalPDFName: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.text = text
        self.urls = urls
        self.imageFileName = imageFileName
        self.pdfFileName = pdfFileName
        self.originalPDFName = originalPDFName
    }
}

public struct SharedChatLoadedPayload: Sendable {
    public let item: SharedChatDraftItem
    public let imageData: Data?
    public let pdfData: Data?
}

public enum BeagleSharedInbox {
    public static let appGroupId = "group.dev.sounio.cockpit"
    private static let folderName = "SharedChatInbox"
    private static let manifestName = "shared_chat_queue.json"
    private static let lock = NSLock()

    public static func inboxDirectory(overrideRoot: URL? = nil) -> URL? {
        let base = overrideRoot ?? FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId)
        guard let base else { return nil }
        let dir = base.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @discardableResult
    public static func enqueue(
        text: String,
        urls: [String] = [],
        imageData: Data? = nil,
        pdfData: Data? = nil,
        originalPDFName: String? = nil,
        overrideRoot: URL? = nil
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let dir = inboxDirectory(overrideRoot: overrideRoot) else { return false }

        let id = UUID().uuidString.lowercased()
        var imageFile: String?
        var pdfFile: String?

        if let imageData, !imageData.isEmpty {
            let fname = "\(id).jpg"
            let fpath = dir.appendingPathComponent(fname)
            if (try? imageData.write(to: fpath, options: .atomic)) != nil {
                imageFile = fname
            }
        }

        if let pdfData, !pdfData.isEmpty {
            let fname = "\(id).pdf"
            let fpath = dir.appendingPathComponent(fname)
            if (try? pdfData.write(to: fpath, options: .atomic)) != nil {
                pdfFile = fname
            }
        }

        let item = SharedChatDraftItem(
            id: id,
            createdAt: .now,
            text: text,
            urls: urls,
            imageFileName: imageFile,
            pdfFileName: pdfFile,
            originalPDFName: originalPDFName
        )

        let manifestURL = dir.appendingPathComponent(manifestName)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var queue: [SharedChatDraftItem] = []
        if let raw = try? Data(contentsOf: manifestURL),
           let decoded = try? decoder.decode([SharedChatDraftItem].self, from: raw) {
            queue = decoded
        }
        queue.append(item)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let encoded = try? encoder.encode(queue) else { return false }
        return (try? encoded.write(to: manifestURL, options: .atomic)) != nil
    }

    public static func dequeueNext(overrideRoot: URL? = nil) -> SharedChatLoadedPayload? {
        lock.lock()
        defer { lock.unlock() }
        guard let dir = inboxDirectory(overrideRoot: overrideRoot) else { return nil }
        let manifestURL = dir.appendingPathComponent(manifestName)
        guard let raw = try? Data(contentsOf: manifestURL) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard var queue = try? decoder.decode([SharedChatDraftItem].self, from: raw),
              !queue.isEmpty else {
            return nil
        }

        let next = queue.removeFirst()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if queue.isEmpty {
            try? FileManager.default.removeItem(at: manifestURL)
        } else if let encoded = try? encoder.encode(queue) {
            try? encoded.write(to: manifestURL, options: .atomic)
        }

        var loadedImage: Data?
        if let imgName = next.imageFileName {
            let imgURL = dir.appendingPathComponent(imgName)
            loadedImage = try? Data(contentsOf: imgURL)
            try? FileManager.default.removeItem(at: imgURL)
        }

        var loadedPDF: Data?
        if let pdfName = next.pdfFileName {
            let pdfURL = dir.appendingPathComponent(pdfName)
            loadedPDF = try? Data(contentsOf: pdfURL)
            try? FileManager.default.removeItem(at: pdfURL)
        }

        return SharedChatLoadedPayload(item: next, imageData: loadedImage, pdfData: loadedPDF)
    }
}

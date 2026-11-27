#if os(iOS)
import Foundation
import UIKit
import Vision

struct VisualEvidenceLocalAnalysis: Sendable {
    var summary: String
    var extractedText: String
    var hints: [String]
    var faceCount: Int
    var barcodeCount: Int
    var rectangleCount: Int
    var tables: [[[String]]] = []
    var documentJSON: String? = nil
    var faceDetectionSucceeded = false
}

actor VisualEvidenceLocalAnalyzer {
    static let shared = VisualEvidenceLocalAnalyzer()
    func analyze(data: Data, sourceKind: String) async -> VisualEvidenceLocalAnalysis {
        guard let image = UIImage(data: data), let cgImage = image.cgImage else {
            return VisualEvidenceLocalAnalysis(
                summary: "Image captured from \(sourceKind); local Vision could not read pixels.",
                extractedText: "",
                hints: ["visionkit-local-first", "image-unreadable"],
                faceCount: 0,
                barcodeCount: 0,
                rectangleCount: 0
            )
        }

        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = true

        let faceRequest = VNDetectFaceRectanglesRequest()
        let barcodeRequest = VNDetectBarcodesRequest()
        let rectangleRequest = VNDetectRectanglesRequest()
        let classifyRequest = VNClassifyImageRequest()

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        // Isolate optional detectors so one unavailable model cannot discard OCR.
        var failedDetectors: [String] = []
        for (name, request) in [
            ("ocr", textRequest as VNRequest),
            ("face-detection", faceRequest),
            ("barcode-detection", barcodeRequest),
            ("rectangle-detection", rectangleRequest),
            ("classification", classifyRequest)
        ] {
            do {
                try handler.perform([request])
            } catch {
                failedDetectors.append(name)
            }
        }
        let faceDetectionSucceeded = !failedDetectors.contains("face-detection")

        var recognizedText = (textRequest.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
        var tables: [[[String]]] = []
        var documentJSON: String?
        var usedDocumentRecognition = false
        if #available(iOS 26, *) {
            do {
                try Task.checkCancellation()
                let observations = try await RecognizeDocumentsRequest().perform(on: data)
                if !observations.isEmpty {
                    recognizedText = observations.map { $0.document.text.transcript }.joined(separator: "\n\n")
                    tables = observations.flatMap { observation in
                        observation.document.tables.map { table in
                            table.rows.map { row in row.map { $0.content.text.transcript } }
                        }
                    }
                    // Retain source regions and cell ranges alongside the editable transcript.
                    documentJSON = String(data: try JSONEncoder().encode(observations), encoding: .utf8)
                    usedDocumentRecognition = true
                }
            } catch {
                // The complete OCR transcript remains available when document recognition fails.
            }
        }
        let faces = faceRequest.results?.count ?? 0
        let barcodes = barcodeRequest.results?.count ?? 0
        let rectangles = rectangleRequest.results?.count ?? 0
        let labels = (classifyRequest.results ?? [])
            .prefix(4)
            .map { "\($0.identifier) \(Int($0.confidence * 100))%" }
        var hints = ["visionkit-local-first", sourceKind] + failedDetectors.map { "\($0)-unavailable" }
        if !recognizedText.isEmpty { hints.append("ocr") }
        if usedDocumentRecognition { hints.append("structured-document") }
        if faces > 0 { hints.append("faces-detected") }
        if barcodes > 0 { hints.append("barcode-detected") }
        if rectangles > 0 { hints.append("document-layout") }
        if !labels.isEmpty { hints.append("classification") }

        var summaryParts = ["\(sourceKind.capitalized) captured for visual evidence."]
        if !labels.isEmpty {
            summaryParts.append("Local labels: \(labels.joined(separator: ", ")).")
        }
        if !recognizedText.isEmpty {
            summaryParts.append("OCR extracted \(recognizedText.count) characters.")
        }
        if !faceDetectionSucceeded {
            summaryParts.append("Face detection unavailable; review sensitive visual context before upload.")
        }
        if faces > 0 {
            summaryParts.append("Possible faces/person context detected; require explicit review before upload.")
        }
        if rectangles > 0 {
            summaryParts.append("Document/diagram layout signals detected.")
        }

        if #available(iOS 27.2, *) {
            if let afmInsight = await FoundationModelsAgent.shared.analyzeImage(
                cgImage,
                prompt: "Summarize the scientific, clinical, or structural content visible in this \(sourceKind) in 1-2 concise sentences.",
                localOnly: true
            ) {
                hints.append("afm3-multimodal")
                summaryParts.append("Local AFM 3 insight: \(afmInsight)")
            }
        }

        return VisualEvidenceLocalAnalysis(
            summary: summaryParts.joined(separator: " "),
            extractedText: recognizedText,
            hints: hints,
            faceCount: faces,
            barcodeCount: barcodes,
            rectangleCount: rectangles,
            tables: tables,
            documentJSON: documentJSON,
            faceDetectionSucceeded: faceDetectionSucceeded
        )
    }
}

#endif

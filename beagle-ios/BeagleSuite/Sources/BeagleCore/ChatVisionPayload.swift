//
//  ChatVisionPayload.swift
//  BeagleCore
//
//  Normalized JPEG + on-device Vision OCR/classification digest for multimodal
//  chat turns, plus the structured turn representation passed to DirectBrainClient.
//

import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif
#if canImport(ImageIO) && canImport(UniformTypeIdentifiers)
import ImageIO
import UniformTypeIdentifiers
#endif
#if canImport(Vision)
import Vision
#endif

// MARK: - Multimodal Vision Payload & Turn Representation

/// Normalized JPEG + on-device Vision OCR/classification digest for multimodal chat turns.
/// Prepared off the main actor via ImageIO + Apple Vision so 48MP photos never stall the UI,
/// work seamlessly with OpenAI Vision, Anthropic Vision, Cluster artifacts, AND give text-only
/// local MLX models ("Local Sem Censura" / MoE Layer 1) full OCR + visual context offline.
public struct ChatVisionPayload: Sendable {
    public let jpegData: Data
    public let base64JPEG: String
    public let mimeType: String
    public let sha256Hex: String
    public let extractedOCR: String
    public let visualLabels: [String]
    public let barcodes: [String]
    public let pixelWidth: Int
    public let pixelHeight: Int

    /// Compact summary injected into text-only models (Local MLX / MoE Layer 1 / Search / Memory).
    public var localDigest: String {
        var parts: [String] = []
        if pixelWidth > 0, pixelHeight > 0 {
            parts.append("resolução \(pixelWidth)×\(pixelHeight)")
        }
        if !visualLabels.isEmpty {
            parts.append("cena: " + visualLabels.joined(separator: ", "))
        }
        if !barcodes.isEmpty {
            parts.append("códigos: " + barcodes.joined(separator: ", "))
        }
        if !extractedOCR.isEmpty {
            parts.append("texto OCR na imagem:\n\(extractedOCR)")
        }
        return parts.joined(separator: " · ")
    }

    public static func prepare(
        from rawData: Data,
        maxPixelSize: Int = 1568,
        compressionQuality: Double = 0.84
    ) async -> ChatVisionPayload {
        await Task.detached(priority: .userInitiated) {
            Self.prepareSync(
                from: rawData,
                maxPixelSize: maxPixelSize,
                compressionQuality: compressionQuality
            )
        }.value
    }

    private static func prepareSync(
        from rawData: Data,
        maxPixelSize: Int,
        compressionQuality: Double
    ) -> ChatVisionPayload {
        var finalJPEG = rawData
        var width = 0
        var height = 0
        var ocrText = ""
        var labels: [String] = []
        var codes: [String] = []

        #if canImport(ImageIO) && canImport(UniformTypeIdentifiers)
        if let source = CGImageSourceCreateWithData(rawData as CFData, nil) {
            let thumbOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
            ]
            if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) {
                width = cgImage.width
                height = cgImage.height

                let mutableData = NSMutableData()
                if let dest = CGImageDestinationCreateWithData(
                    mutableData as CFMutableData,
                    UTType.jpeg.identifier as CFString,
                    1,
                    nil
                ) {
                    let destProps: [CFString: Any] = [
                        kCGImageDestinationLossyCompressionQuality: compressionQuality
                    ]
                    CGImageDestinationAddImage(dest, cgImage, destProps as CFDictionary)
                    if CGImageDestinationFinalize(dest), mutableData.length > 0 {
                        finalJPEG = mutableData as Data
                    }
                }

                #if canImport(Vision) && !os(watchOS)
                let textReq = VNRecognizeTextRequest()
                textReq.recognitionLevel = .accurate
                textReq.usesLanguageCorrection = true
                textReq.recognitionLanguages = ["pt-BR", "en-US"]

                let classifyReq = VNClassifyImageRequest()
                let barcodeReq = VNDetectBarcodesRequest()

                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                try? handler.perform([textReq, classifyReq, barcodeReq])

                ocrText = (textReq.results ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                    .prefix(40)
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                labels = (classifyReq.results ?? [])
                    .filter { $0.confidence >= 0.25 }
                    .prefix(4)
                    .map { "\($0.identifier) (\(Int(($0.confidence * 100).rounded()))%)" }

                codes = (barcodeReq.results ?? [])
                    .compactMap(\.payloadStringValue)
                    .prefix(4)
                    .map { $0 }
                #endif
            }
        }
        #endif

        let sha: String = {
            #if canImport(CryptoKit)
            let digest = SHA256.hash(data: finalJPEG)
            return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
            #else
            return "sha256:\(abs(finalJPEG.hashValue))"
            #endif
        }()

        return ChatVisionPayload(
            jpegData: finalJPEG,
            base64JPEG: finalJPEG.base64EncodedString(),
            mimeType: "image/jpeg",
            sha256Hex: sha,
            extractedOCR: ocrText,
            visualLabels: labels,
            barcodes: codes,
            pixelWidth: width,
            pixelHeight: height
        )
    }
}

/// Structured multimodal turn passed to `DirectBrainClient` (OpenAI Vision & Anthropic Vision).
public struct DirectBrainTurn: Sendable {
    public let role: String
    public let content: String
    public let imageBase64: String?
    public let imageMediaType: String?

    public init(
        role: String,
        content: String,
        imageBase64: String? = nil,
        imageMediaType: String? = nil
    ) {
        self.role = role
        self.content = content
        self.imageBase64 = imageBase64
        self.imageMediaType = imageMediaType
    }
}

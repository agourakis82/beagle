//
//  MultimodalComposer.swift
//  BeagleCockpit
//
//  Beagle v3.0: Text / Voice / Image capture with visible state, local-first
//  processing, and Sounio-typed review before durable memory promotion.
//

import SwiftUI
import BeagleCore
#if canImport(CryptoKit)
import CryptoKit
#endif
#if os(iOS)
import PhotosUI
import UIKit
import Vision
import VisionKit
#endif

enum ComposerMode: String, CaseIterable, Identifiable {
    case text
    case voice
    case image

    var id: String { rawValue }

    var label: String {
        switch self {
        case .text: return "Text"
        case .voice: return "Voice"
        case .image: return "Image"
        }
    }

    var icon: String {
        switch self {
        case .text: return "text.cursor"
        case .voice: return "waveform"
        case .image: return "viewfinder"
        }
    }
}

struct MultimodalComposer: View {
    @Binding var text: String
    @Binding var mode: ComposerMode
    let timeline: [ChatMemoryTimelineEvent]
    let isEnabled: Bool
    let onSubmit: (String) -> Void
    let onVoice: () -> Void
    let onImage: () -> Void

    var body: some View {
        GlassPanel(elevation: .raised) {
            VStack(alignment: .leading, spacing: BeagleSpacing.md) {
                HStack(spacing: BeagleSpacing.xs) {
                    ForEach(ComposerMode.allCases) { item in
                        Button {
                            withAnimation(BeagleMotion.snappy) {
                                mode = item
                            }
                        } label: {
                            Label(item.label, systemImage: item.icon)
                                .font(BeagleFont.caption.font)
                                .frame(minWidth: 74, minHeight: 36)
                                .foregroundStyle(mode == item ? BeagleTheme.truthObserved : BeagleTheme.textSecondary)
                                .background(
                                    Capsule()
                                        .fill(mode == item ? BeagleTheme.truthObserved.opacity(0.14) : Color.white.opacity(0.04))
                                )
                        }
                        .buttonStyle(.plain)
                        .sensoryFeedback(.selection, trigger: mode)
                    }

                    Spacer(minLength: BeagleSpacing.sm)

                    MemoryTimelineButton(events: timeline)
                }

                switch mode {
                case .text:
                    BeagleInputBar(
                        text: $text,
                        placeholder: "Capturar ideia, pedir análise ou tipar um momento Sounio...",
                        mode: .chat,
                        isEnabled: isEnabled,
                        onSubmit: onSubmit
                    )
                case .voice:
                    composerActionRow(
                        title: "Thinking Aloud",
                        subtitle: "Sessão explícita, transcrição local primeiro, áudio descartado.",
                        icon: "mic.badge.plus",
                        actionTitle: "Abrir voz",
                        action: onVoice
                    )
                case .image:
                    composerActionRow(
                        title: "Visual Evidence",
                        subtitle: "Diagrama, foto, screenshot ou documento viram evidência revisável.",
                        icon: "camera.metering.matrix",
                        actionTitle: "Analisar imagem",
                        action: onImage
                    )
                }
            }
        }
    }

    private func composerActionRow(
        title: String,
        subtitle: String,
        icon: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: BeagleSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(BeagleTheme.truthObserved)
                .frame(width: 38, height: 38)
                .background(Circle().fill(BeagleTheme.truthObserved.opacity(0.1)))

            VStack(alignment: .leading, spacing: BeagleSpacing.xxs) {
                Text(title)
                    .font(BeagleFont.callout.font)
                    .foregroundStyle(BeagleTheme.textPrimary)
                Text(subtitle)
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textTertiary)
                    .lineLimit(2)
            }

            Spacer(minLength: BeagleSpacing.sm)

            Button(action: action) {
                Label(actionTitle, systemImage: "arrow.up.right")
                    .labelStyle(.iconOnly)
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.plain)
            .foregroundStyle(BeagleTheme.truthObserved)
            .background(Circle().fill(Color.white.opacity(0.06)))
            .accessibilityLabel(actionTitle)
        }
    }
}

private struct MemoryTimelineButton: View {
    let events: [ChatMemoryTimelineEvent]
    @State private var showingTimeline = false

    var body: some View {
        Button {
            showingTimeline = true
        } label: {
            Image(systemName: events.isEmpty ? "clock" : "clock.badge.checkmark")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 36, height: 36)
                .foregroundStyle(events.isEmpty ? BeagleTheme.textTertiary : BeagleTheme.truthObserved)
                .background(Circle().fill(Color.white.opacity(0.05)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Memory timeline")
        .sheet(isPresented: $showingTimeline) {
            NavigationStack {
                List {
                    if events.isEmpty {
                        Text("No memory events yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(events) { event in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(event.label)
                                    .font(.headline)
                                Text(event.status)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .navigationTitle("Memory Timeline")
            }
            .presentationDetents([.medium, .large])
        }
    }
}

struct ThinkingAloudSessionView: View {
    let projectSlug: String
    let onCandidates: ([CaptureReviewCandidate]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var captureSession: CaptureSession?
    @State private var statusLine = "Ready"
    @State private var isReviewing = false
    @State private var candidates: [CaptureReviewCandidate] = []

    #if os(iOS)
    @State private var speechRecognizer = SpeechRecognizer()
    #endif

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: BeagleSpacing.lg) {
                GlassPanel(elevation: .floating, truth: .observed) {
                    VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                        HStack {
                            Label("Thinking Aloud", systemImage: "waveform")
                                .font(BeagleFont.title3.font)
                                .foregroundStyle(BeagleTheme.textPrimary)
                            Spacer()
                            Text(statusLine)
                                .font(BeagleFont.caption.font)
                                .foregroundStyle(BeagleTheme.truthObserved)
                        }

                        Text("Escuta só quando você inicia. Transcrição local primeiro; áudio bruto não vira memória canônica.")
                            .font(BeagleFont.footnote.font)
                            .foregroundStyle(BeagleTheme.textSecondary)
                    }
                }

                transcriptPanel

                Spacer(minLength: BeagleSpacing.lg)

                controls
            }
            .padding(BeagleSpacing.lg)
            .background(BeagleTheme.surface0)
            .navigationTitle("Voice Capture")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            #if os(iOS)
            .task { await speechRecognizer.setup() }
            #endif
            .sheet(isPresented: $isReviewing) {
                CaptureReviewSheet(candidates: candidates) { selected in
                    onCandidates(selected)
                    dismiss()
                }
            }
        }
    }

    @ViewBuilder
    private var transcriptPanel: some View {
        #if os(iOS)
        GlassPanel {
            VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                Text(speechRecognizer.transcript.isEmpty ? "Transcript will appear here." : speechRecognizer.transcript)
                    .font(BeagleFont.body.font)
                    .foregroundStyle(speechRecognizer.transcript.isEmpty ? BeagleTheme.textTertiary : BeagleTheme.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
                    .textSelection(.enabled)

                if let error = speechRecognizer.error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.stateError)
                }
            }
        }
        #else
        GlassPanel {
            Label("Voice capture is available on iPhone.", systemImage: "mic.slash")
                .foregroundStyle(BeagleTheme.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 160)
        }
        #endif
    }

    @ViewBuilder
    private var controls: some View {
        #if os(iOS)
        if speechRecognizer.isRecording {
            HStack(spacing: BeagleSpacing.sm) {
                Button {
                    Task { await stopAndReview() }
                } label: {
                    Label("Stop & Review", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(PrimaryButton())
                .disabled(speechRecognizer.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    speechRecognizer.stopRecording()
                    statusLine = "Discarded locally"
                } label: {
                    Label("Discard", systemImage: "xmark")
                }
                .buttonStyle(SecondaryButton(color: BeagleTheme.stateError))
            }
        } else {
            Button {
                Task { await startSession() }
            } label: {
                Label("Start Listening", systemImage: "mic.fill")
            }
            .buttonStyle(PrimaryButton())
        }
        #else
        EmptyView()
        #endif
    }

    #if os(iOS)
    private func startSession() async {
        let request = CaptureSessionStartRequest(
            projectSlug: projectSlug,
            mode: "thinking_aloud",
            surface: "beagle-ios-thinking-aloud",
            title: "Thinking Aloud \(projectSlug)",
            metadata: .object([
                "anti_creepy_policy": .string("explicit_session_only"),
                "raw_audio_policy": .string("local_ttl_short_discard_after_transcription")
            ])
        )
        let result = await BeagleClient.shared.captureSessionStart(request)
        captureSession = result.value
        statusLine = result.value == nil ? "Local only" : "Observed"
        // Tags voice-acoustic samples back to this capture session — same convention as
        // ThoughtCaptureView's persistenceConversationId.
        speechRecognizer.sessionId = captureSession?.id
        await speechRecognizer.startRecording()
    }

    private func stopAndReview() async {
        speechRecognizer.stopRecording()
        let transcript = speechRecognizer.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { return }

        let segment = TranscriptionSegment(
            text: transcript,
            confidence: 0.72,
            source: speechRecognizer.isWhisperReady ? "apple-speech-on-device" : "apple-speech-fallback"
        )

        if let session = captureSession {
            _ = await BeagleClient.shared.captureSessionEvent(
                sessionId: session.id,
                request: CaptureSessionEventRequest(
                    eventType: "transcript_final",
                    text: transcript,
                    transcriptionSegments: [segment],
                    privacyClass: MemoryPrivacyGuard.classify([transcript]),
                    metadata: .object([
                        "raw_audio_retention": .string("discarded_after_stop"),
                        "external_transcription": .bool(false)
                    ])
                )
            )
        }

        candidates = CaptureCandidateBuilder.voiceCandidates(
            transcript: transcript,
            sessionId: captureSession?.id,
            projectSlug: projectSlug
        )
        statusLine = "Review"
        isReviewing = true
    }
    #endif
}

struct VisualEvidenceCaptureView: View {
    let projectSlug: String
    let onCandidates: ([CaptureReviewCandidate]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var localSummary = ""
    @State private var extractedText = ""
    @State private var sourceKind = "diagram"
    @State private var allowExternalModel = false
    @State private var sensitiveVisualAcknowledged = false
    @State private var isSubmitting = false
    @State private var statusLine = "Choose an image source or add local notes."
    @State private var candidates: [CaptureReviewCandidate] = []
    @State private var showingReview = false
    @State private var localHints: [String] = ["visionkit-local-first"]
    @State private var detectedFaceCount = 0
    @State private var detectedBarcodeCount = 0
    @State private var detectedRectangleCount = 0

    #if os(iOS)
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var selectedImageData: Data?
    @State private var showingCamera = false
    @State private var showingDocumentScanner = false
    #endif

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BeagleSpacing.lg) {
                    GlassPanel(elevation: .floating, truth: .observed) {
                        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                            Label("Visual Evidence", systemImage: "viewfinder")
                                .font(BeagleFont.title3.font)
                                .foregroundStyle(BeagleTheme.textPrimary)

                            Text("Capture diagrama, foto, screenshot ou documento. Vision local roda primeiro; modelo externo só depois de confirmação explícita.")
                                .font(BeagleFont.footnote.font)
                                .foregroundStyle(BeagleTheme.textSecondary)
                        }
                    }

                    nativeCaptureControls

                    Picker("Source", selection: $sourceKind) {
                        Text("Diagram").tag("diagram")
                        Text("Whiteboard").tag("whiteboard")
                        Text("Document").tag("document")
                        Text("Photo").tag("photo")
                        Text("Screenshot").tag("screenshot")
                    }
                    .pickerStyle(.segmented)

                    imagePreview

                    VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                        Text("Local summary")
                            .font(BeagleFont.caption.font)
                            .foregroundStyle(BeagleTheme.textSecondary)
                        TextEditor(text: $localSummary)
                            .frame(minHeight: 96)
                            .scrollContentBackground(.hidden)
                            .padding(BeagleSpacing.sm)
                            .background(RoundedRectangle(cornerRadius: BeagleRadius.md).fill(Color.white.opacity(0.05)))
                    }

                    VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                        Text("OCR / layout notes")
                            .font(BeagleFont.caption.font)
                            .foregroundStyle(BeagleTheme.textSecondary)
                        TextEditor(text: $extractedText)
                            .frame(minHeight: 116)
                            .scrollContentBackground(.hidden)
                            .padding(BeagleSpacing.sm)
                            .background(RoundedRectangle(cornerRadius: BeagleRadius.md).fill(Color.white.opacity(0.05)))
                    }

                    SourceConfidenceStripView(
                        hints: localHints,
                        faceCount: detectedFaceCount,
                        barcodeCount: detectedBarcodeCount,
                        rectangleCount: detectedRectangleCount
                    )

                    if detectedFaceCount > 0 {
                        Toggle("I reviewed faces/sensitive visual context", isOn: $sensitiveVisualAcknowledged)
                            .font(BeagleFont.footnote.font)
                            .tint(BeagleTheme.truthObserved)
                    }

                    Toggle("Confirm external multimodal analysis", isOn: $allowExternalModel)
                        .font(BeagleFont.footnote.font)
                        .tint(BeagleTheme.truthObserved)

                    Text(statusLine)
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textTertiary)

                    Button {
                        Task { await analyze() }
                    } label: {
                        Label(isSubmitting ? "Analyzing..." : "Create Claim Map", systemImage: "sparkles")
                    }
                    .buttonStyle(PrimaryButton())
                    .disabled(isSubmitting || !hasVisualMaterial)
                }
                .padding(BeagleSpacing.lg)
            }
            .background(BeagleTheme.surface0)
            .navigationTitle("Image Capture")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            #if os(iOS)
            .onChange(of: selectedPhotoItem) { _, newValue in
                guard let newValue else { return }
                Task { await loadPhotoItem(newValue) }
            }
            .sheet(isPresented: $showingCamera) {
                CameraImagePicker { image in
                    Task { await applyImage(image, source: "photo") }
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showingDocumentScanner) {
                DocumentCameraScanner { image in
                    Task { await applyImage(image, source: "document") }
                }
                .ignoresSafeArea()
            }
            #endif
            .sheet(isPresented: $showingReview) {
                CaptureReviewSheet(candidates: candidates) { selected in
                    onCandidates(selected)
                    dismiss()
                }
            }
        }
    }

    private var hasVisualMaterial: Bool {
        if !localSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        if !extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        #if os(iOS)
        if selectedImageData != nil {
            return true
        }
        #endif
        return false
    }

    @ViewBuilder
    private var nativeCaptureControls: some View {
        #if os(iOS)
        GlassPanel {
            VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                Text("Source")
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textSecondary)

                HStack(spacing: BeagleSpacing.sm) {
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        VisualSourceButton(title: "Photos", icon: "photo.on.rectangle")
                    }
                    .buttonStyle(.plain)

                    Button {
                        sourceKind = "photo"
                        showingCamera = true
                    } label: {
                        VisualSourceButton(title: "Camera", icon: "camera")
                    }
                    .buttonStyle(.plain)
                    .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))

                    Button {
                        sourceKind = "document"
                        showingDocumentScanner = true
                    } label: {
                        VisualSourceButton(title: "Scan", icon: "doc.viewfinder")
                    }
                    .buttonStyle(.plain)

                    Button {
                        pasteImage()
                    } label: {
                        VisualSourceButton(title: "Paste", icon: "doc.on.clipboard")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        #else
        GlassPanel {
            Label("Native visual capture is available on iPhone/iPad. Add local notes here on this platform.", systemImage: "photo.badge.plus")
                .font(BeagleFont.footnote.font)
                .foregroundStyle(BeagleTheme.textSecondary)
        }
        #endif
    }

    @ViewBuilder
    private var imagePreview: some View {
        #if os(iOS)
        if let selectedImage {
            GlassPanel {
                VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                    Image(uiImage: selectedImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 240)
                        .clipShape(RoundedRectangle(cornerRadius: BeagleRadius.md))
                    Text("Raw image will be stored only as a private cluster artifact after review.")
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                }
            }
        }
        #endif
    }

    private func analyze() async {
        isSubmitting = true
        defer { isSubmitting = false }

        let payload = "\(sourceKind)\n\(localSummary)\n\(extractedText)"
        let privacy = MemoryPrivacyGuard.classify([payload])
        guard privacy != "restricted" else {
            statusLine = "Restricted content stays local for explicit review."
            return
        }
        guard detectedFaceCount == 0 || sensitiveVisualAcknowledged else {
            statusLine = "Face/sensitive context detected. Review locally before upload."
            return
        }

        #if os(iOS)
        let artifactData = selectedImageData
        #else
        let artifactData: Data? = nil
        #endif
        let artifactRequest = VisualEvidenceArtifactRequest(
            projectSlug: projectSlug,
            sourceKind: sourceKind,
            mediaType: artifactData == nil ? "text/local-visual-notes" : "image/jpeg",
            contentHash: artifactData.map(Self.sha256Data) ?? Self.sha256(payload),
            artifactDataBase64: artifactData?.base64EncodedString(),
            artifactByteCount: artifactData?.count,
            localSummary: localSummary,
            extractedText: extractedText,
            localHints: localHints + [sourceKind],
            privacyClass: privacy,
            confirmationState: allowExternalModel ? "external_confirmed" : "local_preview_only",
            metadata: .object([
                "external_model_confirmed": .bool(allowExternalModel),
                "raw_image_policy": .string("private_cluster_artifact_only"),
                "face_count": .number(Double(detectedFaceCount)),
                "barcode_count": .number(Double(detectedBarcodeCount)),
                "rectangle_count": .number(Double(detectedRectangleCount))
            ])
        )
        let artifact = await BeagleClient.shared.visualEvidenceArtifact(artifactRequest)
        guard let artifactValue = artifact.value else {
            statusLine = artifact.error ?? "Artifact could not be stored."
            return
        }

        let analysis = await BeagleClient.shared.visualEvidenceAnalyze(
            VisualEvidenceAnalyzeRequest(
                artifactId: artifactValue.id,
                prompt: "Extract claim seeds, evidence refs, tensions, missing evidence, and next actions.",
                allowExternalModel: allowExternalModel,
                preferredProvider: allowExternalModel ? "openai-responses-vision" : "local-only",
                localAnalysis: .object([
                    "summary": .string(localSummary),
                    "source_kind": .string(sourceKind)
                ]),
                redactionSummary: "Local preview supplied by user; raw image is not in public digest."
            )
        )
        candidates = analysis.value?.claimMap ?? CaptureCandidateBuilder.imageCandidates(
            summary: localSummary,
            artifactId: artifactValue.id,
            projectSlug: projectSlug
        )
        statusLine = analysis.value?.requiresConfirmation == true ? "Local claim map ready" : "Confirmed analysis ready"
        showingReview = true
    }

    #if os(iOS)
    private func loadPhotoItem(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data)
            else {
                statusLine = "Could not read selected photo."
                return
            }
            await applyImage(image, source: "photo", originalData: data)
        } catch {
            statusLine = "Photo import failed."
        }
    }

    @MainActor
    private func applyImage(_ image: UIImage, source: String, originalData: Data? = nil) async {
        sourceKind = source
        selectedImage = image
        selectedImageData = image.jpegData(compressionQuality: 0.88) ?? originalData
        statusLine = "Running local Vision analysis..."
        let analysis = VisualEvidenceLocalAnalyzer.analyze(image: image, sourceKind: source)
        localSummary = analysis.summary
        extractedText = analysis.extractedText
        localHints = analysis.hints
        detectedFaceCount = analysis.faceCount
        detectedBarcodeCount = analysis.barcodeCount
        detectedRectangleCount = analysis.rectangleCount
        sensitiveVisualAcknowledged = analysis.faceCount == 0
        statusLine = analysis.faceCount > 0
            ? "Local Vision found possible faces. Review before upload."
            : "Local Vision preview ready."
    }

    @MainActor
    private func pasteImage() {
        guard let image = UIPasteboard.general.image else {
            statusLine = "No image found on clipboard."
            return
        }
        Task { await applyImage(image, source: "screenshot") }
    }
    #endif

    private static func sha256(_ value: String) -> String {
        #if canImport(CryptoKit)
        let digest = SHA256.hash(data: Data(value.utf8))
        return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
        #else
        return "sha256:\(abs(value.hashValue))"
        #endif
    }

    private static func sha256Data(_ data: Data) -> String {
        #if canImport(CryptoKit)
        let digest = SHA256.hash(data: data)
        return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
        #else
        return "sha256:\(abs(data.hashValue))"
        #endif
    }
}

#if os(iOS)
private struct VisualEvidenceLocalAnalysis {
    var summary: String
    var extractedText: String
    var hints: [String]
    var faceCount: Int
    var barcodeCount: Int
    var rectangleCount: Int
}

private struct VisualSourceButton: View {
    let title: String
    let icon: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
            Text(title)
                .font(BeagleFont.caption.font)
        }
        .foregroundStyle(BeagleTheme.textPrimary)
        .frame(maxWidth: .infinity, minHeight: 58)
        .background(RoundedRectangle(cornerRadius: BeagleRadius.md).fill(Color.white.opacity(0.05)))
    }
}

private enum VisualEvidenceLocalAnalyzer {
    static func analyze(image: UIImage, sourceKind: String) -> VisualEvidenceLocalAnalysis {
        guard let cgImage = image.cgImage else {
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
        do {
            try handler.perform([textRequest, faceRequest, barcodeRequest, rectangleRequest, classifyRequest])
        } catch {
            return VisualEvidenceLocalAnalysis(
                summary: "Image captured from \(sourceKind); local Vision failed before external analysis.",
                extractedText: "",
                hints: ["visionkit-local-first", "vision-error"],
                faceCount: 0,
                barcodeCount: 0,
                rectangleCount: 0
            )
        }

        let recognizedText = (textRequest.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .prefix(18)
            .joined(separator: "\n")
        let faces = faceRequest.results?.count ?? 0
        let barcodes = barcodeRequest.results?.count ?? 0
        let rectangles = rectangleRequest.results?.count ?? 0
        let labels = (classifyRequest.results ?? [])
            .prefix(4)
            .map { "\($0.identifier) \(Int($0.confidence * 100))%" }
        var hints = ["visionkit-local-first", sourceKind]
        if !recognizedText.isEmpty { hints.append("ocr") }
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
        if faces > 0 {
            summaryParts.append("Possible faces/person context detected; require explicit review before upload.")
        }
        if rectangles > 0 {
            summaryParts.append("Document/diagram layout signals detected.")
        }

        return VisualEvidenceLocalAnalysis(
            summary: summaryParts.joined(separator: " "),
            extractedText: recognizedText,
            hints: hints,
            faceCount: faces,
            barcodeCount: barcodes,
            rectangleCount: rectangles
        )
    }
}

private struct CameraImagePicker: UIViewControllerRepresentable {
    let onImage: @MainActor (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage, dismiss: dismiss)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, @preconcurrency UIImagePickerControllerDelegate {
        let onImage: @MainActor (UIImage) -> Void
        let dismiss: DismissAction

        init(onImage: @escaping @MainActor (UIImage) -> Void, dismiss: DismissAction) {
            self.onImage = onImage
            self.dismiss = dismiss
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = info[.originalImage] as? UIImage
            let onImage = self.onImage
            let dismiss = self.dismiss
            Task { @MainActor in
                if let image {
                    onImage(image)
                }
                dismiss()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            let dismiss = self.dismiss
            Task { @MainActor in
                dismiss()
            }
        }
    }
}

private struct DocumentCameraScanner: UIViewControllerRepresentable {
    let onImage: @MainActor (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage, dismiss: dismiss)
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, @preconcurrency VNDocumentCameraViewControllerDelegate {
        let onImage: @MainActor (UIImage) -> Void
        let dismiss: DismissAction

        init(onImage: @escaping @MainActor (UIImage) -> Void, dismiss: DismissAction) {
            self.onImage = onImage
            self.dismiss = dismiss
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            let image = scan.pageCount > 0 ? scan.imageOfPage(at: 0) : nil
            let onImage = self.onImage
            let dismiss = self.dismiss
            Task { @MainActor in
                if let image {
                    onImage(image)
                }
                dismiss()
            }
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            let dismiss = self.dismiss
            Task { @MainActor in
                dismiss()
            }
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            let dismiss = self.dismiss
            Task { @MainActor in
                dismiss()
            }
        }
    }
}

private struct SourceConfidenceStripView: View {
    let hints: [String]
    let faceCount: Int
    let barcodeCount: Int
    let rectangleCount: Int

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BeagleSpacing.xs) {
                badge("local", "checkmark.shield")
                if faceCount > 0 {
                    badge("faces \(faceCount)", "person.crop.square")
                }
                if barcodeCount > 0 {
                    badge("codes \(barcodeCount)", "barcode.viewfinder")
                }
                if rectangleCount > 0 {
                    badge("layout \(rectangleCount)", "rectangle.dashed")
                }
                ForEach(Array(Set(hints)).sorted(), id: \.self) { hint in
                    badge(hint.replacingOccurrences(of: "-", with: " "), "tag")
                }
            }
        }
    }

    private func badge(_ text: String, _ icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(BeagleFont.caption.font)
            .foregroundStyle(BeagleTheme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.white.opacity(0.05)))
    }
}
#endif

#if !os(iOS)
private struct SourceConfidenceStripView: View {
    let hints: [String]
    let faceCount: Int
    let barcodeCount: Int
    let rectangleCount: Int

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BeagleSpacing.xs) {
                badge("local", "checkmark.shield")
                ForEach(Array(Set(hints)).sorted(), id: \.self) { hint in
                    badge(hint.replacingOccurrences(of: "-", with: " "), "tag")
                }
            }
        }
    }

    private func badge(_ text: String, _ icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(BeagleFont.caption.font)
            .foregroundStyle(BeagleTheme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.white.opacity(0.05)))
    }
}
#endif

struct CaptureReviewSheet: View {
    let candidates: [CaptureReviewCandidate]
    let onPromote: ([CaptureReviewCandidate]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIDs: Set<String> = []

    var body: some View {
        NavigationStack {
            List {
                ForEach(candidates) { candidate in
                    Button {
                        if selectedIDs.contains(candidate.id) {
                            selectedIDs.remove(candidate.id)
                        } else {
                            selectedIDs.insert(candidate.id)
                        }
                    } label: {
                        HStack(alignment: .top, spacing: BeagleSpacing.sm) {
                            Image(systemName: selectedIDs.contains(candidate.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedIDs.contains(candidate.id) ? BeagleTheme.truthObserved : BeagleTheme.textTertiary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(candidate.title)
                                    .font(.headline)
                                Text(candidate.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(candidate.kind)
                                    .font(.caption2)
                                    .foregroundStyle(BeagleTheme.truthRemembered)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Review Capture")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Promote") {
                        let selected = candidates.filter { selectedIDs.contains($0.id) }
                        onPromote(selected.isEmpty ? candidates : selected)
                    }
                }
            }
            .onAppear {
                selectedIDs = Set(candidates.prefix(3).map(\.id))
            }
        }
        .presentationDetents([.medium, .large])
    }
}

enum CaptureCandidateBuilder {
    static func voiceCandidates(
        transcript: String,
        sessionId: String?,
        projectSlug: String
    ) -> [CaptureReviewCandidate] {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let evidence = sessionId.map { ["capture_session:\($0)"] } ?? []
        let sentence = trimmed
            .split(whereSeparator: { ".?!\n".contains($0) })
            .first
            .map(String.init) ?? String(trimmed.prefix(180))
        return [
            CaptureReviewCandidate(
                kind: "moment",
                title: "Thinking aloud moment",
                summary: String(trimmed.prefix(420)),
                evidenceRefs: evidence,
                nextAction: "Turn this into the next concrete Sounio move.",
                confidence: 0.72,
                provenance: .object(["capture_mode": .string("voice")])
            ),
            CaptureReviewCandidate(
                kind: "claim_seed",
                title: "Claim seed",
                summary: "Candidate claim from spoken thought.",
                evidenceRefs: evidence,
                claimText: sentence,
                epistemicStatus: "belief",
                confidence: 0.58,
                provenance: .object(["project_slug": .string(projectSlug)])
            )
        ]
    }

    static func imageCandidates(
        summary: String,
        artifactId: String,
        projectSlug: String
    ) -> [CaptureReviewCandidate] {
        [
            CaptureReviewCandidate(
                kind: "claim_seed",
                title: "Visual claim seed",
                summary: String(summary.prefix(360)),
                evidenceRefs: ["visual_artifact:\(artifactId)"],
                claimText: "Visual evidence suggests: \(String(summary.prefix(220)))",
                epistemicStatus: "belief",
                confidence: 0.54,
                provenance: .object([
                    "capture_mode": .string("image"),
                    "project_slug": .string(projectSlug)
                ])
            )
        ]
    }
}

//
//  VisualEvidenceCaptureView.swift
//  BeagleCockpit
//
//  Local-first visual/document evidence capture, camera & VisionKit scanners,
//  and source confidence badges.
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
    @State private var faceDetectionUnavailable = false
    @State private var detectedBarcodeCount = 0
    @State private var detectedRectangleCount = 0

    #if os(iOS)
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var selectedImageData: Data?
    @State private var documentTables: [[[String]]] = []
    @State private var documentJSON: String?
    @State private var analysisID = UUID()
    @State private var isAnalyzingImage = false
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

                    #if os(iOS)
                    ForEach(documentTables.indices, id: \.self) { index in
                        VStack(alignment: .leading) {
                            Text("Table \(index + 1)").font(.headline)
                            ScrollView(.horizontal) {
                                Grid(alignment: .leading) {
                                    ForEach(documentTables[index].indices, id: \.self) { row in
                                        GridRow {
                                            ForEach(documentTables[index][row].indices, id: \.self) { column in
                                                Text(documentTables[index][row][column])
                                                    .padding(6)
                                                    .textSelection(.enabled)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    #endif

                    SourceConfidenceStripView(
                        hints: localHints,
                        faceCount: detectedFaceCount,
                        barcodeCount: detectedBarcodeCount,
                        rectangleCount: detectedRectangleCount
                    )

                    if detectedFaceCount > 0 || faceDetectionUnavailable {
                        if faceDetectionUnavailable {
                            Text("Face detection unavailable. Review the image for sensitive content.")
                                .font(BeagleFont.footnote.font)
                        }
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
        #if os(iOS)
        if isAnalyzingImage { return false }
        #endif
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
        guard (detectedFaceCount == 0 && !faceDetectionUnavailable) || sensitiveVisualAcknowledged else {
            statusLine = "Review faces and sensitive visual context locally before upload."
            return
        }

        #if os(iOS)
        let artifactData = selectedImageData
        let structuredDocument = documentJSON
        #else
        let artifactData: Data? = nil
        let structuredDocument: String? = nil
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
                "face_count": faceDetectionUnavailable ? .null : .number(Double(detectedFaceCount)),
                "face_detection_unavailable": .bool(faceDetectionUnavailable),
                "barcode_count": .number(Double(detectedBarcodeCount)),
                "rectangle_count": .number(Double(detectedRectangleCount)),
                "structured_document_json": structuredDocument.map(ExocortexJSONValue.string) ?? .null
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
        let requestID = UUID()
        analysisID = requestID
        isAnalyzingImage = true
        defer { if analysisID == requestID { isAnalyzingImage = false } }
        sourceKind = source
        selectedImage = image
        // Render orientation into the pixels so legacy OCR and document regions agree.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let normalizedImage = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
        selectedImageData = normalizedImage.jpegData(compressionQuality: 0.88) ?? originalData
        statusLine = "Running local Vision analysis..."
        guard let data = selectedImageData else {
            statusLine = "Could not prepare image for analysis."
            return
        }
        let analysis = await VisualEvidenceLocalAnalyzer.shared.analyze(data: data, sourceKind: source)
        guard analysisID == requestID, !Task.isCancelled else { return }
        documentTables = analysis.tables
        documentJSON = analysis.documentJSON
        localSummary = analysis.summary
        extractedText = analysis.extractedText
        localHints = analysis.hints
        detectedFaceCount = analysis.faceCount
        faceDetectionUnavailable = !analysis.faceDetectionSucceeded
        detectedBarcodeCount = analysis.barcodeCount
        detectedRectangleCount = analysis.rectangleCount
        sensitiveVisualAcknowledged = analysis.faceDetectionSucceeded && analysis.faceCount == 0
        statusLine = !analysis.faceDetectionSucceeded
            ? "Face detection unavailable. Review sensitive content before upload."
            : analysis.faceCount > 0
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


struct CameraImagePicker: UIViewControllerRepresentable {
    let onImage: @MainActor (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage, dismiss: dismiss)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
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

struct DocumentCameraScanner: UIViewControllerRepresentable {
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

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
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

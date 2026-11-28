//
//  MultimodalComposer.swift
//  BeagleCockpit
//
//  Beagle v3.0: Text / Voice / Image capture with visible state, local-first
//  processing, and Sounio-typed review before durable memory promotion.
//

import SwiftUI
import BeagleCore

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

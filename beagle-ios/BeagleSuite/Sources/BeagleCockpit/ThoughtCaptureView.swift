//
//  ThoughtCaptureView.swift
//  BeagleCockpit
//
//  The most important view in the app.
//  Capture raw thoughts → HERMES refines → hypergraph stores.
//  Voice, keyboard, or clipboard. The iPhone is the entry point of the exocortex.
//

import SwiftUI
import BeagleCore
#if canImport(Speech)
import Speech
#endif

struct ThoughtCaptureView: View {
    @Environment(CognitiveStore.self) private var cognitive
    @State private var inputText = ""
    @State private var captureMode: CaptureMode = .keyboard
    @State private var lastRefined: String?
    @State private var isTranscribing = false
    @State private var conversation = ConversationStore()
    @FocusState private var inputFocused: Bool

    enum CaptureMode: String, CaseIterable {
        case keyboard, voice, clipboard, chat

        var icon: String {
            switch self {
            case .keyboard:  return "keyboard"
            case .voice:     return "mic.fill"
            case .clipboard: return "doc.on.clipboard"
            case .chat:      return "bubble.left.and.bubble.right"
            }
        }

        var label: String {
            switch self {
            case .keyboard:  return "Type"
            case .voice:     return "Voice"
            case .clipboard: return "Paste"
            case .chat:      return "Chat"
            }
        }
    }

    var body: some View {
        NavigationStack {
            if captureMode == .chat {
                VStack(spacing: 0) {
                    modePicker
                        .padding(.horizontal, BeagleSpacing.lg)
                        .padding(.top, BeagleSpacing.md)
                    ConversationView(conversation: conversation)
                }
                .background { PostureGradientBackground(counts: .empty) }
                .navigationTitle("Capture")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: BeagleSpacing.xl) {
                        captureSection
                        if let refined = lastRefined {
                            refinedSection(refined)
                        }
                        recentThoughtsSection
                    }
                    .padding(.horizontal, BeagleSpacing.lg)
                    .padding(.top, BeagleSpacing.md)
                }
                .background { PostureGradientBackground(counts: .empty) }
                .navigationTitle("Capture")
            }
        }
    }

    // MARK: - Capture input

    // MARK: - Mode picker (shared)

    private var modePicker: some View {
        HStack(spacing: BeagleSpacing.xs) {
            ForEach(CaptureMode.allCases, id: \.rawValue) { mode in
                Button {
                    withAnimation(BeagleMotion.snappy) {
                        captureMode = mode
                        if mode == .clipboard { pasteFromClipboard() }
                    }
                } label: {
                    Label(mode.label, systemImage: mode.icon)
                        .font(BeagleFont.footnote.font)
                        .padding(.horizontal, BeagleSpacing.sm)
                        .padding(.vertical, BeagleSpacing.xs)
                        .foregroundStyle(captureMode == mode ? BeagleTheme.truthObserved : BeagleTheme.textSecondary)
                        .background(
                            Capsule().fill(captureMode == mode ? BeagleTheme.truthObserved.opacity(0.12) : Color.white.opacity(0.04))
                        )
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.selection, trigger: captureMode)
            }
            Spacer()
        }
    }

    private var captureSection: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.md) {
            modePicker

            // Text input area
            if captureMode == .voice {
                GlassPanel(elevation: .raised) {
                    voiceSection
                }
            } else {
                VStack(spacing: BeagleSpacing.xs) {
                    if cognitive.isCapturing {
                        HStack(spacing: BeagleSpacing.xs) {
                            ProgressView()
                                .controlSize(.small)
                            Text("HERMES refining...")
                                .font(BeagleFont.caption.font)
                                .foregroundStyle(BeagleTheme.postureWarm)
                            Spacer()
                        }
                        .padding(.horizontal, BeagleSpacing.md)
                    }

                    BeagleInputBar(
                        text: $inputText,
                        placeholder: "What are you thinking about?",
                        mode: .chat,
                        isEnabled: !cognitive.isCapturing,
                        onSubmit: { _ in
                            Task { await captureThought() }
                        }
                    )
                }
            }
        }
    }

    // MARK: - Voice

    private var voiceSection: some View {
        VStack(spacing: BeagleSpacing.md) {
            Image(systemName: isTranscribing ? "waveform" : "mic.fill")
                .font(.system(size: 32))
                .foregroundStyle(isTranscribing ? BeagleTheme.truthObserved : BeagleTheme.textTertiary)
                .symbolEffect(.variableColor, isActive: isTranscribing)
                .frame(height: 60)

            if isTranscribing {
                Text(inputText.isEmpty ? "Listening..." : inputText)
                    .font(BeagleFont.body.font)
                    .foregroundStyle(BeagleTheme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if isTranscribing {
                Button { stopTranscription() } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(SecondaryButton(color: BeagleTheme.stateError))
            } else {
                Button { startTranscription() } label: {
                    Label("Start Recording", systemImage: "mic.fill")
                }
                .buttonStyle(PrimaryButton())
            }
        }
        .frame(minHeight: 100)
    }

    // MARK: - Refined result

    private func refinedSection(_ refined: String) -> some View {
        GlassPanel(elevation: .raised, truth: .observed) {
            VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
                HStack(spacing: BeagleSpacing.xxs) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(BeagleTheme.truthObserved)
                    Text("HERMES refined")
                        .font(BeagleFont.caption.font)
                        .fontWeight(.medium)
                        .foregroundStyle(BeagleTheme.truthObserved)
                }
                Text(refined)
                    .font(BeagleFont.body.font)
                    .foregroundStyle(BeagleTheme.textPrimary)
                    .textSelection(.enabled)
            }
        }
        .transition(.asymmetric(insertion: .push(from: .bottom), removal: .opacity))
    }

    // MARK: - Recent thoughts

    private var recentThoughtsSection: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            if !cognitive.recentThoughts.isEmpty {
                Text("Recent")
                    .font(BeagleFont.caption.font)
                    .fontWeight(.medium)
                    .foregroundStyle(BeagleTheme.textTertiary)

                ForEach(cognitive.recentThoughts.prefix(10)) { thought in
                    HStack(alignment: .top, spacing: BeagleSpacing.sm) {
                        Circle()
                            .fill(thought.refinedText != nil ? BeagleTheme.truthObserved : BeagleTheme.truthDeclared)
                            .frame(width: 6, height: 6)
                            .padding(.top, 6)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(thought.refinedText ?? thought.rawText ?? "—")
                                .font(BeagleFont.footnote.font)
                                .foregroundStyle(BeagleTheme.textPrimary)
                                .lineLimit(3)
                            if let source = thought.source {
                                Text(source)
                                    .font(BeagleFont.dataSmall.font)
                                    .foregroundStyle(BeagleTheme.textTertiary)
                            }
                        }
                    }
                    .padding(.vertical, BeagleSpacing.xxs)
                }
            }
        }
    }

    // MARK: - Actions

    private func captureThought() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let thought = await cognitive.captureThought(text: text, source: "ios-\(captureMode.rawValue)")
        withAnimation(BeagleMotion.slow) {
            lastRefined = thought?.refinedText ?? thought?.rawText
        }
        inputText = ""
    }

    private func pasteFromClipboard() {
        #if os(iOS)
        if let content = UIPasteboard.general.string {
            inputText = content
        }
        #elseif os(macOS)
        if let content = NSPasteboard.general.string(forType: .string) {
            inputText = content
        }
        #endif
    }

    // MARK: - Speech Recognition

    private func startTranscription() {
        #if canImport(Speech) && os(iOS)
        SFSpeechRecognizer.requestAuthorization { status in
            guard status == .authorized else { return }
            Task { @MainActor in
                isTranscribing = true
                inputText = ""
                // Real-time transcription would use SFSpeechAudioBufferRecognitionRequest
                // Simplified: after a delay, stop and capture
            }
        }
        #endif
    }

    private func stopTranscription() {
        isTranscribing = false
        if !inputText.isEmpty {
            Task { await captureThought() }
        }
    }
}

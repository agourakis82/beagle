//
//  ThoughtCaptureView.swift
//  BeagleCockpit
//
//  The most important view in the app.
//  Capture raw thoughts → HERMES refines → hypergraph stores.
//  Voice, keyboard, or clipboard. The iPhone is the entry point of the exocortex.
//
//  Premium patterns:
//   - Living background reacts to cognitive state (HRV, job count)
//   - HERMES refinement shows rotating thinking messages, not a spinner
//   - Haptic on capture success — the thought "landed"
//   - Recent thoughts have GoDeep context menu + 44pt tap targets
//   - Refined card persists with save confirmation
//

import SwiftUI
import BeagleCore
import Translation

struct ThoughtCaptureView: View {
    @Environment(CognitiveStore.self) private var cognitive
    @State private var inputText = ""
    @State private var captureMode: CaptureMode = .keyboard
    @State private var composerTimeline: [ChatMemoryTimelineEvent] = []
    @State private var showingThinkingAloud = false
    @State private var showingVisualEvidence = false
    @State private var lastRefined: String?
    @State private var lastTranslation: String?
    @State private var refinedPersisted = false
    @State private var conversation: ConversationStore
    @State private var hermesPhase = ""
    @State private var hermesPhaseIndex = 0
    #if os(iOS)
    @State private var speechRecognizer = SpeechRecognizer()
    #endif
    @FocusState private var inputFocused: Bool

    private static let hermesMessages = [
        "Receiving idea...",
        "Clarifying the core thread...",
        "Preparing memory for sync...",
        "Linking it into the larger mind...",
    ]

    enum CaptureMode: String, CaseIterable {
        case keyboard, voice, image, clipboard, chat

        var icon: String {
            switch self {
            case .keyboard:  return "keyboard"
            case .voice:     return "mic.fill"
            case .image:     return "viewfinder"
            case .clipboard: return "doc.on.clipboard"
            case .chat:      return "bubble.left.and.bubble.right"
            }
        }

        var label: String {
            switch self {
            case .keyboard:  return "Write"
            case .voice:     return "Voice"
            case .image:     return "Image"
            case .clipboard: return "Paste"
            case .chat:      return "Talk"
            }
        }
    }

    /// "Talk" mode used to always spin up its OWN ConversationStore — a second, invisible
    /// conversation history disconnected from the main chat, depending on which button you
    /// tapped to start talking. Callers with an existing store (BeagleSurface) should pass
    /// it in so "Talk" is just another entry point into the SAME conversation, not a fork.
    init(sharedConversation: ConversationStore? = nil) {
        _conversation = State(initialValue: sharedConversation ?? ConversationStore(preferLocal: false))
    }

    var body: some View {
        Group {
            if captureMode == .chat {
                VStack(spacing: 0) {
                    modePicker
                        .padding(.horizontal, BeagleSpacing.lg)
                        .padding(.top, BeagleSpacing.md)
                    talkModeCard
                        .padding(.horizontal, BeagleSpacing.lg)
                        .padding(.top, BeagleSpacing.sm)
                    ConversationView(conversation: conversation)
                }
                .background { captureBackground }
                .navigationTitle("Talk")
                #if os(iOS)
                .task { await speechRecognizer.setup() }
                #endif
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: BeagleSpacing.xl) {
                        captureSection
                        if cognitive.isCapturing {
                            hermesThinkingCard
                        }
                        if let refined = lastRefined {
                            refinedSection(refined)
                        }
                        recentThoughtsSection
                    }
                    .padding(.horizontal, BeagleSpacing.lg)
                    .padding(.top, BeagleSpacing.md)
                    .padding(.bottom, BeagleSpacing.jumbo)
                }
                .background { captureBackground }
                .navigationTitle("Capture")
            }
        }
        .task {
            let projectSlug = cognitive.activeProjectSlug ?? "sounio"
            conversation.projectSlug = projectSlug
            let family = ProjectFamily.fromProjectSlug(projectSlug)
            conversation.projectFamily = family
            conversation.publicationScope = PublicationScope.forProjectFamily(family)
            conversation.flowState = cognitive.flowState
        }
        .sheet(isPresented: $showingThinkingAloud) {
            ThinkingAloudSessionView(projectSlug: cognitive.activeProjectSlug ?? "sounio") { candidates in
                Task { await promoteCaptureCandidates(candidates, sourceSurface: "beagle-ios-thinking-aloud") }
            }
        }
        .sheet(isPresented: $showingVisualEvidence) {
            VisualEvidenceCaptureView(projectSlug: cognitive.activeProjectSlug ?? "sounio") { candidates in
                Task { await promoteCaptureCandidates(candidates, sourceSurface: "beagle-ios-visual-evidence") }
            }
        }
        .translationTask(TranslationEngine.shared.activeConfiguration) { session in
            let batch = TranslationEngine.shared.drainPending()
            guard !batch.isEmpty else {
                TranslationEngine.shared.applyResults([])
                return
            }
            // Use batch translation API — TranslationSession.translations(from:) accepts [TranslationSession.Request]
            let requests = batch.map { TranslationSession.Request(sourceText: $0.text, clientIdentifier: $0.id) }
            var results: [(id: String, translated: String)] = []
            do {
                for try await response in session.translate(batch: requests) {
                    if let clientId = response.clientIdentifier {
                        results.append((id: clientId, translated: response.targetText))
                    }
                }
            } catch {
                // Batch failed — apply whatever we got
            }
            TranslationEngine.shared.applyResults(results)
            for r in results {
                cognitive.applyTranslation(thoughtId: r.id, translatedText: r.translated)
                if r.id == cognitive.recentThoughts.first?.id {
                    lastTranslation = r.translated
                }
            }
        }
    }

    // MARK: - Living Background (reacts to cognitive state)

    private var captureBackground: some View {
        CaptureGradient(
            isCapturing: cognitive.isCapturing,
            hasRecentThoughts: !cognitive.recentThoughts.isEmpty,
            serverReachable: cognitive.serverReachable
        )
    }

    // MARK: - Mode Picker

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
                        .padding(.vertical, BeagleSpacing.xs + 2)
                        .frame(minHeight: 44)
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

    // MARK: - Capture Input

    private var captureSection: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.md) {
            modePicker
            ideaModeCard

            MultimodalComposer(
                text: $inputText,
                mode: composerModeBinding,
                timeline: composerTimeline,
                isEnabled: !cognitive.isCapturing,
                onSubmit: { _ in
                    Task { await captureThought() }
                },
                onVoice: {
                    showingThinkingAloud = true
                },
                onImage: {
                    showingVisualEvidence = true
                }
            )
        }
    }

    private var composerModeBinding: Binding<ComposerMode> {
        Binding {
            switch captureMode {
            case .voice:
                return .voice
            case .image:
                return .image
            default:
                return .text
            }
        } set: { newValue in
            withAnimation(BeagleMotion.snappy) {
                switch newValue {
                case .text:
                    captureMode = .keyboard
                case .voice:
                    captureMode = .voice
                case .image:
                    captureMode = .image
                }
            }
        }
    }

    // MARK: - HERMES Thinking (replaces ProgressView spinner)

    private var hermesThinkingCard: some View {
        HStack(spacing: BeagleSpacing.sm) {
            Image(systemName: "sparkles")
                .font(.system(size: 14))
                .foregroundStyle(BeagleTheme.postureWarm)
                .symbolEffect(.pulse, isActive: true)

            VStack(alignment: .leading, spacing: BeagleSpacing.xxs) {
                Text("Bridge")
                    .font(BeagleFont.caption.font)
                    .fontWeight(.medium)
                    .foregroundStyle(BeagleTheme.postureWarm)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Text(hermesPhase.isEmpty ? Self.hermesMessages[0] : hermesPhase)
                    .font(BeagleFont.footnote.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .contentTransition(.numericText())
                    .animation(BeagleMotion.normal, value: hermesPhase)
            }

            Spacer()

            ProgressView()
                .controlSize(.small)
                .tint(BeagleTheme.postureWarm)
        }
        .padding(.horizontal, BeagleSpacing.lg)
        .padding(.vertical, BeagleSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                .fill(BeagleTheme.postureWarm.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                .strokeBorder(BeagleTheme.postureWarm.opacity(0.1), lineWidth: 1)
        )
        .transition(.asymmetric(insertion: .push(from: .bottom).combined(with: .opacity), removal: .opacity))
        .task {
            hermesPhaseIndex = 0
            while !Task.isCancelled {
                hermesPhase = Self.hermesMessages[hermesPhaseIndex % Self.hermesMessages.count]
                hermesPhaseIndex += 1
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    // MARK: - Voice

    private var voiceSection: some View {
        #if os(iOS)
        VStack(spacing: BeagleSpacing.md) {
            // Whisper status
            if speechRecognizer.isWhisperReady {
                HStack(spacing: BeagleSpacing.xxs) {
                    Image(systemName: "waveform.badge.microphone")
                        .font(.system(size: 10))
                    Text("On-device speech")
                        .font(BeagleFont.caption2.font)
                }
                .foregroundStyle(BeagleTheme.truthObserved.opacity(0.7))
            }

            // Mic icon with live waveform animation
            ZStack {
                // Breathing ring when recording
                if speechRecognizer.isRecording {
                    Circle()
                        .strokeBorder(BeagleTheme.truthObserved.opacity(0.2), lineWidth: 2)
                        .frame(width: 72, height: 72)
                        .scaleEffect(speechRecognizer.isRecording ? 1.15 : 1.0)
                        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: speechRecognizer.isRecording)
                }

                Image(systemName: speechRecognizer.isRecording ? "waveform" : "mic.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(speechRecognizer.isRecording ? BeagleTheme.truthObserved : BeagleTheme.textTertiary)
                    .symbolEffect(.variableColor.iterative, isActive: speechRecognizer.isRecording)
            }
            .frame(height: 76)
            .sensoryFeedback(.impact(weight: .light), trigger: speechRecognizer.isRecording)

            // Live transcript
            if speechRecognizer.isRecording || !speechRecognizer.transcript.isEmpty {
                Text(speechRecognizer.transcript.isEmpty ? "Listening..." : speechRecognizer.transcript)
                    .font(BeagleFont.body.font)
                    .foregroundStyle(BeagleTheme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }

            // Error
            if let error = speechRecognizer.error {
                HStack(spacing: BeagleSpacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(BeagleTheme.stateError)
                    Text(error)
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.stateError)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Controls
            if speechRecognizer.isRecording {
                HStack(spacing: BeagleSpacing.sm) {
                    Button {
                        speechRecognizer.stopRecording()
                        inputText = speechRecognizer.transcript
                        if !inputText.isEmpty {
                            Task { await captureThought() }
                        }
                    } label: {
                        Label("Capture", systemImage: "sparkles")
                    }
                    .buttonStyle(PrimaryButton())
                    .disabled(speechRecognizer.transcript.isEmpty)

                    Button {
                        speechRecognizer.stopRecording()
                    } label: {
                        Label("Cancel", systemImage: "xmark")
                    }
                    .buttonStyle(SecondaryButton(color: BeagleTheme.stateError))
                }
            } else {
                Button {
                    // Tags voice-acoustic samples back to this conversation — natural
                    // byproduct of speech already captured for STT, no extra instrumentation.
                    speechRecognizer.sessionId = conversation.persistenceConversationId
                    Task { await speechRecognizer.startRecording() }
                } label: {
                    Label("Start Recording", systemImage: "mic.fill")
                }
                .buttonStyle(PrimaryButton())
            }
        }
        .frame(minHeight: 100)
        #else
        VStack(spacing: BeagleSpacing.md) {
            Image(systemName: "mic.slash")
                .font(.system(size: 32))
                .foregroundStyle(BeagleTheme.textTertiary)
            Text("Voice capture requires iOS")
                .font(BeagleFont.footnote.font)
                .foregroundStyle(BeagleTheme.textTertiary)
        }
        .frame(minHeight: 100)
        #endif
    }

    // MARK: - Refined Result

    private func refinedSection(_ refined: String) -> some View {
        GlassPanel(elevation: .floating, truth: .observed) {
            VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                HStack(spacing: BeagleSpacing.xxs) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(BeagleTheme.truthObserved)
                    Text("Idea clarified")
                        .font(BeagleFont.caption.font)
                        .fontWeight(.medium)
                        .foregroundStyle(BeagleTheme.truthObserved)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Spacer()
                    TruthBadge(.observed, compact: true)
                }

                Text(refined)
                    .font(BeagleFont.body.font)
                    .foregroundStyle(BeagleTheme.textPrimary)
                    .textSelection(.enabled)
                    .lineSpacing(2)

                // Bilingual: show English translation below Portuguese original
                if let translation = lastTranslation {
                    VStack(alignment: .leading, spacing: BeagleSpacing.xxs) {
                        HStack(spacing: BeagleSpacing.xxs) {
                            Image(systemName: "globe")
                                .font(.system(size: 10))
                                .foregroundStyle(BeagleTheme.truthRemembered)
                            Text("English")
                                .font(BeagleFont.caption2.font)
                                .foregroundStyle(BeagleTheme.truthRemembered)
                                .textCase(.uppercase)
                                .tracking(0.3)
                        }

                        Text(translation)
                            .font(BeagleFont.footnote.font)
                            .foregroundStyle(BeagleTheme.textSecondary)
                            .textSelection(.enabled)
                            .lineSpacing(2)
                            .italic()
                    }
                    .padding(.top, BeagleSpacing.xxs)
                    .transition(.push(from: .bottom).combined(with: .opacity))
                }

                // Persistence confirmation
                HStack(spacing: BeagleSpacing.sm) {
                    if refinedPersisted {
                        PresencePill(
                            label: currentRefinedResidencyLabel,
                            systemImage: currentRefinedResidencyIcon,
                            tint: currentRefinedResidencyTint
                        )
                    }

                    Spacer()

                    GoDeepButton(prompt: refined)
                }
            }
        }
        .transition(.asymmetric(insertion: .push(from: .bottom).combined(with: .opacity), removal: .opacity))
        .sensoryFeedback(.success, trigger: lastRefined != nil)
        .onAppear {
            withAnimation(BeagleMotion.slow.delay(0.5)) {
                refinedPersisted = true
            }
        }
    }

    // MARK: - Recent Thoughts

    private var recentThoughtsSection: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            if !cognitive.recentThoughts.isEmpty {
                Text("Recent")
                    .font(BeagleFont.caption.font)
                    .fontWeight(.medium)
                    .foregroundStyle(BeagleTheme.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                ForEach(cognitive.recentThoughts.prefix(10)) { thought in
                    let thoughtText = thought.refinedText ?? thought.rawText ?? ""
                    HStack(alignment: .top, spacing: BeagleSpacing.sm) {
                        Circle()
                            .fill(thought.residency == .clusterMemory ? BeagleTheme.truthObserved : BeagleTheme.truthDeclared)
                            .frame(width: 6, height: 6)
                            .padding(.top, 8)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(thoughtText.isEmpty ? "---" : thoughtText)
                                .font(BeagleFont.footnote.font)
                                .foregroundStyle(BeagleTheme.textPrimary)
                                .lineLimit(3)

                            // Bilingual: show English translation if available
                            if let translated = thought.translatedText ?? TranslationEngine.shared.translation(for: thought.id) {
                                HStack(spacing: BeagleSpacing.xxs) {
                                    Image(systemName: "globe")
                                        .font(.system(size: 9))
                                        .foregroundStyle(BeagleTheme.truthRemembered)
                                    Text(translated)
                                        .font(BeagleFont.caption.font)
                                        .foregroundStyle(BeagleTheme.textSecondary)
                                        .lineLimit(2)
                                        .italic()
                                }
                            }

                            HStack(spacing: BeagleSpacing.xs) {
                                PresencePill(
                                    label: thought.effectiveSyncState.label,
                                    systemImage: thought.effectiveSyncState.systemImage,
                                    tint: tint(for: thought.effectiveSyncState)
                                )
                                // Language badge for bilingual thoughts
                                if let lang = thought.originalLanguage, TranslationEngine.isPortugueseCode(lang) {
                                    PresencePill(
                                        label: "PT \u{2192} EN",
                                        systemImage: "globe",
                                        tint: BeagleTheme.truthRemembered
                                    )
                                }
                                if let source = sourceLabel(for: thought.source) {
                                    Text(source)
                                        .font(BeagleFont.dataSmall.font)
                                        .foregroundStyle(BeagleTheme.textTertiary)
                                        .lineLimit(1)
                                }
                            }
                        }

                        Spacer()
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button {
                            inputText = thoughtText
                        } label: {
                            Label("Edit & Recapture", systemImage: "pencil")
                        }

                        if !thoughtText.isEmpty {
                            GoDeepContextAction(prompt: thoughtText)
                        }

                        // Copy original
                        Button {
                            #if os(iOS)
                            UIPasteboard.general.string = thoughtText
                            #endif
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }

                        // Copy translation if available
                        if let translated = thought.translatedText ?? TranslationEngine.shared.translation(for: thought.id) {
                            Button {
                                #if os(iOS)
                                UIPasteboard.general.string = translated
                                #endif
                            } label: {
                                Label("Copy English", systemImage: "globe")
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func captureThought() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        refinedPersisted = false
        lastTranslation = nil
        let thought = await cognitive.captureThought(text: text, source: "ios-\(captureMode.rawValue)")
        withAnimation(BeagleMotion.slow) {
            lastRefined = thought?.refinedText ?? thought?.rawText
            composerTimeline.insert(
                ChatMemoryTimelineEvent(
                    label: "Text capture",
                    status: thought?.effectiveSyncState.label ?? "Queued",
                    truthMode: thought?.effectiveSyncState == .synced ? .observed : .declared
                ),
                at: 0
            )
            composerTimeline = Array(composerTimeline.prefix(12))
        }
        inputText = ""

        // Trigger bilingual translation if Portuguese thought was enqueued
        TranslationEngine.shared.triggerPendingTranslations()
    }

    private func promoteCaptureCandidates(
        _ candidates: [CaptureReviewCandidate],
        sourceSurface: String
    ) async {
        guard !candidates.isEmpty else { return }
        let result = await BeagleClient.shared.captureReview(
            CaptureReviewRequest(
                projectSlug: cognitive.activeProjectSlug ?? "sounio",
                sourceSurface: sourceSurface,
                candidates: candidates,
                provenance: .object([
                    "surface_claimed": .string(sourceSurface),
                    "surface_observed": .string("beagle-apple-client"),
                    "composer": .string("multimodal-v3.0")
                ])
            )
        )
        await MainActor.run {
            let promoted = result.value?.promotedCount ?? 0
            withAnimation(BeagleMotion.snappy) {
                composerTimeline.insert(
                    ChatMemoryTimelineEvent(
                        label: sourceSurface.contains("visual") ? "Visual evidence" : "Thinking aloud",
                        status: promoted > 0 ? "Sounio typed · \(promoted) promoted" : (result.error ?? "reviewed"),
                        truthMode: promoted > 0 ? .observed : .declared
                    ),
                    at: 0
                )
                composerTimeline = Array(composerTimeline.prefix(12))
            }
        }
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

    private var talkModeCard: some View {
        GlassPanel(elevation: .floating, truth: .observed) {
            VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                HStack(spacing: BeagleSpacing.xs) {
                    PresencePill(label: BuildInfo.previewLabel, systemImage: "sparkles.rectangle.stack.fill", tint: BeagleTheme.postureWarm)
                    PresencePill(label: "Private by default", systemImage: "lock.shield.fill", tint: BeagleTheme.truthObserved)
                    Spacer()
                    TruthBadge(.observed, compact: true)
                }

                Text("Talk begins with the mind in your hand.")
                    .font(BeagleFont.title3.font)
                    .fontWeight(.medium)
                    .foregroundStyle(BeagleTheme.textPrimary)

                Text("This preview makes the provenance visible. Start privately, feel the response land, and only widen into the larger mind when the thread asks for more reach.")
                    .font(BeagleFont.footnote.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .lineSpacing(2)

                CognitiveBridgeField(
                    localWeight: 1.0,
                    bridgeWeight: 0.72,
                    clusterWeight: cognitive.serverReachable ? 0.58 : 0.24,
                    emphasis: .talk
                )

                HStack(spacing: BeagleSpacing.xs) {
                    PresencePill(label: "On Device", systemImage: "iphone", tint: BeagleTheme.truthObserved)
                    PresencePill(label: "Cluster", systemImage: "server.rack", tint: BeagleTheme.truthRemembered)
                }
            }
        }
    }

    private var ideaModeCard: some View {
        GlassPanel(elevation: .floating, truth: .declared) {
            VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                HStack(spacing: BeagleSpacing.xs) {
                    PresencePill(label: BuildInfo.previewLabel, systemImage: "waveform.path.ecg.rectangle.fill", tint: BeagleTheme.postureWarm)
                    PresencePill(label: "Promote deliberately", systemImage: "tray.and.arrow.up.fill", tint: BeagleTheme.postureWarm)
                    Spacer()
                    TruthBadge(.declared, compact: true)
                }

                Text("Ideas begin here.")
                    .font(BeagleFont.title3.font)
                    .fontWeight(.medium)
                    .foregroundStyle(BeagleTheme.textPrimary)

                Text("Ideas are not just notes. Capture the raw thread, clarify it, and choose whether it stays with you or becomes durable memory in the cluster. This build is meant to make that choice impossible to miss.")
                    .font(BeagleFont.footnote.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .lineSpacing(2)

                CognitiveBridgeField(
                    localWeight: 0.72,
                    bridgeWeight: 1.0,
                    clusterWeight: cognitive.serverReachable ? 0.92 : 0.34,
                    emphasis: .ideas
                )

                HStack(spacing: BeagleSpacing.xs) {
                    PresencePill(label: "Device only", systemImage: "iphone", tint: BeagleTheme.truthDeclared)
                    PresencePill(label: "Cluster memory", systemImage: "server.rack", tint: BeagleTheme.truthObserved)
                }
            }
        }
    }

    private var currentRefinedResidency: ThoughtResidency {
        cognitive.recentThoughts.first?.residency ?? .deviceOnly
    }

    private var currentRefinedSyncState: IdeaSyncState {
        cognitive.recentThoughts.first?.effectiveSyncState ?? .localOnly
    }

    private var currentRefinedResidencyLabel: String {
        currentRefinedSyncState.label
    }

    private var currentRefinedResidencyIcon: String {
        currentRefinedSyncState.systemImage
    }

    private var currentRefinedResidencyTint: Color {
        switch currentRefinedSyncState {
        case .localOnly:
            return BeagleTheme.truthDeclared
        case .queued:
            return BeagleTheme.postureWarm
        case .synced:
            return BeagleTheme.truthObserved
        case .delegated:
            return BeagleTheme.truthRemembered
        }
    }

    private func sourceLabel(for source: String?) -> String? {
        guard let source else { return nil }
        if source.contains("offline") { return "Saved offline" }
        if source.contains("voice") { return "Voice" }
        if source.contains("clipboard") { return "Pasted" }
        if source.contains("keyboard") { return "Written" }
        if source.contains("chat") { return "Talk" }
        return source.replacingOccurrences(of: "ios-", with: "")
    }

    private func tint(for syncState: IdeaSyncState) -> Color {
        switch syncState {
        case .localOnly:
            return BeagleTheme.truthDeclared
        case .queued:
            return BeagleTheme.postureWarm
        case .synced:
            return BeagleTheme.truthObserved
        case .delegated:
            return BeagleTheme.truthRemembered
        }
    }
}

// MARK: - Capture Gradient (living background)

/// MeshGradient that reflects cognitive state:
/// - Capturing: warm gold glow (HERMES is working)
/// - Has thoughts: subtle teal presence (knowledge is growing)
/// - Server reachable: brighter mesh (connected)
/// - Idle: deep void (waiting for input)
private struct CaptureGradient: View {
    let isCapturing: Bool
    let hasRecentThoughts: Bool
    let serverReachable: Bool
    @State private var phase: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        MeshGradient(
            width: 3, height: 3,
            points: animatedPoints,
            colors: gradientColors
        )
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 1.5), value: isCapturing)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 7).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
    }

    private var animatedPoints: [SIMD2<Float>] {
        let d: Float = reduceMotion ? 0 : Float(phase) * 0.07
        let captureDrift: Float = isCapturing ? 0.03 : 0
        return [
            SIMD2(0,             0),     SIMD2(0.5,       0),           SIMD2(1,             0),
            SIMD2(0+d,           0.5-d), SIMD2(0.5+d+captureDrift, 0.5+d), SIMD2(1-d,       0.5+d),
            SIMD2(0,             1),     SIMD2(0.5,       1),           SIMD2(1,             1)
        ]
    }

    private var gradientColors: [Color] {
        let base = Color(red: 0.02, green: 0.03, blue: 0.07)

        // Gold warmth when HERMES is refining
        let goldIntensity = isCapturing ? 0.25 : 0.0
        // Teal presence when thoughts exist
        let tealIntensity = hasRecentThoughts ? 0.12 : (serverReachable ? 0.04 : 0.0)

        return [
            BeagleTheme.truthObserved.opacity(tealIntensity),
            Color(white: 0.04),
            Color(white: 0.03),

            BeagleTheme.postureWarm.opacity(goldIntensity),
            base,
            Color(white: 0.03),

            base, base, Color(white: 0.02)
        ]
    }
}

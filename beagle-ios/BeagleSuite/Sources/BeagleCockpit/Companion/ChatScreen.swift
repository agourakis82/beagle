//
//  ChatScreen.swift
//  BeagleCockpit — Companion chat
//
//  The chat surface skeleton. Flat warm bubbles scroll above the app's living-mesh
//  background; a single floating Liquid Glass composer is the only chrome. Streaming is
//  driven by ConversationStore (@Observable) — content snapshots coalesce naturally
//  through SwiftUI Observation, and the scroll follows the latest snapshot.
//  See docs/design/2026-06-24-companion-design-system.md (§4, §7).
//

import SwiftUI
import BeagleCore

public struct ChatScreen: View {
    let store: ConversationStore   // @Observable — SwiftUI tracks property reads in body
    /// User's real respiratory rate (breaths/min, from PhysioStore/HealthKit) so the companion
    /// breathes at the user's pace; nil → calm resting default.
    let breathRate: Double?
    /// Live geomagnetic snapshot for AuroraPresence. nil → calm placeholder; the
    /// store keeps refreshing in the background so this updates naturally.
    let weather: SpaceWeatherStore.Snapshot?
    /// Live body snapshot (HRV, breath, wrist temp, sleep) for the body strip
    /// above the composer. nil → strip is hidden.
    let posture: CognitivePosture?
    /// Access to the surface's sheets, folded into the history drawer (Claude-style: settings
    /// at the bottom of the drawer) so the chat top stays clean — just history · title · new.
    var onOpenSettings: (() -> Void)?
    var onOpenProject: (() -> Void)?
    /// Opens the dedicated data screen (Agora/physiome series). Lives in the drawer footer.
    var onOpenData: (() -> Void)?
    /// Opens "o que eu lembro de ti" — the warm memory-browse screen. Drawer footer.
    var onOpenMemory: (() -> Void)?
    /// Opens the overnight Dream Synthesis reader. Drawer footer, badge shows unread count —
    /// this is the ONLY surfaced consumer of DreamSynthesisEngine; it silently had no home
    /// after the header-bar chrome was retired, so insights piled up invisibly.
    var onOpenDreamInsights: (() -> Void)?
    var unreadDreamInsightCount: Int = 0
    /// Opens WorkView (the agent deck) — was iPad-sidebar-only before this session's screen
    /// audit found it had zero entry point on iPhone despite being the richest single
    /// feature in the app. Drawer footer.
    var onOpenWork: (() -> Void)?
    /// Opens ThoughtCaptureView (voice→text + Sounio typing) — SAME story as Work: it lived only
    /// in the iPad sidebar, so the iPhone had NO way to capture a thought at all, which is why the
    /// night synthesis stayed starved and the user couldn't dictate. Drawer footer.
    var onOpenCapture: (() -> Void)?
    @State private var draft = ""
    @State private var appeared = false
    /// Live dictation for the composer mic (was a dead `onVoice: {}` stub). @Observable +
    /// @MainActor; the transcript streams into `draft` while recording. Set up once via .task.
    @State private var speech = SpeechRecognizer()
    // SOTA-chat #5: send haptic trigger — bumped in send() so .sensoryFeedback fires a
    // discrete light impact on every send, independent of the message store's timing.
    @State private var sendTick = 0
    /// ONE sheet for the whole screen — multiple `.sheet(isPresented:)` on the same view conflict
    /// in SwiftUI (the second silently breaks the first, which is why the drawer stopped opening).
    @State private var activeSheet: ChatSheet?
    /// The companion's gear for the next message (voice model, or Fundo → Go-Deeper).
    @State private var depth: ChatDepth = .sonnet
    @State private var composerGoDeepStore = GoDeepStore()
    /// The top bar melts away while you read forward and returns when you scroll back up — the
    /// "chrome dissolves into the content" feel (Claude/Safari). Driven by scroll direction below.
    @State private var topBarHidden = false
    /// Accumulated scroll in the current direction — the bar only flips after a deliberate
    /// gesture (not a twitch), so it doesn't vanish on the slightest touch.
    @State private var scrollAccum: CGFloat = 0
    /// Accessibility: when the user turns on Reduce Transparency, glass falls back to a
    /// solid material so text/controls stay legible (iOS 27's contrast guidance).
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(store: ConversationStore,
                breathRate: Double? = nil,
                weather: SpaceWeatherStore.Snapshot? = nil,
                posture: CognitivePosture? = nil,
                onOpenSettings: (() -> Void)? = nil,
                onOpenProject: (() -> Void)? = nil,
                onOpenData: (() -> Void)? = nil,
                onOpenMemory: (() -> Void)? = nil,
                onOpenDreamInsights: (() -> Void)? = nil,
                unreadDreamInsightCount: Int = 0,
                onOpenWork: (() -> Void)? = nil,
                onOpenCapture: (() -> Void)? = nil) {
        self.store = store
        self.breathRate = breathRate
        self.weather = weather
        self.posture = posture
        self.onOpenSettings = onOpenSettings
        self.onOpenProject = onOpenProject
        self.onOpenData = onOpenData
        self.onOpenMemory = onOpenMemory
        self.onOpenDreamInsights = onOpenDreamInsights
        self.unreadDreamInsightCount = unreadDreamInsightCount
        self.onOpenWork = onOpenWork
        self.onOpenCapture = onOpenCapture
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            // Layer 1: hearth glow rising from bottom
            hearth
            // Layer 2: aurora orb sitting BEHIND the conversation (per user 2026-06-28:
            // "deixar o orb no mesmo plano que a conversa, ou atrás dela, pra ampliar
            // a visualização do chat"). Large + faint; the chat reads OVER it.
            presenceBackground
            // Layer 3: chat content fills the screen — empty state greeting OR conversation
            VStack(spacing: 0) {
                if store.messages.isEmpty {
                    Spacer(minLength: 0)
                    greeting
                    Spacer(minLength: 0)
                    Spacer(minLength: 0)
                } else {
                    conversation
                }
            }
            // Layer 4: minimal top bar — history · title · new. Floats over the aurora.
            topBar
            // Layer 5: composer pinned to the bottom. No body strip — body/sky/ambient data
            // lives on its own screen now; the chat is just conversation.
            composer
        }
        // Entry ceremony — the space materializes with a breath instead of snapping in
        // (Gaggioli: ceremony over frictionless).
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.985, anchor: .bottom)
        .task {
            if ProcessInfo.processInfo.arguments.contains("--demo-chat") {
                store.seedDemoConversation()
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.55)) { appeared = true }
        }
        // SOTA-chat #5: subtle haptics via iOS 17 .sensoryFeedback (state-triggered, no
        // generators to manage). Light impact on send; a discrete success at the moment the
        // stream finishes (isStreaming true → false). Adult register — never festive.
        .sensoryFeedback(.impact(weight: .light), trigger: sendTick)
        .sensoryFeedback(trigger: store.isStreaming) { wasStreaming, isStreaming in
            (wasStreaming && !isStreaming) ? .success : nil
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .history:
                ConversationDrawer(store: store, onOpenSettings: onOpenSettings, onOpenProject: onOpenProject, onOpenData: onOpenData, onOpenMemory: onOpenMemory, onOpenDreamInsights: onOpenDreamInsights, unreadDreamInsightCount: unreadDreamInsightCount, onOpenWork: onOpenWork, onOpenCapture: onOpenCapture)
            case .goDeep(let prompt):
                GoDeepView(store: composerGoDeepStore, prompt: prompt)
            }
        }
    }

    // Minimal top bar: history (☰) · conversation title · new (＋). Liquid Glass buttons that
    // float over the aurora. NO GlassEffectContainer/glassEffectID — those try to MORPH the glass
    // when state changes (e.g. presenting the drawer), which made the buttons flicker / lose their
    // effect on tap. Plain per-button glass is stable.
    private var topBar: some View {
        VStack {
            HStack(spacing: BeagleSpacing.sm) {
                topBarButton("line.3.horizontal") { activeSheet = .history }
                Spacer(minLength: BeagleSpacing.sm)
                Text(store.currentConversationTitle)
                    .font(BeagleFont.subheadline.font.weight(.semibold))
                    .foregroundStyle(BeagleTheme.companionInk)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    // Legibility over the variable aurora — a soft dark halo keeps the title
                    // readable whether it floats over bright green or deep night.
                    .shadow(color: .black.opacity(0.45), radius: 4, y: 0.5)
                Spacer(minLength: BeagleSpacing.sm)
                topBarButton("square.and.pencil") {
                    withAnimation(.easeOut(duration: 0.25)) { store.newConversation() }
                }
            }
            .padding(.horizontal, BeagleSpacing.md)
            .padding(.top, BeagleSpacing.sm)
            // Melt away while reading forward; glide back on scroll-up.
            .opacity(topBarHidden ? 0 : 1)
            .offset(y: topBarHidden ? -72 : 0)
            .blur(radius: topBarHidden ? 6 : 0)
            Spacer()
        }
    }

    private func topBarButton(_ system: String, action: @escaping () -> Void) -> some View {
        // NO `.glassEffect` on these buttons: on iOS 26/27 glass applied to a Button mismatches the
        // tap region (the glass shape ≠ the hittable area), so taps were silently lost — that's why
        // the ☰ "didn't open" the drawer while the composer Menu (not a glass button) worked. A
        // frosted-material circle + an explicit `.contentShape(Circle())` makes the WHOLE circle a
        // reliable tap target.
        Button {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            #endif
            action()
        } label: {
            Image(systemName: system)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(BeagleTheme.companionInk.opacity(0.9))
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    // Aurora CURTAIN sitting BEHIND the conversation. Spans the full width;
    // drifts horizontally, ripples vertically, hue cycles, brightens when the
    // companion is streaming. Empty state: brighter and fills upper half.
    // Chatting: dimmer and pulled to upper third so the conversation reads.
    private var presenceBackground: some View {
        let empty = store.messages.isEmpty
        return AuroraPresence(
            breathRate: breathRate,
            weather: weather,
            isStreaming: store.isStreaming,
            size: empty ? .greeter : .header
        )
        // Inspiring when empty (greeter); a quiet whisper behind the text when reading, so the
        // conversation stays the hero (the user: "a aurora no fundo é inspiradora, sabendo fazer
        // design não atrapalha").
        .opacity(empty ? 0.9 : 0.28)
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.35), value: empty)
    }

    // Top-right "novo" button — clears the conversation thread. Floats over the
    // chat so it doesn't steal layout space. Glass capsule + hairline.
    private var newConversationButton: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    #if canImport(UIKit)
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    #endif
                    withAnimation(.easeOut(duration: 0.25)) { store.clear() }
                } label: {
                    Label("novo", systemImage: "square.and.pencil")
                        .font(BeagleFont.caption.font.weight(.medium))
                        .foregroundStyle(BeagleTheme.companionInk.opacity(0.85))
                        .padding(.horizontal, BeagleSpacing.sm)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.75))
                .padding(.trailing, BeagleSpacing.md)
                .padding(.top, BeagleSpacing.sm)
            }
            Spacer()
        }
    }

    // Live body strip — HRV / breath / wrist temp / sleep — pulled from PhysioStore.
    // Renders only when at least one signal is available; chips collapse otherwise.
    @ViewBuilder
    private var bodyStrip: some View {
        if let p = posture, hasAnyBodySignal(p) {
            HStack(spacing: BeagleSpacing.sm) {
                if let h = p.hrv { bodyChip("\(Int(h)) ms", system: "waveform.path.ecg") }
                if let r = p.respiratoryRate { bodyChip("\(Int(r.rounded())) bpm", system: "wind") }
                if let s = p.sleepQuality { bodyChip("\(Int((s * 100).rounded()))% sono", system: "moon.zzz") }
                if let t = p.wristTemperature {
                    let sign = t >= 0 ? "+" : ""
                    bodyChip("\(sign)\(String(format: "%.1f", t))°", system: "thermometer.medium")
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, BeagleSpacing.md)
        }
    }

    private func hasAnyBodySignal(_ p: CognitivePosture) -> Bool {
        p.hrv != nil || p.respiratoryRate != nil || p.sleepQuality != nil || p.wristTemperature != nil
    }

    private func bodyChip(_ text: String, system: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: system)
                .font(.system(size: 10, weight: .medium))
            Text(text)
                .font(BeagleFont.caption2.font.weight(.medium))
        }
        .foregroundStyle(BeagleTheme.companionInk.opacity(0.75))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .glassEffect(.regular, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5))
    }

    // Aurora glow rising from the composer — geomagnetic dawn.
    private var hearth: some View {
        let kp = weather?.kp ?? 1.0
        let stormBoost = min(0.25, max(0, (kp - 2) / 20))
        return RadialGradient(
            colors: [
                BeagleTheme.auroraGreen.opacity(0.18 + stormBoost),
                BeagleTheme.auroraTeal.opacity(0.14 + stormBoost),
                BeagleTheme.auroraViolet.opacity(0.10 + stormBoost),
                BeagleTheme.auroraNight.opacity(0.55),
                .clear
            ],
            center: UnitPoint(x: 0.5, y: 0.95),
            startRadius: 0,
            endRadius: 520
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: - Conversation (flat content above the mesh)

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: BeagleSpacing.lg) {
                    ForEach(store.messages) { message in
                        MessageBubble(
                            message: message,
                            isLast: message.id == store.messages.last?.id,
                            onRegenerate: { Task { await store.regenerateLastResponse() } }
                        )
                        .id(message.id)
                    }
                    // clearance so the floating composer never covers the last line
                    Color.clear.frame(height: 72).id(Self.bottomAnchor)
                }
                .padding(.horizontal, BeagleSpacing.md)
                .padding(.top, BeagleSpacing.md)
                .frame(maxWidth: .infinity, minHeight: 0, alignment: .bottom)
                .animation(.easeOut(duration: 0.25), value: store.messages.count)
            }
            .defaultScrollAnchor(.bottom)   // recent messages hug the composer; void goes up top
            .scrollDismissesKeyboard(.interactively)
            // Direction-based chrome melt: finger up (offset grows → reading forward) hides the
            // top bar; finger down (offset shrinks → going back) reveals it. Anchor-agnostic.
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentOffset.y
            } action: { oldY, newY in
                let delta = newY - oldY
                guard abs(delta) > 0.5 else { return }     // ignore noise
                // Reset the accumulator on a direction change so a deliberate gesture in one
                // direction is what counts — not net drift.
                if (delta > 0) != (scrollAccum > 0) { scrollAccum = 0 }
                scrollAccum += delta
                if scrollAccum > 60, !topBarHidden {
                    withAnimation(.easeOut(duration: 0.4)) { topBarHidden = true }
                    scrollAccum = 0
                } else if scrollAccum < -40, topBarHidden {
                    withAnimation(.easeOut(duration: 0.4)) { topBarHidden = false }
                    scrollAccum = 0
                }
            }
            // SOTA-chat #1: the instant a send starts, isStreaming flips true with an empty
            // assistant snapshot (the "pensando" indicator). Scroll it into view immediately so
            // the thinking state is visible at the moment of send, before the first token.
            .onChange(of: store.isStreaming) { _, isStreaming in
                if isStreaming {
                    withAnimation(.smooth) { proxy.scrollTo(Self.bottomAnchor, anchor: .bottom) }
                }
            }
            // SOTA-chat #3: springs (.smooth, bounce 0) instead of .easeOut so an in-flight
            // scroll FUSES with the next token or a user drag — the animation carries velocity
            // and blends rather than restarting/stuttering on every snapshot.
            .onChange(of: store.messages.last?.content) { _, _ in
                withAnimation(.smooth) { proxy.scrollTo(Self.bottomAnchor, anchor: .bottom) }
            }
            .onChange(of: store.messages.count) { _, _ in
                // SOTA-chat #3: interruptible spring for the new-message jump too.
                withAnimation(.smooth) { proxy.scrollTo(Self.bottomAnchor, anchor: .bottom) }
                // A fresh turn brings the bar back so the title/controls are always reachable.
                if topBarHidden { withAnimation(.easeOut(duration: 0.28)) { topBarHidden = false } }
            }
        }
    }

    // MARK: - Composer (the only glass)

    private var composer: some View {
        ChatComposer(
            text: $draft,
            depth: $depth,
            isStreaming: store.isStreaming,
            onSend: send,
            onVoice: { toggleVoice() },
            isRecording: speech.isRecording
        )
        .padding(.horizontal, BeagleSpacing.md)
        .padding(.bottom, BeagleSpacing.sm)
        .shadow(color: .black.opacity(0.35), radius: 18, y: 6)   // lift off the surface
        .task { await speech.setup() }
        // Voice→text: stream the live transcript into the field while dictating. The mic only
        // appears when the field is empty, so this never clobbers typed text.
        .onChange(of: speech.transcript) { _, newValue in
            if speech.isRecording { draft = newValue }
        }
    }

    /// Toggle dictation: tap the mic to start (transcript streams into `draft`), tap Stop to end;
    /// the text then stays in the field to edit or send. Reuses the same SpeechRecognizer as capture.
    private func toggleVoice() {
        if speech.isRecording {
            speech.stopRecording()
        } else {
            Task { await speech.startRecording() }
        }
    }

    // MARK: - Empty state (warm, zero-friction — no forms)

    private var greeting: some View {
        let story = BodyStory.opening(physioSnapshot, hour: Calendar.current.component(.hour, from: Date()))
        return VStack(spacing: BeagleSpacing.sm) {
            Text(story.line)
                .font(BeagleFont.title2.font)
                .fontWeight(.semibold)
                .foregroundStyle(BeagleTheme.companionInk)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
            Text(story.follow)
                .font(BeagleFont.callout.font)
                .foregroundStyle(BeagleTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, BeagleSpacing.xl)
    }

    /// Body-as-story snapshot. Reads the wired store (flow ← HRV); `--demo` injects a
    /// realistic body state so the attuned greeting renders without live HealthKit (sim).
    private var physioSnapshot: PhysioSnapshot {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--demo") || args.contains("--demo-chat") {
            return PhysioSnapshot(sleepQuality: "light", flow: "STRESS", restingHRElevated: true)
        }
        // Real sleep quality (deep+REM ratio) → narrative word, never a number.
        let sleep: String? = store.sleepQuality01.map { q in
            q < 0.35 ? "light" : (q > 0.65 ? "deep" : "ok")
        }.flatMap { $0 == "ok" ? nil : $0 }
        return PhysioSnapshot(sleepQuality: sleep, flow: store.flowState, restingHRElevated: false)
    }

    // MARK: - Send

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // SOTA-chat #5: fire the light send haptic for any committed send (chat turn or Fundo).
        sendTick &+= 1
        // Fundo = escalate to a full Go-Deeper exploration instead of a chat turn.
        if depth == .fundo {
            draft = ""
            activeSheet = .goDeep(text)
            return
        }
        draft = ""
        store.voiceModel = depth.voiceModel   // Rápido → default voice; Pensar → stronger model
        store.deepThink = depth.isDeepThink    // Agente → agentic read-only tool path (server side)
        Task { await store.sendMessage(text) }
    }

    private static let bottomAnchor = "companion.chat.bottom"
}

// MARK: - Sheets

/// The single sheet the chat screen can present. One enum-driven sheet avoids the SwiftUI
/// multiple-`.sheet` conflict (which silently broke the history drawer).
enum ChatSheet: Identifiable {
    case history
    case goDeep(String)   // prompt to explore
    var id: String {
        switch self {
        case .history: return "history"
        case .goDeep: return "goDeep"
        }
    }
}

// MARK: - Conversation history drawer (Fase 1 polishes: search, rename, pin UI)

/// The thread list — tap to switch, swipe to delete, + to start fresh. Best-in-class history
/// (Claude/ChatGPT) so the chat is many conversations, not one.
struct ConversationDrawer: View {
    let store: ConversationStore
    var onOpenSettings: (() -> Void)?
    var onOpenProject: (() -> Void)?
    var onOpenData: (() -> Void)?
    var onOpenMemory: (() -> Void)?
    var onOpenDreamInsights: (() -> Void)?
    var unreadDreamInsightCount: Int = 0
    var onOpenWork: (() -> Void)?
    var onOpenCapture: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var reloadToken = 0

    var body: some View {
        NavigationStack {
            List {
                let threads = store.conversations()
                if threads.isEmpty {
                    Text("Nenhuma conversa ainda.")
                        .font(BeagleFont.footnote.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                } else {
                    ForEach(threads, id: \.id) { conv in
                        Button {
                            store.switchTo(conversationId: conv.id)
                            dismiss()
                        } label: {
                            HStack(spacing: BeagleSpacing.sm) {
                                if conv.pinned {
                                    Image(systemName: "pin.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(BeagleTheme.truthRemembered)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(conv.displayTitle)
                                        .font(BeagleFont.body.font)
                                        .foregroundStyle(BeagleTheme.companionInk)
                                        .lineLimit(1)
                                    Text(conv.updatedAt, format: .relative(presentation: .named))
                                        .font(BeagleFont.caption2.font)
                                        .foregroundStyle(BeagleTheme.textSecondary)
                                }
                                Spacer()
                                if conv.id == store.currentConversationId {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(BeagleTheme.truthObserved)
                                }
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                store.deleteConversation(conv.id); reloadToken += 1
                            } label: { Label("Apagar", systemImage: "trash") }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                store.togglePinned(conv.id); reloadToken += 1
                            } label: { Label("Fixar", systemImage: "pin") }
                            .tint(BeagleTheme.truthRemembered)
                        }
                    }
                }
                // Footer: memory + data screen + settings + project live here now (off the chat top).
                Section {
                    if onOpenCapture != nil {
                        Button { dismiss(); onOpenCapture?() } label: {
                            Label("Capturar pensamento", systemImage: "mic.fill")
                        }
                        .foregroundStyle(BeagleTheme.companionInk.opacity(0.9))
                    }
                    if onOpenMemory != nil {
                        Button { dismiss(); onOpenMemory?() } label: {
                            Label("O que eu lembro de ti", systemImage: "brain.head.profile")
                        }
                        .foregroundStyle(BeagleTheme.companionInk.opacity(0.9))
                    }
                    if onOpenDreamInsights != nil {
                        Button { dismiss(); onOpenDreamInsights?() } label: {
                            HStack {
                                Label("Insights da noite", systemImage: "moon.stars.fill")
                                if unreadDreamInsightCount > 0 {
                                    Spacer()
                                    Text("\(unreadDreamInsightCount)")
                                        .font(BeagleFont.caption2.font)
                                        .foregroundStyle(Color(hue: 270/360, saturation: 0.5, brightness: 0.9))
                                }
                            }
                        }
                        .foregroundStyle(BeagleTheme.companionInk.opacity(0.9))
                    }
                    if onOpenData != nil {
                        Button { dismiss(); onOpenData?() } label: {
                            Label("Dados", systemImage: "chart.xyaxis.line")
                        }
                        .foregroundStyle(BeagleTheme.companionInk.opacity(0.9))
                    }
                    if onOpenWork != nil {
                        Button { dismiss(); onOpenWork?() } label: {
                            Label("Trabalho", systemImage: "bolt.fill")
                        }
                        .foregroundStyle(BeagleTheme.companionInk.opacity(0.9))
                    }
                    if onOpenProject != nil {
                        Button { dismiss(); onOpenProject?() } label: {
                            Label("Projeto", systemImage: "scope")
                        }
                        .foregroundStyle(BeagleTheme.companionInk.opacity(0.9))
                    }
                    if onOpenSettings != nil {
                        Button { dismiss(); onOpenSettings?() } label: {
                            Label("Configurações", systemImage: "gearshape")
                        }
                        .foregroundStyle(BeagleTheme.companionInk.opacity(0.9))
                    }
                }
            }
            .id(reloadToken)
            .navigationTitle("Conversas")
            .navigationBarTitleDisplayMode(.inline)
            // Keep the native sheet material (the nice translucent glass) — just force dark so the
            // warm-white text reads. (Flattening to a solid canvas killed the material and the
            // tap targets; reverted.)
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fechar") { dismiss() }
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        store.newConversation(); dismiss()
                    } label: { Image(systemName: "square.and.pencil") }
                }
            }
        }
    }
}

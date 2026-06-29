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
    @State private var draft = ""
    @State private var appeared = false
    @State private var showHistory = false

    public init(store: ConversationStore,
                breathRate: Double? = nil,
                weather: SpaceWeatherStore.Snapshot? = nil,
                posture: CognitivePosture? = nil) {
        self.store = store
        self.breathRate = breathRate
        self.weather = weather
        self.posture = posture
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
        .sheet(isPresented: $showHistory) {
            ConversationDrawer(store: store)
        }
    }

    // Minimal top bar: history (☰) · conversation title · new (＋). Glass, floats over the aurora.
    private var topBar: some View {
        VStack {
            HStack(spacing: BeagleSpacing.sm) {
                topBarButton("line.3.horizontal") { showHistory = true }
                Spacer(minLength: BeagleSpacing.sm)
                Text(store.currentConversationTitle)
                    .font(BeagleFont.footnote.font.weight(.semibold))
                    .foregroundStyle(BeagleTheme.companionInk.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: BeagleSpacing.sm)
                topBarButton("square.and.pencil") {
                    withAnimation(.easeOut(duration: 0.25)) { store.newConversation() }
                }
            }
            .padding(.horizontal, BeagleSpacing.md)
            .padding(.top, BeagleSpacing.sm)
            Spacer()
        }
    }

    private func topBarButton(_ system: String, action: @escaping () -> Void) -> some View {
        Button {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            #endif
            action()
        } label: {
            Image(systemName: system)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(BeagleTheme.companionInk.opacity(0.85))
                .frame(width: 34, height: 34)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5))
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
                        MessageBubble(message: message)
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
            .onChange(of: store.messages.last?.content) { _, _ in
                withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo(Self.bottomAnchor, anchor: .bottom) }
            }
            .onChange(of: store.messages.count) { _, _ in
                proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
            }
        }
    }

    // MARK: - Composer (the only glass)

    private var composer: some View {
        ChatComposer(
            text: $draft,
            isStreaming: store.isStreaming,
            onSend: send,
            onVoice: {}     // TODO: voice capture
        )
        .padding(.horizontal, BeagleSpacing.md)
        .padding(.bottom, BeagleSpacing.sm)
        .shadow(color: .black.opacity(0.35), radius: 18, y: 6)   // lift off the surface
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
        draft = ""
        Task { await store.sendMessage(text) }
    }

    private static let bottomAnchor = "companion.chat.bottom"
}

// MARK: - Conversation history drawer (Fase 1 polishes: search, rename, pin UI)

/// The thread list — tap to switch, swipe to delete, + to start fresh. Best-in-class history
/// (Claude/ChatGPT) so the chat is many conversations, not one.
struct ConversationDrawer: View {
    let store: ConversationStore
    @Environment(\.dismiss) private var dismiss
    @State private var reloadToken = 0

    var body: some View {
        NavigationStack {
            List {
                let threads = store.conversations()
                if threads.isEmpty {
                    Text("Nenhuma conversa ainda.")
                        .font(BeagleFont.footnote.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
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
                                        .foregroundStyle(BeagleTheme.textPrimary)
                                        .lineLimit(1)
                                    Text(conv.updatedAt, format: .relative(presentation: .named))
                                        .font(BeagleFont.caption2.font)
                                        .foregroundStyle(BeagleTheme.textTertiary)
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
            }
            .id(reloadToken)
            .navigationTitle("Conversas")
            .navigationBarTitleDisplayMode(.inline)
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

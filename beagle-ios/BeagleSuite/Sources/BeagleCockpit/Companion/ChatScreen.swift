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
    @State private var draft = ""
    @State private var appeared = false

    public init(store: ConversationStore, breathRate: Double? = nil, weather: SpaceWeatherStore.Snapshot? = nil) {
        self.store = store
        self.breathRate = breathRate
        self.weather = weather
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            hearth
            VStack(spacing: 0) {
                companionZone
                if !store.messages.isEmpty { conversation }
            }
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
    }

    // Aurora pivot (2026-06-28): the presence is the SKY, not a mascot. AuroraPresence
    // is pure SwiftUI radial gradients — no MTKView, no splat, no main-thread contention.
    // Cheap enough to live in the chat header without fighting the keyboard. Modulated
    // by breathRate (user's HRV) + hour-of-day (hue) + Kp (saturation + pulse speed).
    @ViewBuilder private var presence: some View {
        AuroraPresence(breathRate: breathRate, weather: weather,
                       size: store.messages.isEmpty ? .greeter : .header)
    }

    // Empty state: the AuroraPresence fills the upper third (greeter), greeting below.
    // Chatting state: the presence shrinks to a compact header (~120pt overall),
    // conversation takes the rest of the space above the composer.
    private var companionZone: some View {
        let empty = store.messages.isEmpty
        return VStack(spacing: BeagleSpacing.lg) {
            if empty { Spacer(minLength: 0) }
            presence
                .frame(height: empty ? 280 : 120)
                .padding(.top, empty ? 0 : 8)
                .opacity(empty ? 1 : 0.95)
            if empty {
                greeting
                Spacer(minLength: 0)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: empty ? .infinity : nil)
        .padding(.bottom, empty ? 64 : 0)
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.35), value: empty)
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

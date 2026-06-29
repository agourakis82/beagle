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
    @State private var draft = ""
    @State private var appeared = false

    public init(store: ConversationStore, breathRate: Double? = nil) {
        self.store = store
        self.breathRate = breathRate
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            hearth
            companion                       // one stable splat instance — behind the conversation, never reloads
            if !store.messages.isEmpty {
                conversation
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

    // The companion's presence — vector beagle by default; the photoreal Gaussian-splat
    // beagle behind the --beagle-splat flag (de-risk; falls back to vector if it can't load).
    @ViewBuilder private var presence: some View {
        #if os(iOS) || os(macOS)
        if ProcessInfo.processInfo.arguments.contains("--beagle-splat") {
            BeagleSplatView(motion: CompanionMotion(flowState: store.flowState, listening: store.isStreaming, breathRate: breathRate))
        } else {
            BeagleFigure(state: store.flowState, listening: store.isStreaming, breathRate: breathRate, kp: store.currentSky?.kp, dst: store.currentSky?.dst)
        }
        #else
        BeagleFigure(state: store.flowState, listening: store.isStreaming, breathRate: breathRate)
        #endif
    }

    // ONE stable companion slot — the splat (or vector fallback) lives here for the screen's
    // whole life so the MTKView/ply (24MB) never tears down between the opening and the
    // conversation. `presence` is a SINGLE non-conditional node (stable SwiftUI identity); only
    // its frame/position/opacity animate with state: a 240pt greeter when the space is empty, a
    // 132pt ambient header once the conversation fills in below it.
    private var companion: some View {
        let empty = store.messages.isEmpty
        return VStack(spacing: BeagleSpacing.lg) {
            if empty { Spacer() }
            presence                                    // single instance — never recreated
                .frame(height: empty ? 240 : 132)
                .padding(.top, empty ? 0 : 18)
                .opacity(empty ? 1 : 0.92)
            if empty {
                greeting
                Spacer()
                Spacer()
            } else {
                Spacer()
            }
        }
        .padding(.bottom, empty ? 64 : 0)
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.45), value: empty)
    }

    // A warm glow rising from where the conversation lives — turns the dead black
    // void into a hearth. Subtle; the living mesh (behind, in BeagleSurface) layers under.
    private var hearth: some View {
        RadialGradient(
            colors: [
                Color(red: 70/255, green: 46/255, blue: 40/255).opacity(0.45),
                Color(red: 30/255, green: 24/255, blue: 34/255).opacity(0.25),
                .clear
            ],
            center: UnitPoint(x: 0.5, y: 0.92),
            startRadius: 0,
            endRadius: 460
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

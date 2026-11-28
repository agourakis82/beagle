//
//  ChatScreen+Conversation.swift
//  BeagleCockpit — Companion chat chrome, ambient layers, conversation feed & empty state
//

import SwiftUI
import BeagleCore
#if canImport(UIKit)
import UIKit
#endif

extension ChatScreen {

    // MARK: - Top bar

    // Minimal top bar: history (☰) · conversation title · new (＋). Liquid Glass buttons that
    // float over the aurora. NO GlassEffectContainer/glassEffectID — those try to MORPH the glass
    // when state changes (e.g. presenting the drawer), which made the buttons flicker / lose their
    // effect on tap. Plain per-button glass is stable.
    var topBar: some View {
        VStack {
            HStack(spacing: BeagleSpacing.sm) {
                topBarButton(
                    "line.3.horizontal",
                    accessibilityLabel: "Histórico e menu",
                    accessibilityIdentifier: "chat.topBar.drawerButton"
                ) { activeSheet = .history }
                Spacer(minLength: BeagleSpacing.sm)
                VStack(spacing: 2) {
                    Text(store.currentConversationTitle)
                        .font(BeagleFont.subheadline.font.weight(.semibold))
                        .foregroundStyle(BeagleTheme.companionInk)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .accessibilityIdentifier("chat.topBar.title")
                        // Legibility over the variable aurora - a soft dark halo keeps the title
                        // readable whether it floats over bright green or deep night.
                        .shadow(color: .black.opacity(0.45), radius: 4, y: 0.5)
                    // The Agora block distilled to three words: day-part, hour, readiness (when
                    // HealthKit has a signal). Same vocabulary the server puts in the model
                    // own Agora block - never invents a state the model was not given.
                    Text(agoraStrip)
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .shadow(color: .black.opacity(0.45), radius: 4, y: 0.5)
                }
                Spacer(minLength: BeagleSpacing.sm)
                voiceTopBarControl
                topBarButton(
                    "square.and.pencil",
                    accessibilityLabel: "Nova conversa",
                    accessibilityIdentifier: "chat.topBar.newChatButton"
                ) {
                    voz.parar()
                    withAnimation(.easeOut(duration: 0.25)) { store.newConversation() }
                }
            }
            .padding(.horizontal, BeagleSpacing.md)
            .padding(.top, BeagleSpacing.sm)
            // Melt away while reading forward; glide back on scroll-up.
            .opacity(topBarHidden ? 0 : 1)
            .offset(y: topBarHidden ? -72 : 0)
            .blur(radius: topBarHidden ? 6 : 0)
            .allowsHitTesting(!topBarHidden)
            Spacer()
        }
    }

    private func topBarButton(
        _ system: String,
        accessibilityLabel: String,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
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
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    // MARK: - Presence & ambient layers

    // Aurora CURTAIN sitting BEHIND the conversation. Spans the full width;
    // drifts horizontally, ripples vertically, hue cycles, brightens when the
    // companion is streaming. Empty state: brighter and fills upper half.
    // Chatting: dimmer and pulled to upper third so the conversation reads.
    var presenceBackground: some View {
        let empty = store.messages.isEmpty
        // ATENÇÃO: cada camada tem a SUA opacidade. Antes havia um único
        // `.opacity(empty ? 0.9 : 0.28)` no retorno da propriedade; herdá-lo deixaria
        // o primordial a 28% justamente enquanto se lê — o efeito "fantasma".
        return ZStack {
            // Atrás: a aurora continua (foi construída de propósito e o usuário gosta
            // dela), mas rebaixada a cenário do cenário para não virar sopa visual.
            AuroraPresence(
                breath: breath,
                weather: weather,
                isStreaming: store.isStreaming,
                size: empty ? .greeter : .header
            )
            .opacity(empty ? 0.55 : 0.16)
            .animation(.easeOut(duration: 0.35), value: empty)

            // Na frente: o bicho. Máscara radial e curva própria de opacidade vivem
            // dentro de PrimordialPresence.
            PrimordialPresence(
                state: presenceState,
                breath: breath,
                sky: weather?.band ?? .calm
            )
            .opacity(empty ? 0.95 : 0.55)
            .animation(.easeOut(duration: 0.35), value: empty)
        }
        .allowsHitTesting(false)
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
    var hearth: some View {
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

    /// A CHEGADA — item 7 do desenho: "quando há material, ao abrir o app ele já
    /// disse algo".
    ///
    /// Visualmente distinta da carta de propósito. A fala em resposta tem serifa e
    /// a marca âmbar no início do turno; isto é um bloco recuado, com filete e uma
    /// etiqueta que diz QUANDO foi dito. A diferença não é decorativa: sem ela,
    /// algo escrito antes dele chegar leria como resposta ao que ele acabou de
    /// dizer — e ele confiaria numa réplica que nunca houve.
    @ViewBuilder
    private var aChegada: some View {
        if chegada.temAlgoADizer {
            VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
                HStack(spacing: BeagleSpacing.xxs) {
                    Text("ENQUANTO VOCÊ NÃO ESTAVA")
                        .font(.system(size: 9.5, weight: .semibold))
                        .tracking(1.3)
                        .foregroundStyle(MessageBubble.marcaAmbar.opacity(0.85))
                    Spacer(minLength: 0)
                    Button {
                        withAnimation(BeagleMotion.snappy) { chegada.dispensar() }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(BeagleTheme.textTertiary)
                            .padding(6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dispensar")
                }
                MarkdownText(
                    text: chegadaAberta ? chegada.textoCompleto : chegada.texto,
                    inkColor: BeagleTheme.companionInk.opacity(0.92),
                    bodyFont: .system(.callout, design: .serif),
                    lineSpacingPt: 5.5
                )
                if chegada.temMais {
                    Button {
                        withAnimation(BeagleMotion.snappy) { chegadaAberta.toggle() }
                    } label: {
                        Text(chegadaAberta ? "menos" : "o resto")
                            .font(BeagleFont.caption2.font)
                            .foregroundStyle(MessageBubble.marcaAmbar.opacity(0.9))
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, BeagleSpacing.sm)
            .padding(.trailing, BeagleSpacing.xs)
            .padding(.vertical, BeagleSpacing.sm)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(MessageBubble.marcaAmbar.opacity(0.5))
                    .frame(width: 2)
            }
            .frame(maxWidth: 620, alignment: .leading)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    var conversation: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    LazyVStack(spacing: BeagleSpacing.lg) {
                        aChegada
                        ForEach(store.messages) { message in
                            MessageBubble(
                                message: message,
                                isLast: message.id == store.messages.last?.id,
                                onRegenerate: { Task { await store.regenerateLastResponse() } },
                                voz: voz
                            )
                            .id(message.id)
                        }
                        // Presence LAYER — a murmur about the wait, not a line of his letter.
                        // Lives outside the message list so server-authored text never renders
                        // in serif as his voice (desenho 2026-08-02, item 5).
                        if (store.isStreaming || gptLive.activeDelegationCount > 0),
                           let note = store.presenceNote,
                           !note.isEmpty {
                            Text(note)
                                .font(BeagleFont.footnote.font.italic())
                                .foregroundStyle(BeagleTheme.textTertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, BeagleSpacing.xs)
                                .transition(.opacity)
                        }
                        // clearance so the floating composer + live voice bar never cover the last line
                        Color.clear.frame(height: liveVoice.isActive ? 136 : 72).id(Self.bottomAnchor)
                    }
                    .padding(.horizontal, BeagleSpacing.md)
                    .padding(.top, BeagleSpacing.md)
                    .frame(maxWidth: .infinity, minHeight: 0, alignment: .bottom)
                    .animation(.easeOut(duration: 0.25), value: store.messages.count)
                }
                .defaultScrollAnchor(.bottom)   // recent messages hug the composer; void goes up top
                .scrollDismissesKeyboard(.interactively)
                // Direction-based chrome melt + tail proximity tracking (R3).
                .onScrollGeometryChange(for: ConversationScrollPolicy.Metrics.self) { geo in
                    let isScrollable = geo.contentSize.height > geo.containerSize.height + 24
                    let distance = ConversationScrollPolicy.distanceFromBottom(
                        contentHeight: geo.contentSize.height,
                        contentOffsetY: geo.contentOffset.y,
                        containerHeight: geo.containerSize.height,
                        bottomInset: geo.contentInsets.bottom
                    )
                    return ConversationScrollPolicy.Metrics(
                        offsetY: geo.contentOffset.y + geo.contentInsets.top,
                        containerHeight: geo.containerSize.height,
                        contentHeight: geo.contentSize.height,
                        distanceFromBottom: distance,
                        isScrollable: isScrollable
                    )
                } action: { oldMetrics, newMetrics in
                    scrollFollowState = ConversationScrollPolicy.updatedFollowState(
                        current: scrollFollowState,
                        oldMetrics: oldMetrics,
                        newMetrics: newMetrics
                    )
                    // Ignore programmatic offset jumps caused by keyboard appearance/dismissal
                    // or orientation changes resizing the scroll container.
                    if abs(newMetrics.containerHeight - oldMetrics.containerHeight) > 1 {
                        scrollAccum = 0
                        return
                    }
                    if !newMetrics.isScrollable || newMetrics.offsetY <= 12 {
                        if topBarHidden {
                            withAnimation(.easeOut(duration: 0.3)) { topBarHidden = false }
                        }
                        scrollAccum = 0
                        return
                    }
                    let delta = newMetrics.offsetY - oldMetrics.offsetY
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
                .onChange(of: store.messages.last?.content) { _, _ in
                    let isUser = store.messages.last?.role == .user
                    let decision = ConversationScrollPolicy.nextStateOnIncomingUpdate(
                        state: scrollFollowState,
                        isUserMessage: isUser
                    )
                    scrollFollowState = decision.nextState
                    if decision.shouldScroll {
                        proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
                    }
                }
                .onChange(of: store.messages.count) { _, _ in
                    let isUser = store.messages.last?.role == .user
                    let decision = ConversationScrollPolicy.nextStateOnIncomingUpdate(
                        state: scrollFollowState,
                        isUserMessage: isUser
                    )
                    scrollFollowState = decision.nextState
                    if decision.shouldScroll {
                        withAnimation(.snappy(duration: 0.22)) {
                            proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
                        }
                    }
                    // A fresh turn brings the bar back so the title/controls are always reachable.
                    if topBarHidden { withAnimation(.easeOut(duration: 0.28)) { topBarHidden = false } }
                }

                if !scrollFollowState.isNearBottom {
                    scrollToBottomButton(hasUnread: scrollFollowState.hasUnreadBelow || store.isStreaming) {
                        scrollFollowState = ConversationScrollPolicy.resetForBottomJump()
                        withAnimation(.snappy(duration: 0.25)) {
                            proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
                        }
                    }
                    .padding(.trailing, BeagleSpacing.md)
                    .padding(.bottom, liveVoice.isActive ? 144 : 84)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.2), value: scrollFollowState.isNearBottom)
        }
    }

    private func scrollToBottomButton(hasUnread: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 12, weight: .semibold))
                if hasUnread {
                    Text("Nova resposta")
                        .font(BeagleFont.caption.font.weight(.medium))
                }
            }
            .foregroundStyle(BeagleTheme.companionInk.opacity(0.95))
            .padding(.horizontal, hasUnread ? 12 : 10)
            .padding(.vertical, 9)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 0.75))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(hasUnread ? "Ir para a nova resposta" : "Ir para o final da conversa")
        .accessibilityIdentifier("chat.scrollToBottomButton")
    }

    // MARK: - Composer (the only glass)

    var composer: some View {
        ChatComposer(
            text: $draft,
            depth: $depth,
            attachedImageData: $attachedImageData,
            attachedDocument: $attachedDocument,
            isStreaming: store.isStreaming,
            onSend: send,
            voice: voice,
            // Só o turno FALADO carrega tom. Digitado envia nil, e nil significa
            // "não falei" — não "falei normal".
            onVoiceCommit: { falado in
                handleVoiceCommittedUtterance(falado)
            },
            onWillArmVoice: {
                voz.parar()
            },
            onRequestCamera: {
                #if os(iOS)
                activeSheet = .camera
                #endif
            },
            onRequestScanner: {
                #if os(iOS)
                activeSheet = .documentScanner
                #endif
            }
        )
        .padding(.horizontal, BeagleSpacing.md)
        .padding(.bottom, BeagleSpacing.sm)
        .shadow(color: .black.opacity(0.35), radius: 18, y: 6)   // lift off the surface
    }

    // MARK: - Empty state (warm, zero-friction — no forms)

    var greeting: some View {
        let story = BodyStory.opening(physioSnapshot, hour: Calendar.current.component(.hour, from: Date()))
        return VStack(spacing: BeagleSpacing.md) {
            VStack(spacing: BeagleSpacing.sm) {
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
            .padding(.horizontal, BeagleSpacing.xl)

            quickLaunchCapsules
        }
        .frame(maxWidth: .infinity)
    }

    private var quickLaunchCapsules: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BeagleSpacing.xs + 2) {
                if let onOpenDailySynthesis {
                    quickLaunchChip(
                        title: DailyBriefingBuilder.cachedTodaySynthesis() != nil ? "Síntese pronta" : "Síntese matinal",
                        systemImage: "sun.horizon.fill",
                        tint: BeagleTheme.postureWarm,
                        action: onOpenDailySynthesis
                    )
                }

                if let onOpenDeepExploration {
                    quickLaunchChip(
                        title: "Modo Fundo",
                        systemImage: "scope",
                        tint: BeagleTheme.truthRemembered,
                        action: onOpenDeepExploration
                    )
                }

                quickLaunchChip(
                    title: liveVoice.isActive ? "Voz ativa" : "Voz mãos-livres",
                    systemImage: "waveform.badge.mic",
                    tint: BeagleTheme.truthObserved
                ) {
                    Task {
                        if liveVoice.isActive {
                            endLiveVoiceSession()
                        } else {
                            await startLiveVoiceSession()
                        }
                    }
                }

                if let onOpenData {
                    let kpLabel: String = {
                        if let kp = weather?.kp {
                            return String(format: "Agora · Kp %.1f", kp)
                        }
                        return "Agora · Corpo & Céu"
                    }()
                    quickLaunchChip(
                        title: kpLabel,
                        systemImage: "sparkles",
                        tint: BeagleTheme.auroraTeal,
                        action: onOpenData
                    )
                }
            }
            .padding(.horizontal, BeagleSpacing.lg)
        }
    }

    private func quickLaunchChip(
        title: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            #endif
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(BeagleFont.caption.font.weight(.medium))
                    .foregroundStyle(BeagleTheme.companionInk.opacity(0.9))
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(tint.opacity(0.28), lineWidth: 0.75))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Agora strip (top bar)

    /// Day-part word for the top bar. Same hour buckets as BodyStory.salutation so the
    /// greeting and the strip never disagree about what time of day it is.
    private var periodWord: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12:  return "manhã"
        case 12..<18: return "tarde"
        case 18..<24: return "noite"
        default:      return "madrugada"
        }
    }

    private var hourString: String {
        "\(Calendar.current.component(.hour, from: Date()))h"
    }

    /// Same readiness word the server puts in the model's ## Agora block
    /// (temporal-context.mjs readinessPtBR) — derived from store.physioSummary, NOT
    /// posture, so the strip never contradicts what the model was just told. nil when
    /// there's no HealthKit signal to derive it from (never invents a state).
    private var stateWord: String? {
        switch store.physioSummary?.readiness {
        case .restored: return "recuperado"
        case .steady: return "estável"
        case .strained: return "tenso"
        case .unavailable, .none: return nil
        }
    }

    private var agoraStrip: String {
        var parts = [periodWord, hourString]
        if let stateWord { parts.append(stateWord) }
        return parts.joined(separator: " · ")
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

    private static let bottomAnchor = "companion.chat.bottom"


}

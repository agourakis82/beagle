//
//  PrimordialPresence.swift
//  BeagleCockpit — Companion: a presença em vídeo
//
//  Quatro laços fotográficos (adormecido / atento / ouvindo / pensando) trocados
//  por fade CRUZADO conforme o estado do app. Um bicho só, não quatro clipes.
//
//  Decisões que não são gosto:
//
//  • AVPlayerLayer cru, não `VideoPlayer`/AVKit — AVKit traz chrome (controles,
//    gesto de play/pause, badge de AirPlay) numa camada que precisa ser cenário.
//  • DUAS camadas A/B, cada uma com AVQueuePlayer + AVPlayerLooper. A nova entra
//    em opacity 0→1 em 0.6s enquanto a antiga sai; só depois a antiga é liberada.
//    Trocar o item de UM player pisca (o layer fica preto entre itens).
//  • Silencioso em dois níveis: `isMuted` aqui E `-an` no pipeline (os .mp4 não
//    têm faixa de áudio). O app disputa AVAudioSession com SpeechRecognizer,
//    Moshi e a captura de voz; um player com trilha pode derrubar uma gravação
//    em curso. Este arquivo NÃO toca em AVAudioSession — de propósito.
//  • Pausa fora de `.active`, e cai para poster estático em Reduce Motion e em
//    Low Power Mode. A tela de chat já roda AuroraPresence (Canvas + TimelineView
//    a 20fps); somar decodificação contínua a isso é justamente o que aquece o
//    aparelho enquanto se lê parágrafo longo parado.
//  • `#if os(iOS)/os(macOS)` no representable: o target BeagleCockpit declara
//    supportedDestinations [iOS, macOS] e UIViewRepresentable não existe no Mac.
//    Mesmo padrão de Splat/MetalKitSceneView.swift.
//
//  NÃO MEDIDO AINDA (precisa de aparelho): consumo/calor com o Aurora junto, e se
//  o vídeo compõe bem sobre o hearth ou fica com cara de fantasma. A opacidade e
//  a máscara radial abaixo são um primeiro palpite, não uma conclusão.
//

import SwiftUI
import AVFoundation
import BeagleCore

#if os(macOS)
import AppKit
private typealias PresenceRepresentable = NSViewRepresentable
private typealias PresencePlatformView = NSView
#else
import UIKit
private typealias PresenceRepresentable = UIViewRepresentable
private typealias PresencePlatformView = UIView
#endif

// MARK: - Localização dos recursos

enum PresenceAssets {
    /// Os .mp4/.png vivem em Sources/BeagleCockpit/Resources/Presence/ e o xcodegen
    /// os empacota junto com bula.sqlite. O bundle normalmente ACHATA isso; a
    /// segunda tentativa cobre o caso de virar folder reference.
    static func loopURL(for state: PresenceState) -> URL? {
        Bundle.main.url(forResource: state.loopResource, withExtension: "mp4")
            ?? Bundle.main.url(forResource: state.loopResource, withExtension: "mp4", subdirectory: "Presence")
    }

    static func posterURL(for state: PresenceState) -> URL? {
        Bundle.main.url(forResource: state.loopResource, withExtension: "png")
            ?? Bundle.main.url(forResource: state.loopResource, withExtension: "png", subdirectory: "Presence")
    }

    /// Falso quando os laços não foram empacotados — a vista some em silêncio em
    /// vez de deixar um retângulo preto no lugar da presença.
    static var isAvailable: Bool { loopURL(for: .atento) != nil }
}

// MARK: - Host AVPlayerLayer (A/B)

@MainActor
private final class PresenceHostView: PresencePlatformView {

    /// Uma "voz" do crossfade: player + looper + camada. Os três morrem juntos.
    private final class Voice {
        let player: AVQueuePlayer
        let looper: AVPlayerLooper
        let layer: AVPlayerLayer
        let state: PresenceState

        init?(state: PresenceState) {
            guard let url = PresenceAssets.loopURL(for: state) else { return nil }
            let item = AVPlayerItem(asset: AVURLAsset(url: url))
            let queue = AVQueuePlayer()
            queue.isMuted = true
            // Sem áudio na origem; ainda assim explicitamos que este player não
            // deve influenciar a sessão de áudio de ninguém.
            queue.preventsDisplaySleepDuringVideoPlayback = false
            let looper = AVPlayerLooper(player: queue, templateItem: item)
            let layer = AVPlayerLayer(player: queue)
            layer.videoGravity = .resizeAspectFill
            layer.opacity = 0
            self.player = queue
            self.looper = looper
            self.layer = layer
            self.state = state
        }

        func dispose() {
            player.pause()
            player.removeAllItems()
            layer.removeFromSuperlayer()
        }
    }

    private var voices: [Voice] = []
    private var paused = false

    var currentState: PresenceState? { voices.last?.state }

    #if os(macOS)
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = .clear
    }
    override func layout() {
        super.layout()
        layoutVoices()
    }
    #else
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        layoutVoices()
    }
    #endif

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) não usado") }

    private func layoutVoices() {
        // Sem animação implícita no frame: o resize não pode virar um deslize.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for v in voices { v.layer.frame = bounds }
        CATransaction.commit()
    }

    /// Entra com `state` por cima e apaga o anterior. Idempotente.
    func show(_ state: PresenceState, crossfade: TimeInterval) {
        guard currentState != state else { return }
        guard let voice = Voice(state: state) else { return }

        voice.layer.frame = bounds
        #if os(macOS)
        layer?.addSublayer(voice.layer)
        #else
        layer.addSublayer(voice.layer)
        #endif
        voices.append(voice)
        if !paused { voice.player.play() }

        // Identidade, não estado: se o usuário oscilar entre dois estados rápido,
        // comparar por `state` aposentaria a voz errada.
        let outgoing = Array(voices.dropLast())

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            // O completion do CATransaction chega fora do MainActor no Swift 6.
            Task { @MainActor in self?.retire(outgoing) }
        }
        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0
        fadeIn.toValue = 1
        fadeIn.duration = crossfade
        fadeIn.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        voice.layer.opacity = 1
        voice.layer.add(fadeIn, forKey: "presence.fadeIn")
        // A antiga NÃO some por opacidade: ela fica por baixo em opacidade cheia
        // até a nova cobrir. Cross-dissolve de duas camadas translúcidas deixaria
        // o hearth aparecer no meio da troca.
        CATransaction.commit()
    }

    private func retire(_ dying: [Voice]) {
        let doomed = Set(dying.map(ObjectIdentifier.init))
        // Nunca aposentar a voz do topo, mesmo que ela apareça na lista.
        guard let live = voices.last else { return }
        for v in voices where doomed.contains(ObjectIdentifier(v)) && v !== live {
            v.dispose()
        }
        voices.removeAll { doomed.contains(ObjectIdentifier($0)) && $0 !== live }
    }

    func setPaused(_ value: Bool) {
        guard paused != value else { return }
        paused = value
        for v in voices {
            if value { v.player.pause() } else { v.player.play() }
        }
    }

    func teardown() {
        for v in voices { v.dispose() }
        voices.removeAll()
    }
}

// MARK: - Representable

private struct PresenceVideoLayer: PresenceRepresentable {
    let state: PresenceState
    let paused: Bool
    let crossfade: TimeInterval

    #if os(macOS)
    func makeNSView(context: Context) -> NSView { makeHost() }
    func updateNSView(_ nsView: NSView, context: Context) { update(nsView) }
    static func dismantleNSView(_ nsView: NSView, coordinator: ()) { (nsView as? PresenceHostView)?.teardown() }
    #else
    func makeUIView(context: Context) -> UIView { makeHost() }
    func updateUIView(_ uiView: UIView, context: Context) { update(uiView) }
    static func dismantleUIView(_ uiView: UIView, coordinator: ()) { (uiView as? PresenceHostView)?.teardown() }
    #endif

    @MainActor private func makeHost() -> PresenceHostView {
        let host = PresenceHostView(frame: .zero)
        // Primeira entrada sem fade: não há nada para cruzar.
        host.show(state, crossfade: 0.01)
        host.setPaused(paused)
        return host
    }

    @MainActor private func update(_ view: PresencePlatformView) {
        guard let host = view as? PresenceHostView else { return }
        host.show(state, crossfade: crossfade)
        host.setPaused(paused)
    }
}

// MARK: - A vista pública

/// A presença primordial: um laço de vídeo por estado, com fade cruzado, mais uma
/// camada de calor que respira no ritmo declarado por `PresenceBreath`.
struct PrimordialPresence: View {
    let state: PresenceState
    let breath: PresenceBreath
    let sky: SkyBand

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var inhaled = false

    /// Vídeo pausado ⇒ mostrar o poster no lugar do laço.
    private var isStill: Bool { reduceMotion || lowPower }
    private var isPaused: Bool { scenePhase != .active }

    /// Tinta do céu. Deliberadamente sutil: a presença é um bicho, não um medidor
    /// geomagnético — a tempestade esquenta a luz, não pinta a tela.
    private var skyTint: Color {
        switch sky {
        case .calm:   return Color(red: 1.00, green: 0.68, blue: 0.38)
        case .active: return Color(red: 1.00, green: 0.55, blue: 0.30)
        case .storm:  return Color(red: 1.00, green: 0.40, blue: 0.28)
        }
    }

    var body: some View {
        Group {
            if PresenceAssets.isAvailable {
                ZStack {
                    if isStill {
                        posterImage
                    } else {
                        PresenceVideoLayer(state: state, paused: isPaused, crossfade: 0.6)
                    }
                    heatOverlay
                }
                // Máscara radial: a presença não pode ler como um retângulo de vídeo
                // atrás do texto. As bordas dissolvem no hearth.
                .mask(
                    RadialGradient(
                        colors: [.white, .white.opacity(0.85), .clear],
                        center: .init(x: 0.5, y: 0.34),
                        startRadius: 0,
                        endRadius: 320
                    )
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(.easeOut(duration: 0.4), value: isStill)
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        #endif
        .onAppear { startBreathing() }
        .onChange(of: breath) { _, _ in startBreathing() }
    }

    @ViewBuilder
    private var posterImage: some View {
        #if os(iOS)
        if let url = PresenceAssets.posterURL(for: state), let img = UIImage(contentsOfFile: url.path) {
            Image(uiImage: img).resizable().scaledToFill()
        }
        #else
        if let url = PresenceAssets.posterURL(for: state), let img = NSImage(contentsOfFile: url.path) {
            Image(nsImage: img).resizable().scaledToFill()
        }
        #endif
    }

    /// Calor por cima, respirando. Core Animation (repeatForever) e não
    /// TimelineView: uma segunda fonte de redraw por frame nesta tela é
    /// exatamente o que se quer evitar. Amplitude vem de `PresenceBreath` —
    /// `.neutral` pulsa menos, então "sem dado" é visível.
    private var heatOverlay: some View {
        let amp = breath.amplitude
        let low = 0.10 * amp
        let high = (0.10 + 0.16) * amp
        return RadialGradient(
            colors: [skyTint.opacity(0.55), skyTint.opacity(0.0)],
            center: .init(x: 0.5, y: 0.40),
            startRadius: 10,
            endRadius: 260
        )
        .opacity(inhaled ? high : low)
        .blendMode(.plusLighter)
    }

    private func startBreathing() {
        inhaled = false
        guard !isStill else { return }
        withAnimation(.easeInOut(duration: breath.period / 2).repeatForever(autoreverses: true)) {
            inhaled = true
        }
    }
}

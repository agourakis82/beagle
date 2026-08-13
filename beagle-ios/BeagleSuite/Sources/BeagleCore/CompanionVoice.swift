//
//  CompanionVoice.swift
//  BeagleCore — a boca dele, do lado do aparelho
//
//  Item 6b do desenho de presença. O servidor vocaliza (xAI realtime) o texto que
//  o Opus JÁ compôs e devolve WAV; aqui a gente só toca.
//
//  A CHAVE DA xAI NÃO VIVE AQUI e não deve viver nunca. O token do cockpit passou
//  cinco semanas legível num arquivo público do GitHub (06-ago-2026); repetir
//  isso com uma chave paga seria não aprender nada.
//
//  AVAudioPlayer, não AVAudioEngine: o engine derrubou o app hoje mesmo ao abrir
//  o microfone (AVAudioEngineGraph::Initialize lançando NSException, que Swift
//  não captura). Tocar um WAV pronto não precisa de grafo.
//

import Foundation
import Observation
#if canImport(AVFoundation)
import AVFoundation
#endif

// AVAudioSession não existe no macOS, e `swift test` compila para macOS.
// canImport(AVFoundation) passa lá; a sessão de áudio não. Guardar por
// PLATAFORMA, não por módulo.
#if os(iOS) || os(visionOS) || os(watchOS)
let TEM_SESSAO_DE_AUDIO = true
#else
let TEM_SESSAO_DE_AUDIO = false
#endif

@Observable
@MainActor
public final class CompanionVoice: NSObject {
    public private(set) var buscando: Bool = false
    public private(set) var falandoId: String?
    /// Última recusa legível. O guarda do servidor devolve 422 quando a boca
    /// divergiu do texto — não é erro a esconder, é o sistema funcionando.
    public private(set) var recusa: String?

    private let client: BeagleClient
    #if canImport(AVFoundation)
    private var player: AVAudioPlayer?
    #endif

    public init(client: BeagleClient = .shared) {
        self.client = client
        super.init()
    }

    public func estaFalando(_ id: String) -> Bool { falandoId == id }

    /// Vocaliza `texto`. `id` é só para a UI saber qual bolha está falando.
    public func falar(_ texto: String, id: String) async {
        guard !buscando else { return }
        parar()
        recusa = nil
        buscando = true
        defer { buscando = false }

        let r = await client.fetchCompanionVoice(text: texto)
        guard let wav = r.value else {
            // Cai para texto em silêncio: a carta já está na tela, e é a fonte.
            recusa = r.error
            return
        }
        tocar(wav, id: id)
    }

    public func parar() {
        #if canImport(AVFoundation)
        player?.stop()
        player = nil
        #endif
        falandoId = nil
    }

    private func tocar(_ dados: Data, id: String) {
        #if os(iOS) || os(visionOS)
        do {
            // `.playback` com `.spokenAudio`: respeita o botão de silencioso do
            // aparelho? Não — e isso é deliberado. Se ele segurou para falar, ele
            // quer ouvir a resposta; e o caminho de voz é o caminho de quem está
            // com a tela longe dos olhos.
            let s = AVAudioSession.sharedInstance()
            try s.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try s.setActive(true)
            let p = try AVAudioPlayer(data: dados)
            p.delegate = self
            guard p.prepareToPlay(), p.play() else {
                recusa = "não consegui tocar o áudio"
                return
            }
            player = p
            falandoId = id
        } catch {
            recusa = error.localizedDescription
            falandoId = nil
        }
        #else
        recusa = "sem sessão de áudio nesta plataforma"
        #endif
    }
}

#if os(iOS) || os(visionOS)
extension CompanionVoice: AVAudioPlayerDelegate {
    nonisolated public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.falandoId = nil
            self?.player = nil
            // Devolve a sessão: sem isto, a captura de voz do turno seguinte pode
            // encontrar a rota de áudio ocupada.
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}
#endif

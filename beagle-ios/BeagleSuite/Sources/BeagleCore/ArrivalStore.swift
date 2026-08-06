//
//  ArrivalStore.swift
//  BeagleCore — o que ele deixou enquanto você não estava
//
//  Item 7 do desenho de presença (2026-08-02): "quando há material, ao abrir o
//  app ele JÁ disse algo".
//
//  A PAREDE É ESTRUTURAL, não visual. Este texto vive num tipo PRÓPRIO e nunca
//  toca `ConversationStore.messages` — é impossível ele virar turno de conversa
//  por acidente, porque não existe caminho de código que o coloque lá. O
//  desenho pede que a síntese "nunca vaze para a conversa"; uma flag booleana
//  numa mensagem seria uma promessa, um tipo separado é uma garantia.
//
//  Mesmo padrão que a camada de presença já usa em ChatScreen: texto de origem
//  diferente mora fora da lista de mensagens.
//

import Foundation
import Observation

@Observable
@MainActor
public final class ArrivalStore {
    public private(set) var texto: String = ""
    public private(set) var carregando: Bool = false
    /// O servidor disse que não há material bastante. NÃO é erro — é o companion
    /// se recusando a sintetizar do nada, que é o invariante que mais importa aqui.
    public private(set) var insuficiente: Bool = false

    private let client: BeagleClient
    private var buscouNestaSessao = false

    private static let chaveVisto = "beagle.chegada.vista.em"

    public init(client: BeagleClient = .shared) {
        self.client = client
    }

    public var temAlgoADizer: Bool { !texto.isEmpty && !insuficiente }

    /// Uma vez por sessão, e no máximo uma por dia.
    ///
    /// Sem o teto diário ele abriria o app dez vezes e leria a mesma síntese dez
    /// vezes — e o que era presença viraria repetição. Uma vez por dia é o
    /// ritmo de algo que foi DEIXADO, não de uma notificação.
    public func buscarSeForHora() async {
        guard !buscouNestaSessao, !carregando else { return }
        guard NetworkMonitor.shared.isOnline else { return }
        if let visto = UserDefaults.standard.object(forKey: Self.chaveVisto) as? Date,
           Calendar.current.isDateInToday(visto) { return }
        buscouNestaSessao = true
        carregando = true
        defer { carregando = false }

        let r = await client.fetchArrivalSynthesis(windowDays: 3)
        guard let s = r.value else { return }
        if s.insuficiente {
            insuficiente = true
            return
        }
        let limpo = s.texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpo.isEmpty else { return }
        texto = limpo
        UserDefaults.standard.set(Date(), forKey: Self.chaveVisto)
    }

    /// Ele leu (ou fechou). Some até amanhã — nunca volta na mesma sessão.
    public func dispensar() {
        texto = ""
        UserDefaults.standard.set(Date(), forKey: Self.chaveVisto)
    }
}

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
    /// O que aparece na chegada: só o Elevator. Curto de propósito.
    public private(set) var texto: String = ""
    /// A síntese inteira, para quem quiser ler o resto.
    public private(set) var textoCompleto: String = ""
    public var temMais: Bool { textoCompleto.count > texto.count + 40 }
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
        textoCompleto = limpo
        texto = Self.soElevator(limpo)
        UserDefaults.standard.set(Date(), forKey: Self.chaveVisto)
    }

    /// A síntese vem em cinco seções (Elevator, Espinha, O que você circula,
    /// Perguntas abertas, Próximo movimento) — cerca de 11 mil caracteres.
    ///
    /// A chegada mostra SÓ o Elevator, que é a versão curta por desenho (~900
    /// chars). Despejar as cinco no topo do chat foi o que ele viu ao abrir o
    /// app: um muro de texto antes de ter perguntado qualquer coisa. "Ele já
    /// disse algo" é UMA coisa dita, não um ensaio.
    static func soElevator(_ completo: String) -> String {
        let linhas = completo.components(separatedBy: "\n")
        var fora: [String] = []
        var dentro = false
        for l in linhas {
            let t = l.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("## ") {
                if dentro { break }                 // chegou na segunda seção
                dentro = true
                continue                            // o título não entra: quem lê já sabe que é ele
            }
            if dentro { fora.append(l) }
        }
        let corpo = fora.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        // Sem seções (formato mudou): cai para o primeiro parágrafo, nunca para o texto inteiro.
        if corpo.isEmpty {
            return completo.components(separatedBy: "\n\n").first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? completo
        }
        return corpo
    }

    /// Ele leu (ou fechou). Some até amanhã — nunca volta na mesma sessão.
    public func dispensar() {
        texto = ""
        textoCompleto = ""
        UserDefaults.standard.set(Date(), forKey: Self.chaveVisto)
    }
}

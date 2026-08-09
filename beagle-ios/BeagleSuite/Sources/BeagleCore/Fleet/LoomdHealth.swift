import Foundation

/// A saúde da fonte MEDIDA — o loomd, supervisor por protocolo que roda dentro do pod do
/// workspace — como o frame `{t:"sessions"}` a declara no bloco `loomd:{…}`
/// (server/loom/broker.mjs, `_loomdTruth()`).
///
/// Existe porque a queda dessa fonte era INVISÍVEL na tela. O cliente fazia
/// `lanes = arr.compactMap(LaneSnapshot.init(loom:))` e jogava o resto do frame fora: o loomd
/// caía, o card da lane servida por ele simplesmente sumia do board, e não sobrava modo, motivo
/// nem nome. Um card a menos ninguém nota — e a metade "a fonte boa caiu" da pergunta ficava
/// sem resposta na única superfície que importa.
public struct LoomdHealth: Sendable, Equatable {

    /// Os cinco modos que o servidor emite. NÃO são graus da mesma coisa, e a faixa depende
    /// dessa diferença: `stale`/`down` são MEDIÇÕES (perguntamos, e a resposta foi ruim);
    /// `absent`/`unknown` são a ausência de qualquer medição sobre a fonte.
    public enum Mode: String, Sendable, CaseIterable {
        /// Respondeu, e a leitura ainda está dentro da janela de frescor do servidor.
        case observed
        /// Respondeu um dia; a última leitura boa envelheceu além do teto.
        case stale
        /// Perguntamos em `127.0.0.1:4400` dentro do pod e não veio resposta utilizável.
        case down
        /// O exec nem trouxe o bloco `@@LOOMD:` — cockpit desatualizado.
        case absent
        /// Nunca perguntamos: não há leitor de loomd deste lado.
        case unknown
    }

    public let mode: Mode
    /// O relógio do LOOMD na última leitura boa (`observed_at_ms`). Não é o do cockpit.
    public let observedAt: Date?
    /// O relógio do COCKPIT no sweep que leu — o único contra o qual o frescor pode ser medido.
    public let readAt: Date?
    /// Quantas lanes a fonte servia na última leitura boa.
    public let lanes: Int
    /// As lanes que ela servia e parou de servir, NOMEADAS. Sem isto a queda seria "um card a
    /// menos", que é exatamente a forma de perda que ninguém percebe.
    public let lost: [String]
    /// O motivo nas palavras do servidor. Ele sabe mais do que o cliente poderia adivinhar
    /// ("loomd não respondeu em 127.0.0.1:4400 dentro do pod").
    public let error: String?
    /// Trava do cliente: esta fonte já respondeu nesta sessão. Sem isto não há como separar
    /// QUEDA (havia algo, e sumiu) de AUSÊNCIA (nunca houve) — e é essa distinção que decide
    /// se a tela fala ou fica calada.
    public let everObserved: Bool

    public init(
        mode: Mode,
        observedAt: Date? = nil,
        readAt: Date? = nil,
        lanes: Int = 0,
        lost: [String] = [],
        error: String? = nil,
        everObserved: Bool = false
    ) {
        self.mode = mode
        self.observedAt = observedAt
        self.readAt = readAt
        self.lanes = lanes
        self.lost = lost
        self.error = error
        self.everObserved = everObserved
    }

    /// Decodifica o bloco `loomd` de um frame `sessions`.
    ///
    /// Um `mode` que não reconhecemos cai em `.unknown`, o lado CALADO — nunca em `.observed`.
    /// Promover um valor desconhecido a "ao vivo" esconderia justamente a queda que este tipo
    /// existe para mostrar.
    public init(loom obj: [String: Any], everObserved: Bool = false) {
        self.mode = Mode(rawValue: (obj["mode"] as? String) ?? "") ?? .unknown
        self.observedAt = Self.date(obj["observedAt"])
        self.readAt = Self.date(obj["readAt"])
        self.lanes = (obj["lanes"] as? Int) ?? 0
        self.lost = (obj["lost"] as? [Any])?.compactMap { $0 as? String } ?? []
        let motivo = (obj["error"] as? String) ?? ""
        self.error = motivo.isEmpty ? nil : motivo
        self.everObserved = everObserved
    }

    private static func date(_ any: Any?) -> Date? {
        guard let ms = any as? Double, ms > 0 else { return nil }
        return Date(timeIntervalSince1970: ms / 1000)
    }

    /// Cópia com outra lista de perdidas. O cliente tem uma lista melhor que a do servidor: o
    /// `lost` do servidor zera quando o cockpit reinicia, mas a lane continua fora do board.
    public func naming(lost novas: [String]) -> LoomdHealth {
        LoomdHealth(
            mode: mode, observedAt: observedAt, readAt: readAt, lanes: lanes,
            lost: novas, error: error, everObserved: everObserved
        )
    }

    /// Cópia com a trava do cliente aplicada.
    public func remembering(everObserved visto: Bool) -> LoomdHealth {
        LoomdHealth(
            mode: mode, observedAt: observedAt, readAt: readAt, lanes: lanes,
            lost: lost, error: error, everObserved: visto
        )
    }

    // MARK: - Quando isto merece pixel

    /// A fonte está entregando o que promete.
    public var isHealthy: Bool { mode == .observed }

    /// Vale uma faixa na tela?
    ///
    /// Banner sempre-ligado vira papel de parede e para de ser lido — é a lei da casa (o
    /// `coordSection` só aparece quando há hazard ou conflito de verdade). Então:
    ///
    /// - `down`/`stale` FALAM sempre: o cockpit perguntou e a resposta foi ruim. Isso é uma
    ///   medição sobre a fonte, com motivo específico do servidor, e é acionável.
    /// - `absent` FALA sempre, e isto MUDOU em 09-ago-2026. Antes exigia `everObserved` ou
    ///   `lost` — e a crítica de completude mostrou que isso calava justamente o cenário MAIS
    ///   PROVÁVEL: pod novo (o `workspace-ssh` já reiniciou 25×), loomd nunca subiu, nada
    ///   observado, `lost` vazio → silêncio, e o board volta a ser 100% adivinhado sem dizer.
    ///   O buraco mais provável era o único mudo. Hoje existe um CronJob que sobe o loomd a cada
    ///   5 min, então `absent` deixou de ser "talvez nunca tenha existido" e passou a ser
    ///   "deveria estar lá e não está" — acionável.
    /// - `unknown` segue calado por padrão, porque significa OUTRA coisa: o cockpit não tem
    ///   leitor de loomd (imagem antiga). Não há nada que ele possa fazer na tela sobre isso, e
    ///   uma faixa permanente viraria papel de parede — que é a lei da casa.
    public var isDegraded: Bool {
        switch mode {
        case .observed:     return false
        case .down, .stale: return true
        case .absent:       return true
        case .unknown:      return everObserved || !lost.isEmpty
        }
    }

    // MARK: - Como isto se diz

    /// O nome do modo, curto, para a faixa.
    public var modeLabel: String {
        switch mode {
        case .observed: return "ao vivo"
        case .stale:    return "leitura velha"
        case .down:     return "caída"
        case .absent:   return "ausente"
        case .unknown:  return "desconhecida"
        }
    }

    /// O motivo. Verbatim do servidor quando ele tem um; caso contrário, o que o modo já diz.
    public var reason: String {
        if let error, !error.isEmpty { return error }
        switch mode {
        case .observed: return "o loomd respondeu neste sweep"
        case .stale:    return "a última leitura boa do loomd envelheceu"
        case .down:     return "o loomd não respondeu dentro do pod"
        case .absent:   return "o cockpit não trouxe o bloco do loomd"
        case .unknown:  return "ninguém perguntou ao loomd"
        }
    }

    /// A frase que impede a lane de sumir calada do board.
    public var lostSentence: String? {
        guard !lost.isEmpty else { return nil }
        let nomes = lost.joined(separator: " · ")
        return lost.count == 1
            ? "\(nomes) saiu do board junto"
            : "\(nomes) saíram do board junto"
    }

    /// Uma linha só — é o que o leitor de tela ouve, e é onde o teste morde. O card visual não
    /// pode ser o único lugar onde esta informação existe.
    public var headline: String {
        var frase = "Fonte medida \(modeLabel). \(reason)"
        if let perdidas = lostSentence { frase += ". \(perdidas)" }
        return frase
    }
}

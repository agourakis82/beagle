//
//  InstanteDoEstado.swift
//  BeagleCore — quando o estado aconteceu, declarado pelo sujeito
//
//  ## Por que isto existe
//
//  A Fase 2 confronta o que ele diz sentir com o que o corpo registrou, numa janela de ±60 min.
//  Isso exige saber QUANDO o estado aconteceu. Até 18-ago-2026 o sistema não sabia: media-se
//  contra o instante em que a frase chegou ao servidor.
//
//  O número que fechou a questão: dos 10 auto-relatos que o funil contava como tendo hora, os
//  10 tinham hora IMPUTADA do momento da fala. Zero declarados. E em 60 dias, nenhum dos 26.617
//  registros do sujeito trazia hora explícita no texto — as âncoras que existem são grossas
//  ("hoje", "acordei", "hoje passei o dia"), nenhuma é um instante.
//
//  Conserto no extrator não resolveria: medido, o extrator JÁ tira a hora quando o texto a dá.
//  Não havia o que tirar. O instante tem que nascer aqui, na origem.
//
//  ## A regra, e por que o padrão é não declarar
//
//  O `direcao-v2` (congelado, SHA d695e800…) só admite ao confronto o relato cujo instante foi
//  **declarado**. Hora deduzida da fala é inelegível.
//
//  Por isso o padrão aqui é `nil` — **nenhuma** âncora. Sem toque, o turno segue exatamente como
//  hoje: instante imputado, inelegível, zero regressão e zero atrito. A elegibilidade nasce de
//  um ATO do sujeito.
//
//  Isso inclui tocar em "agora". Pode parecer redundante — o servidor já carimbaria agora — mas
//  não é a mesma coisa: hoje o sistema *supõe* que o relato é sobre o presente; com o toque, ele
//  *sabe*, porque foi dito. A diferença entre suposição e declaração é a coisa toda que a Fase 2
//  mede, e um padrão silencioso de "agora" apagaria justamente essa diferença.
//
//  ## O que NÃO tem aqui, de propósito
//
//  **Âncoras vagas convencionadas.** "De manhã" não é 08:00; mapear uma na outra seria imputação
//  com outro nome, e ainda por cima disfarçada de declaração — pior que o problema que isto
//  conserta.
//
//  **"Ao acordar" resolvido pelo HealthKit.** O relógio sabe a hora em que ele acordou, e seria
//  tentador. Mas datar o relato pela fisiologia e depois confrontar esse relato com a fisiologia
//  destrói a independência entre as duas modalidades — que é a tese inteira da Fase 2. A medida
//  não pode fornecer o eixo do tempo do que ela vai testar.
//
//  Sobram as âncoras que o próprio sujeito consegue afirmar com precisão de instante: agora, um
//  deslocamento curto para trás, ou um horário escolhido.
//

import Foundation

/// Quando o estado aconteceu, segundo o sujeito.
///
/// `nil` (a ausência deste valor) significa "não declarado" e é o padrão — ver a nota de topo.
public enum AncoraTemporal: Equatable, Sendable {
    /// O estado é sobre este momento. Declaração, não suposição.
    case agora
    /// Deslocamento para trás a partir de agora, em minutos. Para "há uma hora", "há 3 horas".
    case atras(minutos: Int)
    /// Instante escolhido no seletor.
    case horario(Date)

    /// As opções rápidas oferecidas antes do seletor.
    ///
    /// Curtas de propósito: um relato de estado que o sujeito consegue situar com precisão de
    /// instante é recente. Além de algumas horas a memória do INSTANTE já não sustenta uma
    /// janela de ±60 min, e oferecer a opção convidaria a uma precisão que não existe.
    public static let rapidas: [AncoraTemporal] = [
        .agora,
        .atras(minutos: 60),
        .atras(minutos: 180),
        .atras(minutos: 360),
    ]

    public var rotulo: String {
        switch self {
        case .agora: return "agora"
        case .atras(let m):
            if m % 60 == 0 { return "há \(m / 60)h" }
            return "há \(m)min"
        case .horario(let d): return Self.formatadorCurto.string(from: d)
        }
    }

    /// O instante, resolvido no relógio do dispositivo.
    ///
    /// `agora` e `atras` são resolvidos NA HORA DO ENVIO e não na hora do toque: entre escolher a
    /// âncora e apertar enviar pode passar tempo — redigindo, corrigindo, sendo interrompido — e
    /// congelar o instante no toque gravaria a hora de uma decisão de interface, não a do estado.
    public func instante(agora referencia: Date = Date()) -> Date {
        switch self {
        case .agora: return referencia
        case .atras(let m): return referencia.addingTimeInterval(-Double(m) * 60)
        case .horario(let d): return d
        }
    }

    private static let formatadorCurto: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = "HH:mm"
        return f
    }()

    /// Identificador estável para viajar no payload, ao lado do instante.
    ///
    /// O instante sozinho não diz COMO foi obtido, e depois ninguém consegue separar um horário
    /// escolhido a dedo de um deslocamento aproximado. A precisão de cada forma é diferente, e
    /// quem for analisar precisa poder estratificar por ela.
    public var chave: String {
        switch self {
        case .agora: return "agora"
        case .atras(let m): return "atras_\(m)min"
        case .horario: return "horario_escolhido"
        }
    }
}

/// O que viaja no corpo do turno quando o sujeito declarou o instante.
///
/// Ausente = não declarado. O servidor não deve inventar este objeto em nenhuma hipótese: ele
/// existe para carregar uma afirmação do sujeito, e um valor de origem diferente com o mesmo
/// nome tornaria a afirmação indistinguível de um palpite — que é exatamente o defeito que ele
/// conserta.
public struct InstanteDeclarado: Equatable, Sendable {
    public let instante: Date
    public let ancora: String

    public init(instante: Date, ancora: String) {
        self.instante = instante
        self.ancora = ancora
    }

    public init?(ancora: AncoraTemporal?, agora referencia: Date = Date()) {
        guard let ancora else { return nil }
        self.instante = ancora.instante(agora: referencia)
        self.ancora = ancora.chave
    }

    /// ISO 8601 com fuso — o servidor precisa do deslocamento, não de um horário solto.
    public var instanteISO: String { Self.iso.string(from: instante) }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Os campos do corpo JSON. Nomes casados com o que o cockpit repassa ao `capture_turn`.
    public var camposJSON: [String: String] {
        ["state_occurred_at": instanteISO, "state_anchor": ancora]
    }
}

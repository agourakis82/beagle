//
//  PresenceState.swift
//  BeagleCore — o estado da presença, e o ritmo dela
//
//  Dois tipos e um resolvedor puro. Nenhum deles toca UI, rede ou HealthKit —
//  por isso dá para testar em tabela.
//
//  O ponto do `PresenceBreath` é fechar um furo antigo: AuroraPresence caía em
//  `breathRate ?? 5.5` e CompanionMotion em `4.4`, ou seja, quando o Physiome
//  estava MUDO o companion respirava um ritmo inventado, indistinguível de um
//  ritmo medido. Com um enum de dois casos não existe um `Double?` que possa
//  escorregar para um default silencioso: ou o dado foi observado (e traz
//  QUANDO foi observado), ou o caso é declaradamente `.neutral` — e `.neutral`
//  é visualmente distinto, não só numericamente.
//

import Foundation

// MARK: - Estado

/// Os quatro estados-base da presença. O rawValue é o nome do laço no bundle.
public enum PresenceState: String, Sendable, Equatable, CaseIterable {
    /// Ninguém olhando: app em background, ou parado há bastante tempo.
    case adormecido
    /// Repouso acordado — o estado normal enquanto se lê a conversa.
    case atento
    /// Você está entrando com alguma coisa (voz ou composer com foco).
    case ouvindo
    /// O companion está gerando resposta.
    case pensando

    // MARK: Transição — tocam UMA vez e devolvem ao base
    /// Ao abrir o app: ele acorda para você.
    case despertar
    /// Ele te viu — logo depois de despertar.
    case reconhecendo
    /// Você saindo.
    case adormecendo

    // MARK: Registro emocional
    //
    // INVARIANTE do desenho: isto reage ao que VOCÊ ESCREVEU, nunca a uma
    // inferência sobre o seu estado. Ele responde ao que ouviu; não diagnostica
    // o seu humor. A diferença não é sutil: uma é escuta, a outra é vigilância.
    case acolhendo
    case celebrando
    case preocupado
    case silencio
    case firme

    // MARK: Trabalho interno — o que ele está fazendo por dentro
    case buscando
    case sintetizando
    case escutandoLongo = "escutando-longo"

    // MARK: Céu e corpo — só com DADO MEDIDO, nunca inventado
    case tempestade
    case madrugada
    case manha

    // MARK: Especial
    /// Faixa de 28px: só o olhar.
    case olhar

    public enum Grupo: Sendable {
        case base, transicao, emocao, trabalho, ceuCorpo, especial
    }

    public var grupo: Grupo {
        switch self {
        case .adormecido, .atento, .ouvindo, .pensando: return .base
        case .despertar, .reconhecendo, .adormecendo: return .transicao
        case .acolhendo, .celebrando, .preocupado, .silencio, .firme: return .emocao
        case .buscando, .sintetizando, .escutandoLongo: return .trabalho
        case .tempestade, .madrugada, .manha: return .ceuCorpo
        case .olhar: return .especial
        }
    }

    /// Transição toca uma vez e volta ao base; o resto fica em laço.
    public var tocaUmaVez: Bool { grupo == .transicao }

    /// Nome do recurso no bundle (`st-atento.mp4` / `lp-acolhendo.mp4`).
    public var loopResource: String {
        grupo == .base ? "st-\(rawValue)" : "lp-\(rawValue)"
    }

    /// Os quatro base são embarcados e sempre existem; o resto pode faltar num
    /// build enxuto. Quem consome DEVE cair para o base em vez de sumir.
    public var baseDeQueda: PresenceState {
        switch grupo {
        case .base: return self
        case .transicao: return .atento
        case .emocao: return .atento
        case .trabalho: return .pensando
        case .ceuCorpo: return .atento
        case .especial: return .atento
        }
    }
}

// MARK: - Respiração

/// O ritmo que anima a presença.
///
/// `.measured` exige bpm **e** o instante da observação: sem `observedAt` o dado
/// não é observado, é palpite. `.neutral` é o caso honesto de "não sei" — e tem
/// amplitude menor de propósito, para que "sem dado" não se pareça com "com dado".
public enum PresenceBreath: Sendable, Equatable {
    case measured(bpm: Double, at: Date)
    case neutral

    /// Período neutro, em segundos. NÃO é uma estimativa do usuário: é um ritmo
    /// declaradamente arbitrário, lento, usado só quando não há medida.
    public static let neutralPeriod: Double = 6.0

    /// Idade máxima padrão de uma medida antes de deixar de valer como observação.
    public static let defaultMaxAge: TimeInterval = 30 * 60

    public var isMeasured: Bool {
        if case .measured = self { return true }
        return false
    }

    /// bpm quando medido; `nil` quando neutro. Nunca inventa.
    public var bpm: Double? {
        if case let .measured(bpm, _) = self { return bpm }
        return nil
    }

    public var observedAt: Date? {
        if case let .measured(_, at) = self { return at }
        return nil
    }

    /// Período do ciclo em segundos. Medidas absurdas (derivadas de HR) são
    /// grampeadas em 4–20 bpm para não quebrar a animação.
    public var period: Double {
        switch self {
        case let .measured(bpm, _):
            return 60.0 / max(4.0, min(20.0, bpm))
        case .neutral:
            return Self.neutralPeriod
        }
    }

    /// Multiplicador de amplitude. O caso neutro respira MENOS fundo — é assim
    /// que "não sei" fica visível sem escrever nada na tela.
    public var amplitude: Double {
        switch self {
        case .measured: return 1.0
        case .neutral:  return 0.45
        }
    }

    /// Constrói a partir de um par opcional. Os DOIS precisam existir.
    public static func from(bpm: Double?, observedAt: Date?) -> PresenceBreath {
        guard let bpm, let observedAt, bpm >= 4 else { return .neutral }
        return .measured(bpm: bpm, at: observedAt)
    }

    /// Uma medida velha demais deixa de ser observação. Sem isto, uma leitura de
    /// ontem continuaria fingindo ser o batimento de agora.
    public func resolved(now: Date, maxAge: TimeInterval = PresenceBreath.defaultMaxAge) -> PresenceBreath {
        guard case let .measured(_, at) = self else { return .neutral }
        return now.timeIntervalSince(at) <= maxAge ? self : .neutral
    }
}

// MARK: - Resolvedor

/// Entradas → `PresenceState`. Puro, `Sendable`, sem relógio interno: quem chama
/// passa `now`, para o teste poder fixar o tempo.
public struct PresenceResolver: Sendable, Equatable {
    /// O companion está gerando resposta.
    public var isStreaming: Bool
    /// Captura de voz aberta.
    public var isVoiceListening: Bool
    /// Composer com foco de teclado (o usuário está compondo).
    public var composerFocused: Bool
    /// `scenePhase == .active`.
    public var isActive: Bool
    /// Última interação do usuário. `nil` → nunca interagiu nesta sessão.
    public var lastInteraction: Date?
    /// Silêncio a partir do qual a presença adormece.
    public var idleThreshold: TimeInterval
    /// Recall em curso.
    public var buscandoMemoria: Bool
    /// Síntese proativa em curso.
    public var sintetizando: Bool
    /// Modo voz de escuta longa.
    public var vozLonga: Bool
    /// O QUE ELE ESCREVEU por último. Texto, não inferência sobre ele.
    public var ultimaFalaDele: String?
    /// Hora local 0-23. `nil` = não sei, e não sei fica no base.
    public var hora: Int?
    /// Kp medido. `nil` = não sei, e não sei NÃO vira tempestade.
    public var kp: Double?

    public init(isStreaming: Bool = false,
                isVoiceListening: Bool = false,
                composerFocused: Bool = false,
                isActive: Bool = true,
                lastInteraction: Date? = nil,
                idleThreshold: TimeInterval = 150,
                buscandoMemoria: Bool = false,
                sintetizando: Bool = false,
                vozLonga: Bool = false,
                ultimaFalaDele: String? = nil,
                hora: Int? = nil,
                kp: Double? = nil) {
        self.isStreaming = isStreaming
        self.isVoiceListening = isVoiceListening
        self.composerFocused = composerFocused
        self.isActive = isActive
        self.lastInteraction = lastInteraction
        self.idleThreshold = idleThreshold
        self.buscandoMemoria = buscandoMemoria
        self.sintetizando = sintetizando
        self.vozLonga = vozLonga
        self.ultimaFalaDele = ultimaFalaDele
        self.hora = hora
        self.kp = kp
    }

    /// Precedência, do mais forte para o mais fraco:
    ///   1. fora de `.active` → adormecido (a tela nem está na frente)
    ///   2. streaming        → pensando  (vence "ouvindo": ele está falando)
    ///   3. voz OU composer  → ouvindo
    ///   4. ocioso demais    → adormecido
    ///   5. resto            → atento
    /// Ocioso é decidido AQUI porque depende de `now`; o resto delega ao
    /// resolvedor puro. Dois resolvedores com regras próprias divergiriam em
    /// silêncio — e a divergência apareceria como o bicho mostrando um humor que
    /// a tabela de teste diz ser outro.
    public func state(now: Date) -> PresenceState {
        if !isActive { return .adormecido }
        let ocupado = isStreaming || isVoiceListening || composerFocused
                   || buscandoMemoria || sintetizando || vozLonga
        if !ocupado, let last = lastInteraction,
           now.timeIntervalSince(last) > idleThreshold { return .adormecido }
        return PresenceState.resolver(PresenceEntrada(
            appAtivo: isActive,
            compondo: isVoiceListening || composerFocused,
            gerando: isStreaming,
            buscandoMemoria: buscandoMemoria,
            sintetizando: sintetizando,
            vozLonga: vozLonga,
            ultimaFalaDele: ultimaFalaDele,
            hora: hora,
            kp: kp))
    }
}

// MARK: - Quem dispara o quê

/// Tudo que a presença precisa saber. Sem UI, sem rede, sem HealthKit dentro —
/// por isso o resolvedor cabe numa tabela de teste.
public struct PresenceEntrada: Sendable {
    public var appAtivo: Bool
    /// Composer com foco, ou captura de voz em curso.
    public var compondo: Bool
    /// O companion está gerando resposta.
    public var gerando: Bool
    public var buscandoMemoria: Bool
    public var sintetizando: Bool
    /// Modo voz de escuta longa.
    public var vozLonga: Bool
    /// O QUE ELE ESCREVEU. Não é leitura do estado dele — é o texto.
    public var ultimaFalaDele: String?
    /// Hora local, 0-23. `nil` = não sei.
    public var hora: Int?
    /// Índice geomagnético medido. `nil` = não sei — e não sei não vira tempestade.
    public var kp: Double?

    public init(appAtivo: Bool = true, compondo: Bool = false, gerando: Bool = false,
                buscandoMemoria: Bool = false, sintetizando: Bool = false,
                vozLonga: Bool = false, ultimaFalaDele: String? = nil,
                hora: Int? = nil, kp: Double? = nil) {
        self.appAtivo = appAtivo; self.compondo = compondo; self.gerando = gerando
        self.buscandoMemoria = buscandoMemoria; self.sintetizando = sintetizando
        self.vozLonga = vozLonga; self.ultimaFalaDele = ultimaFalaDele
        self.hora = hora; self.kp = kp
    }
}

public extension PresenceState {

    /// Reage ao que ele ESCREVEU. Nunca infere o estado dele a partir de outra
    /// coisa — nem do batimento, nem da hora, nem de histórico. Se a palavra não
    /// está no texto, não há emoção a mostrar.
    ///
    /// `firme` fica de fora de propósito: no desenho ela é "ele te contrariando",
    /// isto é, uma propriedade da RESPOSTA dele, não do que você escreveu.
    static func emocao(daFala texto: String?) -> PresenceState? {
        guard let t = texto?
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR")),
              !t.isEmpty else { return nil }

        // Conjugação importa: a frase que mais importa acertar é \"acabou de
        // MORRER um paciente meu\", e uma lista só com \"morreu\" a perde. Evito
        // o radical \"morr\" porque ele casaria com \"morro de rir\".
        let acolher = ["morreu", "morrer", "morrendo", "morri", "perdi", "faleceu",
                       "sozinho", "sozinha", "triste", "chorando", "chorar",
                       "nao aguento", "exausto", "exausta", "cansado", "cansada"]
        let celebrar = ["consegui", "deu certo", "funcionou", "passou", "aprovad", "ganhei",
                        "consegimos", "conseguimos", "finalmente", "deu bom"]
        let preocupar = ["medo", "ansios", "aflito", "aflita", "tenso", "tensa", "urgente",
                         "nao sei o que fazer", "piorou", "grave"]
        let calar = ["so queria", "nao sei o que dizer", "fica comigo", "so quero silencio",
                     "nao quero falar"]

        if calar.contains(where: t.contains) { return .silencio }
        if acolher.contains(where: t.contains) { return .acolhendo }
        if preocupar.contains(where: t.contains) { return .preocupado }
        if celebrar.contains(where: t.contains) { return .celebrando }
        return nil
    }

    /// A ordem importa e é o desenho inteiro em dez linhas.
    ///
    /// Trabalho interno ganha de tudo enquanto acontece (ele está fazendo algo, e
    /// mostrar isso é honestidade sobre a espera). Emoção só aparece enquanto ele
    /// responde — é reação à fala, não um humor de fundo. Céu e corpo são o
    /// último recurso, e só com dado: sem medida, fica no base.
    static func resolver(_ e: PresenceEntrada) -> PresenceState {
        if !e.appAtivo { return .adormecido }
        if e.sintetizando { return .sintetizando }
        if e.buscandoMemoria { return .buscando }
        if e.vozLonga { return .escutandoLongo }
        if e.gerando { return emocao(daFala: e.ultimaFalaDele) ?? .pensando }
        if e.compondo { return .ouvindo }
        if let kp = e.kp, kp >= 5 { return .tempestade }
        if let h = e.hora {
            if h >= 0 && h < 5 { return .madrugada }
            if h >= 5 && h < 9 { return .manha }
        }
        return .atento
    }
}
